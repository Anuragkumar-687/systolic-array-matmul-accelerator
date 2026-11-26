// -----------------------------------------------------------------------------
// matmul_accel.v - Systolic matrix multiplication accelerator (top level)
//
// Computes C = A x B for N x N signed matrices.
//
//   start --> operands are latched, the array is cleared
//   busy  --> high for 3N-2 cycles while the skewed wavefront crosses the mesh
//   done  --> goes high when c_flat is valid, stays high until the next start
//
// Input skewing: row i of A is delayed by i cycles, column j of B is delayed
// by j cycles, so A[i][k] and B[k][j] meet in PE(i,j) at cycle t = i + j + k.
//
// Flattening convention: element [r][c] lives at index (r*N + c).
//
// Input feeders (parameter BUFFERED):
//   1 (default, Phase II) : one skew_buffer shift register per lane. On start
//                           row i of A / column i of B is loaded behind i zero
//                           slots and shifted out one element per cycle.
//   0 (Phase I)           : the original multiplexers, which pick element
//                           k = t - i with the cycle counter. Kept so that both
//                           versions can be simulated and synthesised side by side.
// Both produce the same lane values in every cycle, so latency is 3N-1 either way.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module matmul_accel #(
    parameter N      = 4,
    parameter DATA_W = 8,
    parameter ACC_W  = 24,
    parameter BUFFERED = 1      // 1 = shift-register input buffers, 0 = Phase I muxes
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     start,
    input  wire [N*N*DATA_W-1:0]    a_flat,
    input  wire [N*N*DATA_W-1:0]    b_flat,
    output wire [N*N*ACC_W-1:0]     c_flat,
    output wire                     busy,
    output reg                      done
);

    localparam integer LAST = 3*N - 3;          // last compute cycle index
    localparam integer CNT_W = 16;

    localparam S_IDLE = 1'b0;
    localparam S_RUN  = 1'b1;

    reg                     state;
    reg [CNT_W-1:0]         t;                  // cycle counter
    reg [N*N*DATA_W-1:0]    a_q, b_q;           // latched operands

    wire accept = (state == S_IDLE) && start;
    wire en     = (state == S_RUN);

    assign busy = en;

    // ---------------- controller ----------------
    always @(posedge clk) begin
        if (rst) begin
            state <= S_IDLE;
            t     <= {CNT_W{1'b0}};
            done  <= 1'b0;
            a_q   <= {(N*N*DATA_W){1'b0}};
            b_q   <= {(N*N*DATA_W){1'b0}};
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        if (!BUFFERED) begin    // the buffers keep their own copy
                            a_q <= a_flat;
                            b_q <= b_flat;
                        end
                        t     <= {CNT_W{1'b0}};
                        done  <= 1'b0;
                        state <= S_RUN;
                    end
                end
                S_RUN: begin
                    if (t == LAST) begin
                        done  <= 1'b1;
                        state <= S_IDLE;
                    end else begin
                        t <= t + 1'b1;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    // ---------------- skewed input feeders ----------------
    wire [N*DATA_W-1:0] a_edge;
    wire [N*DATA_W-1:0] b_edge;

    genvar i, r;
    generate
        if (BUFFERED) begin : g_buf
            // Phase II: input buffers (one shift register per lane)
            for (i = 0; i < N; i = i + 1) begin : g_lane
                // gather column i of B: element k is B[k][i]
                wire [N*DATA_W-1:0] b_col;
                for (r = 0; r < N; r = r + 1) begin : g_col
                    assign b_col[r*DATA_W +: DATA_W] = b_flat[(r*N + i)*DATA_W +: DATA_W];
                end

                skew_buffer #(.N(N), .DATA_W(DATA_W), .DELAY(i)) u_abuf (
                    .clk      (clk),
                    .rst      (rst),
                    .load     (accept),
                    .shift    (en),
                    .din_flat (a_flat[i*N*DATA_W +: N*DATA_W]),   // row i of A
                    .dout     (a_edge[i*DATA_W +: DATA_W])
                );
                skew_buffer #(.N(N), .DATA_W(DATA_W), .DELAY(i)) u_bbuf (
                    .clk      (clk),
                    .rst      (rst),
                    .load     (accept),
                    .shift    (en),
                    .din_flat (b_col),                            // column i of B
                    .dout     (b_edge[i*DATA_W +: DATA_W])
                );
            end
        end else begin : g_mux
            // Phase I: counter-driven multiplexers
            for (i = 0; i < N; i = i + 1) begin : g_feed
                // lane i is active for cycles i .. i+N-1
                wire        valid = en && (t >= i) && (t < i + N);
                wire [31:0] k     = valid ? (t - i) : 32'd0;

                // row i of A:    A[i][k]
                assign a_edge[i*DATA_W +: DATA_W] =
                    valid ? a_q[(i*N + k)*DATA_W +: DATA_W] : {DATA_W{1'b0}};
                // column i of B: B[k][i]
                assign b_edge[i*DATA_W +: DATA_W] =
                    valid ? b_q[(k*N + i)*DATA_W +: DATA_W] : {DATA_W{1'b0}};
            end
        end
    endgenerate

    // ---------------- systolic mesh ----------------
    systolic_array #(
        .N      (N),
        .DATA_W (DATA_W),
        .ACC_W  (ACC_W)
    ) u_array (
        .clk    (clk),
        .rst    (rst),
        .clr    (accept),
        .en     (en),
        .a_edge (a_edge),
        .b_edge (b_edge),
        .c_flat (c_flat)
    );

endmodule
