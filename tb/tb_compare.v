// -----------------------------------------------------------------------------
// tb_compare.v - Systolic array vs. sequential baseline (Phase II)
//
// Three designs get the SAME matrices in the SAME clock cycle:
//   sys : matmul_accel, BUFFERED = 1 (Phase II input buffers)
//   mux : matmul_accel, BUFFERED = 0 (Phase I multiplexer feeders)
//   seq : seq_matmul   (one shared MAC, triple loop)
// Every result is checked against a behavioural reference model, and the
// latency (start -> done, in cycles) of each design is measured.
//
// Tests
//   1. identity x M           2. counting pattern       3. all -128
//   4. mixed-sign extremes    5. Q4.4 fixed point       6. NUM_RANDOM random
//   7. back-to-back throughput of the systolic array and of the baseline
//
//   make compare           (N = 4)        make compare N=3
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_compare;

    parameter N          = 4;
    parameter DATA_W     = 8;
    parameter ACC_W      = 24;
    parameter NUM_RANDOM = 200;
    parameter NUM_B2B    = 20;

    reg                    clk = 1'b0;
    reg                    rst = 1'b1;
    reg                    start = 1'b0;
    reg  [N*N*DATA_W-1:0]  a_flat = 0;
    reg  [N*N*DATA_W-1:0]  b_flat = 0;
    wire [N*N*ACC_W-1:0]   c_sys, c_mux, c_seq;
    wire                   busy_sys, busy_mux, busy_seq;
    wire                   done_sys, done_mux, done_seq;

    always #5 clk = ~clk;

    matmul_accel #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W), .BUFFERED(1)) u_sys (
        .clk(clk), .rst(rst), .start(start), .a_flat(a_flat), .b_flat(b_flat),
        .c_flat(c_sys), .busy(busy_sys), .done(done_sys));

    matmul_accel #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W), .BUFFERED(0)) u_mux (
        .clk(clk), .rst(rst), .start(start), .a_flat(a_flat), .b_flat(b_flat),
        .c_flat(c_mux), .busy(busy_mux), .done(done_mux));

    seq_matmul #(.N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)) u_seq (
        .clk(clk), .rst(rst), .start(start), .a_flat(a_flat), .b_flat(b_flat),
        .c_flat(c_seq), .busy(busy_seq), .done(done_seq));

    reg signed [DATA_W-1:0] A [0:N*N-1];
    reg signed [DATA_W-1:0] B [0:N*N-1];
    reg signed [ACC_W-1:0]  G [0:N*N-1];
    reg signed [ACC_W-1:0]  sum, got_sys, got_mux, got_seq;

    integer r, c, k, idx, n, seed;
    integer tests, failures, mism;
    integer lat_sys, lat_mux, lat_seq, cyc;
    integer t0, b2b_sys, b2b_seq;

    task golden;
        begin
            for (r = 0; r < N; r = r + 1)
                for (c = 0; c < N; c = c + 1) begin
                    sum = 0;
                    for (k = 0; k < N; k = k + 1)
                        sum = sum + A[r*N + k] * B[k*N + c];
                    G[r*N + c] = sum;
                end
        end
    endtask

    task pack;
        begin
            for (idx = 0; idx < N*N; idx = idx + 1) begin
                a_flat[idx*DATA_W +: DATA_W] = A[idx];
                b_flat[idx*DATA_W +: DATA_W] = B[idx];
            end
        end
    endtask

    // run all three designs on A and B, check, and measure latency
    task run_all;
        input [8*28-1:0] name;
        input integer    verbose;
        begin
            pack; golden;
            start = 1'b1;
            @(negedge clk); start = 1'b0;
            cyc = 1; lat_sys = 0; lat_mux = 0; lat_seq = 0;
            while (lat_sys == 0 || lat_mux == 0 || lat_seq == 0) begin
                if (done_sys && lat_sys == 0) lat_sys = cyc;
                if (done_mux && lat_mux == 0) lat_mux = cyc;
                if (done_seq && lat_seq == 0) lat_seq = cyc;
                if (lat_sys == 0 || lat_mux == 0 || lat_seq == 0) begin
                    @(negedge clk); cyc = cyc + 1;
                end
            end

            mism = 0;
            for (idx = 0; idx < N*N; idx = idx + 1) begin
                got_sys = c_sys[idx*ACC_W +: ACC_W];
                got_mux = c_mux[idx*ACC_W +: ACC_W];
                got_seq = c_seq[idx*ACC_W +: ACC_W];
                if (got_sys !== G[idx] || got_mux !== G[idx] || got_seq !== G[idx]) begin
                    mism = mism + 1;
                    $display("    MISMATCH C[%0d][%0d]: sys %0d, mux %0d, seq %0d, expected %0d",
                             idx / N, idx % N, got_sys, got_mux, got_seq, G[idx]);
                end
            end
            tests = tests + 1;
            if (mism != 0) failures = failures + 1;
            if (verbose || mism != 0)
                $display("[%0s] %0s  latency: systolic %0d, phase-I %0d, sequential %0d cycles",
                         mism == 0 ? "PASS" : "FAIL", name, lat_sys, lat_mux, lat_seq);
        end
    endtask

    initial begin
        $dumpfile("compare.vcd");
        $dumpvars(0, tb_compare);
        tests = 0; failures = 0; seed = 32'h0C0FFEE5;

        repeat (3) @(negedge clk);
        rst = 1'b0;

        $display("==============================================================");
        $display(" Systolic array vs sequential baseline  (N = %0d, %0d-bit)", N, DATA_W);
        $display("==============================================================");

        for (idx = 0; idx < N*N; idx = idx + 1) begin
            A[idx] = (idx / N == idx % N) ? 1 : 0;  B[idx] = idx + 1;
        end
        run_all("identity x M", 1);

        for (idx = 0; idx < N*N; idx = idx + 1) begin
            A[idx] = idx + 1;  B[idx] = N*N - idx;
        end
        run_all("counting", 1);

        for (idx = 0; idx < N*N; idx = idx + 1) begin
            A[idx] = -128;  B[idx] = -128;
        end
        run_all("all -128", 1);

        for (idx = 0; idx < N*N; idx = idx + 1) begin
            A[idx] = (idx % 2) ? 127 : -128;
            B[idx] = (idx % 3) ? -1 : 127;
        end
        run_all("mixed sign", 1);

        // Q4.4 fixed point: 1.5 = 24, -0.25 = -4, 2.0 = 32, 0.5 = 8 (value x 16)
        // A: 1.5 on the diagonal, -0.25 elsewhere.  B: 2.0 in column 0, 0.5 elsewhere.
        // The product of two Q4.4 numbers is Q8.8 (value x 256).
        for (idx = 0; idx < N*N; idx = idx + 1) begin
            A[idx] = (idx / N == idx % N) ? 24 : -4;
            B[idx] = (idx % N == 0) ? 32 : 8;
        end
        run_all("Q4.4 fixed point", 1);
        got_sys = c_sys[0 +: ACC_W];
        $display("       C[0][0] = %0d / 256 = %f   (expected 1.5*2.0 - 0.25*2.0*(N-1) = %f)",
                 got_sys, got_sys / 256.0, 3.0 - 0.5 * (N - 1));

        for (n = 0; n < NUM_RANDOM; n = n + 1) begin
            for (idx = 0; idx < N*N; idx = idx + 1) begin
                A[idx] = $random(seed);  B[idx] = $random(seed);
            end
            run_all("random", 0);
        end
        $display("    ... %0d random matrices checked on all three designs", NUM_RANDOM);

        // back-to-back throughput: a new start the cycle done is seen
        t0 = 0;
        for (n = 0; n < NUM_B2B; n = n + 1) begin
            for (idx = 0; idx < N*N; idx = idx + 1) begin
                A[idx] = $random(seed);  B[idx] = $random(seed);
            end
            pack;
            start = 1'b1; @(negedge clk); start = 1'b0; t0 = t0 + 1;
            while (!done_sys) begin @(negedge clk); t0 = t0 + 1; end
        end
        b2b_sys = t0;
        while (busy_seq) @(negedge clk);            // let the baseline go idle
        t0 = 0;
        for (n = 0; n < NUM_B2B; n = n + 1) begin
            pack;
            start = 1'b1; @(negedge clk); start = 1'b0; t0 = t0 + 1;
            while (!done_seq) begin @(negedge clk); t0 = t0 + 1; end
        end
        b2b_seq = t0;

        $display("==============================================================");
        $display(" PERFORMANCE (N = %0d, %0d MACs per matrix)", N, N*N*N);
        $display("   latency    systolic %0d cycles (3N-1), sequential %0d cycles (N^3+1)",
                 lat_sys, lat_seq);
        $display("   throughput systolic %0d cycles/matrix = %0.2f MAC/cycle",
                 b2b_sys / NUM_B2B, (1.0 * N * N * N * NUM_B2B) / b2b_sys);
        $display("              sequential %0d cycles/matrix = %0.2f MAC/cycle",
                 b2b_seq / NUM_B2B, (1.0 * N * N * N * NUM_B2B) / b2b_seq);
        $display("   speed-up in cycles: %0.2fx", (1.0 * lat_seq) / lat_sys);
        $display("==============================================================");
        if (failures == 0)
            $display(" ALL %0d COMPARISON TESTS PASSED (3 designs each)", tests);
        else
            $display(" %0d of %0d COMPARISON TESTS FAILED", failures, tests);
        $display("==============================================================");
        $finish;
    end

    initial begin
        #50_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
