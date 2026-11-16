`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Stores the 8 general-purpose registers R0..R7.
//   - 2 read ports (A, B) : read in stage 2 (ID)
//   - 1 write port        : written in stage 5 (WB)
//
// Write-through bypass:
//   If WB writes a register in the same cycle that ID reads it,
//   the new value is passed straight through. This removes the
//   "3 instructions apart" data hazard without any extra stall.
//
// Reset is synchronous and active-high.
//////////////////////////////////////////////////////////////////////////////////
module regfile (
  input  wire       clk,      // system clock
  input  wire       rst,      // synchronous reset, active high

  // Read port A (stage 2, ID)
  input  wire [2:0] ra_addr,  // address of register to read
  output wire [7:0] ra_data,  // value read from that register

  // Read port B (stage 2, ID)
  input  wire [2:0] rb_addr,  // address of register to read
  output wire [7:0] rb_data,  // value read from that register

  //  Write port (stage 5, WB) 
  input  wire       we,       // write enable: 1 = write this cycle
  input  wire [2:0] wr_addr,  // destination register address
  input  wire [7:0] wr_data   // value to write
);

  // 8 registers, each 8 bits wide: r[0] = R0, ..., r[7] = R7
  reg [7:0] r [0:7];

  integer i;  // loop index for reset

  // Write port: synchronous, on the rising clock edge
  always @(posedge clk) begin
    if (rst) begin
      // Reset: clear all 8 registers to 0
      for (i = 0; i < 8; i = i + 1)
        r[i] <= 8'h00;
    end
    else if (we) begin
      // Normal write: store wr_data into r[wr_addr]
      r[wr_addr] <= wr_data;
    end
  end

  // Read port A with write-through bypass.
  // If WB is writing the SAME register this cycle, output the new
  // value (wr_data) instead of the old stored value.
  
  assign ra_data = (we && (wr_addr == ra_addr)) ? wr_data : r[ra_addr];

  // Read port B with the same bypass rule.
  assign rb_data = (we && (wr_addr == rb_addr)) ? wr_data : r[rb_addr];

endmodule