// -----------------------------------------------------------------------------
// skew_buffer.v - Input buffer for one lane (one row of A or one column of B)
//
// A parallel-load shift register N + DELAY elements deep.
//   load  : the N elements are written behind DELAY zero slots
//   shift : the head element is consumed and a zero enters at the tail
// so dout produces   0 ... 0 (DELAY times), d[0], d[1], ..., d[N-1], 0, 0 ...
//
// Lane i uses DELAY = i, which is exactly the skew the array needs:
// element k of lane i leaves the buffer in cycle i + k.
//
// Phase II: replaces the counter-driven multiplexer feeders of Phase I.
// dout comes straight from a register, so no comparator or multiplexer sits
// in front of the first row/column of PEs (shorter critical path).
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module skew_buffer #(
    parameter N      = 4,
    parameter DATA_W = 8,
    parameter DELAY  = 0
) (
    input  wire                clk,
    input  wire                rst,
    input  wire                load,
    input  wire                shift,
    input  wire [N*DATA_W-1:0] din_flat,    // element 0 in the low bits
    output wire [DATA_W-1:0]   dout
);

    localparam DEPTH = N + DELAY;

    reg  [DEPTH*DATA_W-1:0] sr;
    wire [DEPTH*DATA_W-1:0] din_ext = din_flat;          // zero-extend

    assign dout = sr[DATA_W-1:0];

    always @(posedge clk) begin
        if (rst)
            sr <= {(DEPTH*DATA_W){1'b0}};
        else if (load)
            sr <= din_ext << (DELAY*DATA_W);
        else if (shift)
            sr <= sr >> DATA_W;
    end

endmodule
