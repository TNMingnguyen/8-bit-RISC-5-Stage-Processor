`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// File: tb_dump.v
// Description: Testbench for Random Regression Testing.
// 
// Purpose:
//   This testbench is designed to be run from the command line (via Icarus 
//   Verilog and Python). It runs whatever program is currently in "program.hex",
//   waits for the CPU to halt, and then dumps the final state of all registers,
//   flags, and data memory to a text file named "dump.txt".
//
// How it works:
//   A Python script (random_test.py) will read "dump.txt" and compare it 
//   against a golden software model (iss.py) to verify the RTL correctness.
//////////////////////////////////////////////////////////////////////////////////

module tb_dump;

  // 1. Signal Declarations
  reg clk = 0;
  reg rst = 1;
  
  wire       halted;
  wire [7:0] pc;
  wire [1:0] flags;        // {Z, C} status flags
  wire       instr_done;   // Pulses high when an instruction completes WB

  integer f;               // File descriptor for dump.txt
  integer i;               // Loop index for memory dumping
  integer retired = 0;     // Counter for total completed instructions

  // Count the number of instructions that successfully retire (reach WB)
  always @(posedge clk) if (instr_done) retired <= retired + 1;

  // 2. Device Under Test (DUT) Instantiation

  risc8_5stage_core #(
    .IMEM_FILE("program.hex")
  ) dut (
    .clk        (clk), 
    .rst        (rst), 
    .halted     (halted), 
    .pc_out     (pc),
    .flags_out  (flags), 
    .instr_done (instr_done)
  );

  // 3. Clock Generation (100 MHz)

  initial forever #5 clk = ~clk;

  // 4. Main Dump Sequence

  initial begin
    // Apply reset for ~2 cycles, then release
    #22 rst = 0;

    // Wait until the CPU finishes executing the HLT instruction
    wait (halted);
    @(posedge clk);

    // Open the output file for writing
    f = $fopen("dump.txt", "w");

    // Dump all 8 general-purpose registers (R0 to R7)
    for (i = 0; i < 8; i = i + 1) begin
      $fwrite(f, "%02h\n", dut.u_rf.r[i]);
    end

    // Dump the Z and C flags on a single line
    $fwrite(f, "%0d %0d\n", flags[1], flags[0]);

    // Dump all 256 bytes of data memory
    for (i = 0; i < 256; i = i + 1) begin
      $fwrite(f, "%02h\n", dut.u_dmem.mem[i]);
    end

    // Close the file and stop simulation
    $fclose(f);
    $display("Dump complete: halted at PC=%02h after %0d instructions", pc, retired);
    $finish;
  end

  // 5. Watchdog Timer

  // If the CPU hangs or enters an infinite loop, stop simulation after 200 us.
  initial begin
    #200000;
    $display("TIMEOUT: CPU did not halt in time.");
    $finish;
  end

endmodule
