// -----------------------------------------------------------------------------
// tb_matmul_accel.v - self-checking testbench for the systolic accelerator
//
// Drives directed and random matrices into the DUT and compares every result
// against a behavioural triple-loop reference model. Prints PASS/FAIL per test
// and a final summary; dumps waves.vcd for waveform inspection.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_matmul_accel;

    parameter N      = 4;
    parameter DATA_W = 8;
    parameter ACC_W  = 24;
    parameter NUM_RANDOM = 100;

    reg                       clk = 1'b0;
    reg                       rst = 1'b1;
    reg                       start = 1'b0;
    reg  [N*N*DATA_W-1:0]     a_flat = 0;
    reg  [N*N*DATA_W-1:0]     b_flat = 0;
    wire [N*N*ACC_W-1:0]      c_flat;
    wire                      busy;
    wire                      done;

    matmul_accel #(
        .N      (N),
        .DATA_W (DATA_W),
        .ACC_W  (ACC_W)
    ) dut (
        .clk    (clk),
        .rst    (rst),
        .start  (start),
        .a_flat (a_flat),
        .b_flat (b_flat),
        .c_flat (c_flat),
        .busy   (busy),
        .done   (done)
    );

    always #5 clk = ~clk;   // 100 MHz

    // matrices held as [row*N + col]
    reg signed [DATA_W-1:0] A [0:N*N-1];
    reg signed [DATA_W-1:0] B [0:N*N-1];
    reg signed [ACC_W-1:0]  G [0:N*N-1];   // golden result
    reg signed [ACC_W-1:0]  got;
    reg signed [ACC_W-1:0]  sum;

    integer r, c, k, idx, n;
    integer tests, failures, mism, cycles, seed;

    // free-running cycle counter for the throughput measurement
    integer cyc, t0;
    initial cyc = 0;
    always @(posedge clk) cyc = cyc + 1;

    // behavioural reference model
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

    task show;
        input integer which;   // 0 = A, 1 = B, 2 = C (DUT)
        begin
            for (r = 0; r < N; r = r + 1) begin
                $write("      [");
                for (c = 0; c < N; c = c + 1) begin
                    if (which == 0)      $write(" %6d", A[r*N + c]);
                    else if (which == 1) $write(" %6d", B[r*N + c]);
                    else $write(" %6d", $signed(c_flat[(r*N + c)*ACC_W +: ACC_W]));
                end
                $write(" ]\n");
            end
        end
    endtask

    // run one multiplication and check it
    task run_test;
        input [8*20-1:0] name;
        input integer    verbose;
        begin
            for (idx = 0; idx < N*N; idx = idx + 1) begin
                a_flat[idx*DATA_W +: DATA_W] = A[idx];
                b_flat[idx*DATA_W +: DATA_W] = B[idx];
            end
            golden;

            // called on a negedge, so start can go high right away:
            // back-to-back runs then have no idle cycle between them
            start = 1'b1;
            @(negedge clk); start = 1'b0;
            cycles = 1;
            while (!done) begin
                @(negedge clk);
                cycles = cycles + 1;
            end

            mism = 0;
            for (idx = 0; idx < N*N; idx = idx + 1) begin
                got = c_flat[idx*ACC_W +: ACC_W];
                if (got !== G[idx]) begin
                    mism = mism + 1;
                    $display("    MISMATCH C[%0d][%0d]: got %0d, expected %0d",
                             idx / N, idx % N, got, G[idx]);
                end
            end

            tests = tests + 1;
            if (mism != 0) failures = failures + 1;

            if (verbose || mism != 0) begin
                $display("[%0s] %0s  (latency %0d cycles)",
                         mism == 0 ? "PASS" : "FAIL", name, cycles);
                $display("    A ="); show(0);
                $display("    B ="); show(1);
                $display("    C = A x B (from DUT) ="); show(2);
            end
        end
    endtask

    initial begin
        $dumpfile("waves.vcd");
        $dumpvars(0, tb_matmul_accel);

        tests = 0; failures = 0; seed = 32'h5EED_2026;

        repeat (3) @(negedge clk);
        rst = 1'b0;

        $display("==============================================================");
        $display(" Systolic Array Matrix Multiplication Accelerator - testbench");
        $display(" N = %0d, DATA_W = %0d, ACC_W = %0d, expected latency = %0d cycles",
                 N, DATA_W, ACC_W, 3*N - 1);
        $display("==============================================================");

        // 1. identity x M = M
        for (idx = 0; idx < N*N; idx = idx + 1) begin
            A[idx] = (idx / N == idx % N) ? 1 : 0;
            B[idx] = idx + 1;
        end
        run_test("identity x M", 1);

        // 2. counting matrices
        for (idx = 0; idx < N*N; idx = idx + 1) begin
            A[idx] = idx + 1;
            B[idx] = N*N - idx;
        end
        run_test("counting", 1);

        // 3. signed corner case: most negative operands everywhere
        for (idx = 0; idx < N*N; idx = idx + 1) begin
            A[idx] = {1'b1, {(DATA_W-1){1'b0}}};
            B[idx] = {1'b1, {(DATA_W-1){1'b0}}};
        end
        run_test("min x min", 1);

        // 4. mixed-sign corner case
        for (idx = 0; idx < N*N; idx = idx + 1) begin
            A[idx] = (idx % 2) ? {1'b0, {(DATA_W-1){1'b1}}} : {1'b1, {(DATA_W-1){1'b0}}};
            B[idx] = (idx % 3) ? -1 : {1'b0, {(DATA_W-1){1'b1}}};
        end
        run_test("mixed sign", 1);

        // 5. back-to-back random multiplications
        t0 = cyc;
        for (n = 0; n < NUM_RANDOM; n = n + 1) begin
            for (idx = 0; idx < N*N; idx = idx + 1) begin
                A[idx] = $random(seed);
                B[idx] = $random(seed);
            end
            run_test("random", n == 0);
        end
        $display("    ... %0d random multiplications checked", NUM_RANDOM);
        $display("    throughput: %0d matrices in %0d cycles = %0d cycles/matrix, %0.2f MAC/cycle",
                 NUM_RANDOM, cyc - t0, (cyc - t0) / NUM_RANDOM,
                 (1.0 * N * N * N * NUM_RANDOM) / (cyc - t0));

        $display("==============================================================");
        if (failures == 0)
            $display(" ALL %0d TESTS PASSED", tests);
        else
            $display(" %0d of %0d TESTS FAILED", failures, tests);
        $display("==============================================================");
        $finish;
    end

    // watchdog
    initial begin
        #10_000_000;
        $display("TIMEOUT");
        $finish;
    end

endmodule
