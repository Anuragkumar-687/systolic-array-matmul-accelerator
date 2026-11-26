// -----------------------------------------------------------------------------
// seq_matmul.v - Sequential baseline matrix multiplier (Phase II)
//
// Same ports, number format and start/busy/done behaviour as matmul_accel,
// but built around ONE shared multiply-accumulate datapath that walks the
// classic triple loop, one product per clock:
//
//     for i, for j, for k:   C[i][j] += A[i][k] * B[k][j]
//
// It needs N^3 compute cycles, so start -> done takes N^3 + 1 cycles.
// This is the "sequential multiplication" the project brief asks us to
// compare the systolic array against.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module seq_matmul #(
    parameter N      = 4,
    parameter DATA_W = 8,
    parameter ACC_W  = 24
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     start,
    input  wire [N*N*DATA_W-1:0]    a_flat,
    input  wire [N*N*DATA_W-1:0]    b_flat,
    output reg  [N*N*ACC_W-1:0]     c_flat,
    output wire                     busy,
    output reg                      done
);

    localparam IDX_W = (N > 1) ? $clog2(N) : 1;

    localparam S_IDLE = 1'b0;
    localparam S_RUN  = 1'b1;

    reg                     state;
    reg [IDX_W-1:0]         i, j, k;
    reg [N*N*DATA_W-1:0]    a_q, b_q;
    reg signed [ACC_W-1:0]  acc;

    // operand select: two N*N-to-1 multiplexers
    wire signed [DATA_W-1:0]   a_sel = a_q[(i*N + k)*DATA_W +: DATA_W];
    wire signed [DATA_W-1:0]   b_sel = b_q[(k*N + j)*DATA_W +: DATA_W];
    wire signed [2*DATA_W-1:0] prod  = a_sel * b_sel;

    // start a new sum when k = 0. acc_in must stay signed so that prod is
    // sign-extended (an unsigned literal in the ?: would make it unsigned).
    wire signed [ACC_W-1:0] acc_in = (k == 0) ? $signed({ACC_W{1'b0}}) : acc;
    wire signed [ACC_W-1:0] sum    = acc_in + prod;

    assign busy = (state == S_RUN);

    always @(posedge clk) begin
        if (rst) begin
            state  <= S_IDLE;
            i      <= {IDX_W{1'b0}};
            j      <= {IDX_W{1'b0}};
            k      <= {IDX_W{1'b0}};
            acc    <= {ACC_W{1'b0}};
            done   <= 1'b0;
            a_q    <= {(N*N*DATA_W){1'b0}};
            b_q    <= {(N*N*DATA_W){1'b0}};
            c_flat <= {(N*N*ACC_W){1'b0}};
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        a_q   <= a_flat;
                        b_q   <= b_flat;
                        i     <= {IDX_W{1'b0}};
                        j     <= {IDX_W{1'b0}};
                        k     <= {IDX_W{1'b0}};
                        done  <= 1'b0;
                        state <= S_RUN;
                    end
                end
                S_RUN: begin
                    acc <= sum;
                    if (k == N-1) begin
                        c_flat[(i*N + j)*ACC_W +: ACC_W] <= sum;   // C[i][j] finished
                        k <= {IDX_W{1'b0}};
                        if (j == N-1) begin
                            j <= {IDX_W{1'b0}};
                            if (i == N-1) begin
                                done  <= 1'b1;
                                state <= S_IDLE;
                            end else
                                i <= i + 1'b1;
                        end else
                            j <= j + 1'b1;
                    end else
                        k <= k + 1'b1;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
