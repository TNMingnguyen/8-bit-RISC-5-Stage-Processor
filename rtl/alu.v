`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// alu.v - Arithmetic Logic Unit (ALU)
//
// It receives two 8-bit operands (a, b) and an operation code (alu_op).
// It produces:
//   y = 8-bit result
//   c = carry out (for ADD), borrow (for SUB), or shifted-out bit (SHL/SHR)
//   z = zero flag, high when the result y is 0
//
// This module is purely combinational: no clock, no memory.
// Output changes immediately when any input changes.
//////////////////////////////////////////////////////////////////////////////////
module alu (
  input  wire [7:0] a,      // operand A (first number)
  input  wire [7:0] b,      // operand B (second number, or immediate)
  input  wire [2:0] alu_op, // operation select (see codes below)
  output reg  [7:0] y,      // 8-bit result
  output reg        c,      // carry / borrow / shifted-out bit
  output wire       z       // 1 when y == 0
);
  // Operation codes (0 to 7). Same numbers used by control_unit.v.
  localparam ADD    = 3'd0; // y = a + b
  localparam SUB    = 3'd1; // y = a - b
  localparam AND_OP = 3'd2; // y = a & b   (bitwise AND)
  localparam OR_OP  = 3'd3; // y = a | b   (bitwise OR)
  localparam XOR_OP = 3'd4; // y = a ^ b   (bitwise XOR)
  localparam SHL    = 3'd5; // y = a << 1  (shift left by 1)
  localparam SHR    = 3'd6; // y = a >> 1  (shift right by 1)
  localparam PASSB  = 3'd7; // y = b       (used by LDI)

  reg [8:0] result;
  always @(*) begin
    result = 9'd0;  // default value -> prevents accidental latch

    case (alu_op)
      ADD    : result = a + b;      // add; carry goes to bit 8
      SUB    : result = a - b;      // subtract; borrow goes to bit 8
      AND_OP : result = a & b;      // bitwise AND
      OR_OP  : result = a | b;      // bitwise OR
      XOR_OP : result = a ^ b;      // bitwise XOR
      SHL : result = {a[7], a[6:0], 1'b0};     // left shift; old bit 7 goes to carry
      SHR : result = {a[0], 1'b0, a[7:1]};     // right shift; old bit 0 goes to carry
      PASSB  : result = b;          // just output b (for LDI instruction)
      default: result = 9'd0;
    endcase

    // Split the 9-bit result into y (8 bits) and c (1 bit)
    y = result[7:0];  // lower 8 bits = actual result
    c = result[8];    // 9th bit = carry / borrow / shifted-out
  end

  // Zero flag: continuous assignment (simple comparator).
  // z = 1 whenever all 8 bits of y are 0.
  // Used by BZ / BNZ instructions to decide branches.
  assign z = (y == 8'd0);

endmodule