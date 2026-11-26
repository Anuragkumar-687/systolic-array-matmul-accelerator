// -----------------------------------------------------------------------------
// mac_unit.v - Multiply-accumulate unit (Phase II: split out of pe.v)
//
//   acc <= acc + a * b     on every clock where en = 1
//   acc <= 0               on rst or clr (clr has priority over en)
//
// a and b are signed two's-complement numbers. The product keeps full
// precision (2*DATA_W bits) and is sign-extended to ACC_W before it is added.
// With ACC_W >= 2*DATA_W + ceil(log2(N)) the sum of N products never overflows.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module mac_unit #(
    parameter DATA_W = 8,
    parameter ACC_W  = 24
) (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     clr,
    input  wire                     en,
    input  wire signed [DATA_W-1:0] a,
    input  wire signed [DATA_W-1:0] b,
    output reg  signed [ACC_W-1:0]  acc
);

    wire signed [2*DATA_W-1:0] prod = a * b;

    always @(posedge clk) begin
        if (rst || clr)
            acc <= {ACC_W{1'b0}};
        else if (en)
            acc <= acc + prod;
    end

endmodule
