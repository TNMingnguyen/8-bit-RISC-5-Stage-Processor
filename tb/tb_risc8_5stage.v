`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// tb_risc8_5stage.v - Testbench for the 5_stage RISC CPU
// 
// What this testbench does:
//   1. Generates clock (100 MHz) and reset.
//   2. Loads program.hex and runs it until the CPU halts.
//   3. Prints a line every cycle (shows what is in each stage).
//   4. Checks final register values, memory, and flags.
//   5. Prints PASS / FAIL and a summary (CPI, stalls, branches).
//   6. Dumps a VCD file for GTKWave (optional).
//
//////////////////////////////////////////////////////////////////////////////////
module tb_risc8_5stage;

  // 1. Signal Declarations
  reg clk = 0;
  reg rst = 1;

  wire       halted;
  wire [7:0] pc;
  wire [1:0] flags;
  wire       instr_done;

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

  // 4. Performance Counters
  integer cycles  = 0;
  integer retired = 0;
  integer stalls  = 0;
  integer flushes = 0;
  integer fwds    = 0;
  integer errors  = 0;

  // 5. Highly Formatted Tcl Console Output
  initial begin
    $display("\nSTARTING 8-BIT 5-STAGE PIPELINED RISC SIMULATION");
    $display("---------------------------------------------------------------------------------------------------------");
    $display("Cyc | PC_IF | Inst_ID | ALU_EX | FwdA FwdB | Stall | WB_En | Rd_WB | Data_WB |  R1 R2 R3 R4 R5  | RAM[4]");
    $display("---------------------------------------------------------------------------------------------------------");
  end

  always @(posedge clk) if (!rst && !halted) begin
    cycles <= cycles + 1;
    if (instr_done)      retired <= retired + 1;
    if (dut.stall)       stalls  <= stalls  + 1;
    if (dut.take_branch) flushes <= flushes + 1;
    if (dut.idex_valid && (dut.fwd_a_sel != 2'b00 || dut.fwd_b_sel != 2'b00))
      fwds <= fwds + 1;

    $display("%3d | 0x%02h | 0x%04h  | 0x%02h  |  %b    %b   |   %b   |   %b   |  R%0d  |  0x%02h  | %02h %02h %02h %02h %02h |  0x%02h",
             cycles, pc,
             dut.ifid_instr,
             dut.ex_alu_y,
             dut.fwd_a_sel[1], dut.fwd_b_sel[1],
             dut.stall,
             dut.memwb_reg_we,
             dut.memwb_rd,
             dut.memwb_data,
             dut.u_rf.r[1], dut.u_rf.r[2], dut.u_rf.r[3], dut.u_rf.r[4], dut.u_rf.r[5],
             dut.u_dmem.mem[4]);
  end

  // 6. Self-Checking Task
  task check_reg(input [2:0] r, input [7:0] exp);
    if (dut.u_rf.r[r] !== exp) begin
      $display("FAIL  R%0d = %02h, expected %02h", r, dut.u_rf.r[r], exp);
      errors = errors + 1;
    end else begin
      $display("PASS  R%0d = %02h", r, exp);
    end
  endtask

  // 7. Main Test Sequence
  initial begin
    $dumpfile("risc8_5stage.vcd");
    $dumpvars(0, tb_risc8_5stage);

    #22 rst = 0;

    wait (halted);
    @(posedge clk); @(posedge clk);

    $display("\n------------- Checking final results -------------");

    check_reg(1, 8'h00);
    check_reg(2, 8'h0F);
    check_reg(3, 8'h01);
    check_reg(4, 8'h20);
    check_reg(5, 8'h00);
    check_reg(6, 8'h66);
    check_reg(7, 8'h00);

    if (dut.u_dmem.mem[8'h20] !== 8'h0F) begin
      $display("FAIL  MEM[20] = %02h, expected 0F", dut.u_dmem.mem[8'h20]);
      errors = errors + 1;
    end else begin
      $display("PASS  MEM[20] = 0F");
    end

    if (flags !== 2'b11) begin
      $display("FAIL  flags Z=%b C=%b, expected Z=1 C=1", flags[1], flags[0]);
      errors = errors + 1;
    end else begin
      $display("PASS  flags Z=1 C=1");
    end

    $display("\n------------- Performance summary -------------");
    $display("cycles=%0d  instructions=%0d  CPI=%0.2f", cycles, retired, cycles * 1.0 / retired);
    $display("load-use stalls=%0d  taken branches=%0d  forwards=%0d", stalls, flushes, fwds);

    if (errors == 0)
      $display("\n*** ALL TESTS PASSED ***\n");
    else
      $display("\n*** %0d TEST(S) FAILED ***\n", errors);

    $finish;
  end

  // 8. Watchdog Timer
  initial begin
    #20000;
    $display("TIMEOUT: CPU did not halt in time.");
    $finish;
  end

endmodule