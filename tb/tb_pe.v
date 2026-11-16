// -----------------------------------------------------------------------------
// tb_pe.v - unit testbench for a single processing element
//
// Checks the multiply-accumulate behaviour of one PE on its own, before it is
// used inside the array:
//   - reset and clr bring acc / a_out / b_out to zero
//   - one MAC per enabled clock, operands forwarded unchanged
//   - en = 0 holds all state
//   - signed corner cases
//   - random stimulus against a small behavioural model
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_pe;

    parameter DATA_W     = 8;
    parameter ACC_W      = 24;
    parameter NUM_RANDOM = 500;

    reg                      clk = 1'b0;
    reg                      rst = 1'b1;
    reg                      clr = 1'b0;
    reg                      en  = 1'b0;
    reg  signed [DATA_W-1:0] a_in = 0;
    reg  signed [DATA_W-1:0] b_in = 0;
    wire signed [DATA_W-1:0] a_out;
    wire signed [DATA_W-1:0] b_out;
    wire signed [ACC_W-1:0]  acc;

    pe #(
        .DATA_W (DATA_W),
        .ACC_W  (ACC_W)
    ) dut (
        .clk   (clk),
        .rst   (rst),
        .clr   (clr),
        .en    (en),
        .a_in  (a_in),
        .b_in  (b_in),
        .a_out (a_out),
        .b_out (b_out),
        .acc   (acc)
    );

    always #5 clk = ~clk;

    integer checks, errors, n, seed;

    // behavioural model used for the random part
    reg signed [ACC_W-1:0]  m_acc;
    reg signed [DATA_W-1:0] m_a, m_b;
    reg signed [DATA_W-1:0] ra, rb;
    reg                     re, rc;

    // drive inputs for one clock cycle (called on a negedge, returns on the next)
    task step;
        input signed [DATA_W-1:0] a;
        input signed [DATA_W-1:0] b;
        input                     e;
        input                     c;
        begin
            a_in = a; b_in = b; en = e; clr = c;
            @(negedge clk);
        end
    endtask

    task check;
        input [8*24-1:0]          what;
        input signed [ACC_W-1:0]  exp_acc;
        input signed [DATA_W-1:0] exp_a;
        input signed [DATA_W-1:0] exp_b;
        begin
            checks = checks + 1;
            if (acc !== exp_acc || a_out !== exp_a || b_out !== exp_b) begin
                errors = errors + 1;
                $display("[FAIL] %0s: acc=%0d a_out=%0d b_out=%0d (expected %0d, %0d, %0d)",
                         what, acc, a_out, b_out, exp_acc, exp_a, exp_b);
            end else begin
                $display("[PASS] %0s: acc=%0d a_out=%0d b_out=%0d",
                         what, acc, a_out, b_out);
            end
        end
    endtask

    initial begin
        $dumpfile("pe_waves.vcd");
        $dumpvars(0, tb_pe);

        checks = 0; errors = 0; seed = 32'h0BAD_CAFE;

        $display("==============================================================");
        $display(" Processing element unit test (DATA_W = %0d, ACC_W = %0d)", DATA_W, ACC_W);
        $display("==============================================================");

        // reset
        @(negedge clk);
        @(negedge clk);
        check("reset", 0, 0, 0);
        rst = 1'b0;

        // directed MAC sequence: expected values worked out by hand
        step(3, 4, 1, 0);        check("3 x 4",          12,    3,    4);
        step(5, -6, 1, 0);       check("+ 5 x -6",       -18,   5,   -6);
        step(7, 7, 0, 0);        check("en=0 holds",     -18,   5,   -6);
        step(-128, -128, 1, 0);  check("+ -128 x -128",  16366, -128, -128);
        step(-128, 127, 1, 0);   check("+ -128 x 127",   110,   -128, 127);
        step(127, 127, 1, 0);    check("+ 127 x 127",    16239, 127,  127);
        step(0, 55, 1, 0);       check("+ 0 x 55",       16239, 0,    55);
        step(9, 9, 1, 1);        check("clr wins over en", 0,   0,    0);
        step(2, 10, 1, 0);       check("2 x 10 after clr", 20,  2,    10);
        step(0, 0, 0, 1);        check("clr",            0,     0,    0);

        // random stimulus with random en and occasional clr
        m_acc = 0; m_a = 0; m_b = 0;
        for (n = 0; n < NUM_RANDOM; n = n + 1) begin
            ra = $random(seed);
            rb = $random(seed);
            re = ($random(seed) & 3) != 0;     // enabled 3 cycles out of 4
            rc = ($random(seed) & 31) == 0;    // clear about once in 32 cycles

            if (rc) begin
                m_acc = 0; m_a = 0; m_b = 0;
            end else if (re) begin
                m_acc = m_acc + ra * rb;
                m_a   = ra;
                m_b   = rb;
            end

            step(ra, rb, re, rc);

            checks = checks + 1;
            if (acc !== m_acc || a_out !== m_a || b_out !== m_b) begin
                errors = errors + 1;
                $display("[FAIL] random #%0d: acc=%0d a_out=%0d b_out=%0d (expected %0d, %0d, %0d)",
                         n, acc, a_out, b_out, m_acc, m_a, m_b);
            end
        end
        $display("    ... %0d random cycles checked against the model", NUM_RANDOM);

        $display("==============================================================");
        if (errors == 0)
            $display(" ALL %0d PE CHECKS PASSED", checks);
        else
            $display(" %0d of %0d PE CHECKS FAILED", errors, checks);
        $display("==============================================================");
        $finish;
    end

endmodule
