`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// dmem.v - Data Memory (256 bytes of RAM)
//
// Used by LD (load) and ST (store) instructions:
//   LD rd, [rs1]  ->  rd = MEM[R[rs1]]        (read)
//   ST rd, [rs1]  ->  MEM[R[rs1]] = R[rd]     (write)
//
// Read  : asynchronous (data available in the same cycle as the address)
// Write : synchronous  (happens on the rising clock edge)
//
// 256 x 8-bit memory = 256 bytes total.
//////////////////////////////////////////////////////////////////////////////////
module dmem (
  input  wire       clk,    // system clock
  input  wire       we,     // 1 = store (write) this cycle
  input  wire [7:0] addr,   // 8-bit byte address (0..255)
  input  wire [7:0] wdata,  // data to store
  output wire [7:0] rdata   // data loaded from memory
);

  // Memory array: 256 words, each 8 bits
  reg [7:0] mem [0:255];

  integer i;  // loop index

  // Initialize memory to 0 at start of simulation.

  initial begin
    for (i = 0; i < 256; i = i + 1)
      mem[i] = 8'h00;
  end

  // Write port: synchronous, on the rising clock edge.
  // Only write when 'we' is 1.

  always @(posedge clk) begin
    if (we)
      mem[addr] <= wdata;
  end

  // Read port: asynchronous (combinational).
  // The data at 'addr' appears on rdata immediately.
  assign rdata = mem[addr];

endmodule