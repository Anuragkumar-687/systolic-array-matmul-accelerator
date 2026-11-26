// -----------------------------------------------------------------------------
// tb_skew_buffer.v - unit testbench for skew_buffer (Phase II input buffer)
//
// Instantiates three skew_buffer instances with DELAY = 0, 1 and 3 and checks:
//   - synchronous reset clears all outputs to zero
//   - load + shift produces DELAY zeros, then d[0]..d[N-1], then trailing zeros
//   - shift = 0 holds state unchanged mid-stream
//   - load = 1 while shift = 1 reloads immediately (load has priority)
//   - rst = 1 mid-stream clears all buffered values
//   - random stimulus against a behavioural reference model
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_skew_buffer;

    parameter N          = 4;
    parameter DATA_W     = 8;
    parameter NUM_RANDOM = 200;

    reg                   clk      = 1'b0;
    reg                   rst      = 1'b1;
    reg                   load     = 1'b0;
    reg                   shift    = 1'b0;
    reg  [N*DATA_W-1:0]   din_flat = 0;

    wire [DATA_W-1:0]     dout0;
    wire [DATA_W-1:0]     dout1;
    wire [DATA_W-1:0]     dout3;

    skew_buffer #(.N(N), .DATA_W(DATA_W), .DELAY(0)) dut0 (
        .clk(clk), .rst(rst), .load(load), .shift(shift),
        .din_flat(din_flat), .dout(dout0)
    );

    skew_buffer #(.N(N), .DATA_W(DATA_W), .DELAY(1)) dut1 (
        .clk(clk), .rst(rst), .load(load), .shift(shift),
        .din_flat(din_flat), .dout(dout1)
    );

    skew_buffer #(.N(N), .DATA_W(DATA_W), .DELAY(3)) dut3 (
        .clk(clk), .rst(rst), .load(load), .shift(shift),
        .din_flat(din_flat), .dout(dout3)
    );

    always #5 clk = ~clk;

    integer checks, errors, cyc, seed;

    // behavioural reference shift registers for the random phase
    reg [(N+0)*DATA_W-1:0] ref0;
    reg [(N+1)*DATA_W-1:0] ref1;
    reg [(N+3)*DATA_W-1:0] ref3;
    reg [N*DATA_W-1:0]     r_din;
    reg                    r_rst, r_load, r_shift;

    // pack 4 elements (d0 in low bits) into din_flat
    function [N*DATA_W-1:0] pack4;
        input [DATA_W-1:0] d0, d1, d2, d3;
        begin
            pack4 = {d3, d2, d1, d0};
        end
    endfunction

    // drive inputs for one clock cycle (called on negedge, returns on next)
    task step;
        input                 r;
        input                 l;
        input                 s;
        input [N*DATA_W-1:0]  d;
        begin
            rst = r; load = l; shift = s; din_flat = d;
            @(negedge clk);
        end
    endtask

    task check;
        input [8*28-1:0]   what;
        input [DATA_W-1:0] exp0;
        input [DATA_W-1:0] exp1;
        input [DATA_W-1:0] exp3;
        begin
            checks = checks + 1;
            if (dout0 !== exp0 || dout1 !== exp1 || dout3 !== exp3) begin
                errors = errors + 1;
                $display("[FAIL] %0s: dout(0,1,3)=(%0d, %0d, %0d) expected (%0d, %0d, %0d)",
                         what, dout0, dout1, dout3, exp0, exp1, exp3);
            end else begin
                $display("[PASS] %0s: dout(0,1,3)=(%0d, %0d, %0d)",
                         what, dout0, dout1, dout3);
            end
        end
    endtask

    initial begin
        $dumpfile("skew_waves.vcd");
        $dumpvars(0, tb_skew_buffer);

        checks = 0; errors = 0; seed = 32'h5CE0_2026;

        $display("==============================================================");
        $display(" Skew buffer unit test (N = %0d, DATA_W = %0d, DELAY = 0, 1, 3)",
                 N, DATA_W);
        $display("==============================================================");

        // 1. reset
        @(negedge clk);
        @(negedge clk);
        check("reset", 0, 0, 0);

        // 2. load [10, 20, 30, 40] and shift out through trailing zeros
        step(0, 1, 0, pack4(8'd10, 8'd20, 8'd30, 8'd40));
        check("load [10,20,30,40]", 10,  0,  0);
        step(0, 0, 1, 0); check("shift 1",          20, 10,  0);
        step(0, 0, 1, 0); check("shift 2",          30, 20,  0);
        step(0, 0, 1, 0); check("shift 3",          40, 30, 10);
        step(0, 0, 1, 0); check("shift 4",           0, 40, 20);
        step(0, 0, 1, 0); check("shift 5",           0,  0, 30);
        step(0, 0, 1, 0); check("shift 6",           0,  0, 40);
        step(0, 0, 1, 0); check("shift 7 (zeros)",   0,  0,  0);
        step(0, 0, 1, 0); check("shift 8 (zeros)",   0,  0,  0);

        // 3. holding when shift = 0 mid-stream
        step(0, 1, 0, pack4(8'd1, 8'd2, 8'd3, 8'd4));
        check("load [1,2,3,4]",      1,  0,  0);
        step(0, 0, 1, 0); check("shift before hold", 2,  1,  0);
        step(0, 0, 0, 0); check("hold (shift=0 #1)", 2,  1,  0);
        step(0, 0, 0, 0); check("hold (shift=0 #2)", 2,  1,  0);
        step(0, 0, 1, 0); check("resume shift",      3,  2,  0);
        step(0, 0, 1, 0); check("resume shift 2",    4,  3,  1);

        // 4. load while still shifting (load=1, shift=1): load wins
        step(0, 1, 1, pack4(8'd55, 8'd66, 8'd77, 8'd88));
        check("load while shifting", 55,  0,  0);
        step(0, 0, 1, 0); check("post-reload #1",    66, 55,  0);
        step(0, 0, 1, 0); check("post-reload #2",    77, 66,  0);
        step(0, 0, 1, 0); check("post-reload #3",    88, 77, 55);

        // 5. rst mid-stream clears all buffered values
        step(1, 0, 1, 0); check("rst mid-stream",     0,  0,  0);
        step(0, 0, 1, 0); check("shift after rst",    0,  0,  0);

        // 6. random stimulus against behavioural model
        ref0 = 0; ref1 = 0; ref3 = 0;
        for (cyc = 0; cyc < NUM_RANDOM; cyc = cyc + 1) begin
            r_din   = $random(seed);
            r_rst   = ($random(seed) & 31) == 0;
            r_load  = ($random(seed) & 7)  == 0;
            r_shift = ($random(seed) & 3)  != 0;

            if (r_rst) begin
                ref0 = 0;
                ref1 = 0;
                ref3 = 0;
            end else if (r_load) begin
                ref0 = r_din;
                ref1 = {{DATA_W{1'b0}}, r_din} << (1 * DATA_W);
                ref3 = {{(3*DATA_W){1'b0}}, r_din} << (3 * DATA_W);
            end else if (r_shift) begin
                ref0 = ref0 >> DATA_W;
                ref1 = ref1 >> DATA_W;
                ref3 = ref3 >> DATA_W;
            end

            step(r_rst, r_load, r_shift, r_din);

            checks = checks + 1;
            if (dout0 !== ref0[DATA_W-1:0] ||
                dout1 !== ref1[DATA_W-1:0] ||
                dout3 !== ref3[DATA_W-1:0]) begin
                errors = errors + 1;
                $display("[FAIL] random #%0d: dout=(%0d,%0d,%0d) expected (%0d,%0d,%0d)",
                         cyc, dout0, dout1, dout3,
                         ref0[DATA_W-1:0], ref1[DATA_W-1:0], ref3[DATA_W-1:0]);
            end
        end
        $display("    ... %0d random cycles checked against the model", NUM_RANDOM);

        $display("==============================================================");
        if (errors == 0)
            $display(" ALL %0d SKEW BUFFER CHECKS PASSED", checks);
        else
            $display(" %0d of %0d SKEW BUFFER CHECKS FAILED", errors, checks);
        $display("==============================================================");
        $finish;
    end

endmodule
