// -----------------------------------------------------------------------------
// systolic_array.v - N x N mesh of processing elements
//
// A operands enter on the left edge (one per row) and travel right.
// B operands enter on the top edge (one per column) and travel down.
// Only nearest-neighbour wires exist, so the critical path is one multiplier
// plus one adder regardless of N.
//
// Flattening convention: element [r][c] of the result lives at
//   c_flat[(r*N + c)*ACC_W +: ACC_W]
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module systolic_array #(
    parameter N      = 4,
    parameter DATA_W = 8,
    parameter ACC_W  = 24
) (
    input  wire                    clk,
    input  wire                    rst,
    input  wire                    clr,
    input  wire                    en,
    input  wire [N*DATA_W-1:0]     a_edge,   // a_edge[i] feeds row i
    input  wire [N*DATA_W-1:0]     b_edge,   // b_edge[j] feeds column j
    output wire [N*N*ACC_W-1:0]    c_flat
);

    // a_h[i*(N+1) + j] : horizontal link entering PE(i,j)   (j = 0..N)
    // b_v[i*N     + j] : vertical   link entering PE(i,j)   (i = 0..N)
    wire [DATA_W-1:0] a_h [0:N*(N+1)-1];
    wire [DATA_W-1:0] b_v [0:(N+1)*N-1];

    genvar i, j;
    generate
        for (i = 0; i < N; i = i + 1) begin : g_edge
            assign a_h[i*(N+1)] = a_edge[i*DATA_W +: DATA_W];
            assign b_v[i]       = b_edge[i*DATA_W +: DATA_W];
        end

        for (i = 0; i < N; i = i + 1) begin : g_row
            for (j = 0; j < N; j = j + 1) begin : g_col
                pe #(
                    .DATA_W (DATA_W),
                    .ACC_W  (ACC_W)
                ) u_pe (
                    .clk   (clk),
                    .rst   (rst),
                    .clr   (clr),
                    .en    (en),
                    .a_in  (a_h[i*(N+1) + j]),
                    .b_in  (b_v[i*N + j]),
                    .a_out (a_h[i*(N+1) + j + 1]),
                    .b_out (b_v[(i+1)*N + j]),
                    .acc   (c_flat[(i*N + j)*ACC_W +: ACC_W])
                );
            end
        end
    endgenerate

endmodule
