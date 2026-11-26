// -----------------------------------------------------------------------------
// matmul_top.v - Matrix Data Interface + accelerator (FPGA top level, Phase II)
//
// matmul_accel takes both matrices and returns the result on wide parallel
// buses: 2*N*N*DATA_W + N*N*ACC_W bits (640 pins for N = 4), far more than
// any FPGA package has. This wrapper gives it a small register-mapped port,
// as it would have behind a UART, SPI or AXI-Lite bridge on a board:
//
//   write :  we = 1, sel_b = 0 (A) or 1 (B), addr = i*N + j, wdata = element
//   run   :  pulse start, wait for done
//   read  :  raddr = i*N + j  ->  rdata = C[i][j] (two clocks later)
//
// ARCH = 0 : systolic array (matmul_accel)      BUFFERED passes through to it
// ARCH = 1 : sequential baseline (seq_matmul)
//
// All inputs and outputs are registered, so the clock frequency measured on
// this top level is set by the accelerator core, not by the I/O pins.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module matmul_top #(
    parameter N        = 4,
    parameter DATA_W   = 8,
    parameter ACC_W    = 24,
    parameter ARCH     = 0,
    parameter BUFFERED = 1,
    parameter ADDR_W   = (N*N > 1) ? $clog2(N*N) : 1
) (
    input  wire              clk,
    input  wire              rst,
    input  wire              we,
    input  wire              sel_b,
    input  wire [ADDR_W-1:0] addr,
    input  wire [DATA_W-1:0] wdata,
    input  wire              start,
    input  wire [ADDR_W-1:0] raddr,
    output reg  [ACC_W-1:0]  rdata,
    output reg               busy,
    output reg               done
);

    // ---- input registers ----
    reg              we_r, sel_b_r, start_r;
    reg [ADDR_W-1:0] addr_r, raddr_r;
    reg [DATA_W-1:0] wdata_r;

    always @(posedge clk) begin
        if (rst) begin
            we_r <= 1'b0; sel_b_r <= 1'b0; start_r <= 1'b0;
            addr_r <= 0;  raddr_r <= 0;    wdata_r <= 0;
        end else begin
            we_r <= we;   sel_b_r <= sel_b; start_r <= start;
            addr_r <= addr; raddr_r <= raddr; wdata_r <= wdata;
        end
    end

    // ---- matrix register files ----
    reg [N*N*DATA_W-1:0] a_mem, b_mem;

    always @(posedge clk) begin
        if (rst) begin
            a_mem <= 0;
            b_mem <= 0;
        end else if (we_r) begin
            if (sel_b_r) b_mem[addr_r*DATA_W +: DATA_W] <= wdata_r;
            else         a_mem[addr_r*DATA_W +: DATA_W] <= wdata_r;
        end
    end

    // ---- accelerator core ----
    wire [N*N*ACC_W-1:0] c_flat;
    wire                 core_busy, core_done;

    generate
        if (ARCH == 0) begin : g_systolic
            matmul_accel #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W), .BUFFERED(BUFFERED)) u_core (
                .clk(clk), .rst(rst), .start(start_r),
                .a_flat(a_mem), .b_flat(b_mem), .c_flat(c_flat),
                .busy(core_busy), .done(core_done)
            );
        end else begin : g_sequential
            seq_matmul #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) u_core (
                .clk(clk), .rst(rst), .start(start_r),
                .a_flat(a_mem), .b_flat(b_mem), .c_flat(c_flat),
                .busy(core_busy), .done(core_done)
            );
        end
    endgenerate

    // ---- output registers ----
    always @(posedge clk) begin
        if (rst) begin
            rdata <= 0; busy <= 1'b0; done <= 1'b0;
        end else begin
            rdata <= c_flat[raddr_r*ACC_W +: ACC_W];
            busy  <= core_busy;
            done  <= core_done;
        end
    end

endmodule
