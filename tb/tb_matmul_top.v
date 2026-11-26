// -----------------------------------------------------------------------------
// tb_matmul_top.v - Testbench for the matrix data interface (Phase II)
//
// Writes A and B one element at a time through matmul_top's narrow port,
// pulses start, waits for done, reads C back one element at a time and checks
// it against the reference model. Runs the systolic core (ARCH = 0) and the
// sequential baseline (ARCH = 1) side by side.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_matmul_top;

    parameter N       = 4;
    parameter DATA_W  = 8;
    parameter ACC_W   = 24;
    parameter NUM_MAT = 20;
    localparam ADDR_W = $clog2(N*N);

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg               rst = 1'b1, we = 1'b0, sel_b = 1'b0, start = 1'b0;
    reg  [ADDR_W-1:0] addr = 0, raddr = 0;
    reg  [DATA_W-1:0] wdata = 0;
    wire [ACC_W-1:0]  rdata_sys, rdata_seq;
    wire              busy_sys, done_sys, busy_seq, done_seq;

    matmul_top #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W), .ARCH(0)) u_sys (
        .clk(clk), .rst(rst), .we(we), .sel_b(sel_b), .addr(addr), .wdata(wdata),
        .start(start), .raddr(raddr), .rdata(rdata_sys), .busy(busy_sys), .done(done_sys));

    matmul_top #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W), .ARCH(1)) u_seq (
        .clk(clk), .rst(rst), .we(we), .sel_b(sel_b), .addr(addr), .wdata(wdata),
        .start(start), .raddr(raddr), .rdata(rdata_seq), .busy(busy_seq), .done(done_seq));

    reg signed [DATA_W-1:0] A [0:N*N-1];
    reg signed [DATA_W-1:0] B [0:N*N-1];
    reg signed [ACC_W-1:0]  expect_c, got_sys, got_seq;
    integer m, idx, k, seed, checks, errors;

    task write_elem;
        input             is_b;
        input integer     index;
        input [DATA_W-1:0] value;
        begin
            we = 1'b1; sel_b = is_b; addr = index; wdata = value;
            @(negedge clk);
            we = 1'b0;
        end
    endtask

    initial begin
        checks = 0; errors = 0; seed = 7;
        repeat (3) @(negedge clk);
        rst = 1'b0;

        for (m = 0; m < NUM_MAT; m = m + 1) begin
            for (idx = 0; idx < N*N; idx = idx + 1) begin
                A[idx] = $random(seed);
                B[idx] = $random(seed);
                write_elem(1'b0, idx, A[idx]);
                write_elem(1'b1, idx, B[idx]);
            end

            start = 1'b1; @(negedge clk); start = 1'b0;
            repeat (3) @(negedge clk);                   // start passes the input register
            while (!(done_sys === 1'b1 && done_seq === 1'b1)) @(negedge clk);

            for (idx = 0; idx < N*N; idx = idx + 1) begin
                expect_c = 0;
                for (k = 0; k < N; k = k + 1)
                    expect_c = expect_c + A[(idx / N)*N + k] * B[k*N + (idx % N)];
                raddr = idx;
                repeat (3) @(negedge clk);               // input register + output register
                got_sys = rdata_sys;
                got_seq = rdata_seq;
                checks = checks + 1;
                if (got_sys !== expect_c || got_seq !== expect_c) begin
                    errors = errors + 1;
                    $display("FAIL matrix %0d C[%0d][%0d]: systolic %0d, sequential %0d, expected %0d",
                             m, idx / N, idx % N, got_sys, got_seq, expect_c);
                end
            end
        end

        $display("==============================================================");
        if (errors == 0)
            $display(" MATRIX DATA INTERFACE: ALL %0d ELEMENTS CORRECT (%0d matrices, both cores)",
                     checks, NUM_MAT);
        else
            $display(" MATRIX DATA INTERFACE: %0d of %0d ELEMENTS WRONG", errors, checks);
        $display("==============================================================");
        $finish;
    end

endmodule
