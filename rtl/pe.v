// -----------------------------------------------------------------------------
// pe.v - Systolic Processing Element (multiply-accumulate cell)
//
// One cell of the 2-D systolic mesh. Every enabled clock cycle it:
//   1. multiplies the operand arriving from the left (a_in) with the operand
//      arriving from the top (b_in) and adds the product to its accumulator;
//   2. forwards a_in to the right neighbour and b_in to the bottom neighbour.
//
// PE(i,j) therefore accumulates  C[i][j] = sum_k A[i][k] * B[k][j].
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module pe #(
    parameter DATA_W = 8,    // operand width (signed)
    parameter ACC_W  = 24    // accumulator width (signed)
) (
    input  wire                     clk,
    input  wire                     rst,    // synchronous reset
    input  wire                     clr,    // clear before a new multiplication
    input  wire                     en,     // advance the systolic wavefront
    input  wire signed [DATA_W-1:0] a_in,   // from left neighbour / row feeder
    input  wire signed [DATA_W-1:0] b_in,   // from top neighbour / column feeder
    output reg  signed [DATA_W-1:0] a_out,  // to right neighbour
    output reg  signed [DATA_W-1:0] b_out,  // to bottom neighbour
    output reg  signed [ACC_W-1:0]  acc     // running dot product
);

    wire signed [2*DATA_W-1:0] prod = a_in * b_in;

    always @(posedge clk) begin
        if (rst || clr) begin
            a_out <= {DATA_W{1'b0}};
            b_out <= {DATA_W{1'b0}};
            acc   <= {ACC_W{1'b0}};
        end else if (en) begin
            a_out <= a_in;
            b_out <= b_in;
            acc   <= acc + prod;   // prod is sign-extended to ACC_W
        end
    end

endmodule
