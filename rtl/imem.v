`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// imem.v - Instruction Memory (256 x 16-bit ROM)
//
// Holds the program. The PC is the address; the 16-bit instruction
// appears on 'instr' in the SAME cycle (asynchronous read).
//
// Harvard architecture: this memory is separate from data memory,
// so fetch (IF stage) and load/store (MEM stage) never conflict.
//
// The program is loaded from a hex file at simulation start.
//////////////////////////////////////////////////////////////////////////////////

module imem #(
    parameter INIT_FILE = "program.hex"
// file to load the program from
) (
  input  wire [7:0]  addr,   // address = current PC
  output wire [15:0] instr   // instruction at that address
);

  // Program memory: 256 words, each 16 bits
  reg [15:0] rom [0:255];
  integer i;  // loop index

  // Load the program at simulation start.
  // First fill with NOP (0x0000) so unused locations are harmless,
  // then load the actual program from the hex file.

  initial begin
    for (i = 0; i < 256; i = i + 1)
      rom[i] = 16'h0000;
    $readmemh(INIT_FILE, rom);
  end

  // Read port: asynchronous (combinational).
  // The instruction at 'addr' appears on 'instr' immediately.
  assign instr = rom[addr];
endmodule