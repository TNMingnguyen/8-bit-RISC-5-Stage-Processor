`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// hazard_unit.v - Data Hazard Detection
// 
// This module handles two kinds of pipeline data hazards:
//
// 1) FORWARDING (cost: 0 cycles)
//    An instruction in EX needs a register that an older instruction
//    has computed but not yet written back.
//      - If the older instruction is in MEM  -> take value from EX/MEM
//      - If the older instruction is in WB   -> take value from MEM/WB
//      - If the older instruction is further -> register-file bypass
//        (handled inside regfile.v)
//
//    Select codes for the forwarding MUX:
//      2'b00 = use the value read in ID
//      2'b10 = forward from EX/MEM (newest value)
//      2'b01 = forward from MEM/WB (older value)
//
// 2) LOAD-USE STALL (cost: 1 cycle)
//    A load only has its data at the END of MEM. If the very next
//    instruction needs that data in EX, it is too early. So we freeze
//    the PC and IF/ID for one cycle and insert a bubble into ID/EX.
//
// This module is purely combinational.
////////////////////////////////////////////////////////////////////////////////// 

module hazard_unit (
  //  Instruction in ID (stage 2) 
  input  wire       id_valid,       // 1 = IF/ID holds a real instruction
  input  wire [2:0] id_ra_addr,     // register read on port A
  input  wire [2:0] id_rb_addr,     // register read on port B
  input  wire       id_uses_a,      // 1 = instruction really reads port A
  input  wire       id_uses_b,      // 1 = instruction really reads port B
  // Instruction in EX (stage 3)
  
  input  wire       ex_valid,       // 1 = ID/EX holds a real instruction
  input  wire       ex_mem_to_reg,  // 1 = instruction in EX is a load (LD)
  input  wire [2:0] ex_rd,          // its destination register
  input  wire [2:0] ex_ra_addr,     // its port-A read register
  input  wire [2:0] ex_rb_addr,     // its port-B read register
  input  wire       ex_uses_a,      // 1 = it reads port A
  input  wire       ex_uses_b,      // 1 = it reads port B
  //  Instruction in MEM (stage 4) 
  
  input  wire       mem_reg_we,     // 1 = instruction in MEM writes a register
  input  wire       mem_mem_to_reg, // 1 = instruction in MEM is a load
  input  wire [2:0] mem_rd,         // its destination register
  
  // Instruction in WB (stage 5) 
  input  wire       wb_reg_we,      // 1 = instruction in WB writes a register
  input  wire [2:0] wb_rd,          // its destination register

  //  Outputs 
  output reg  [1:0] fwd_a_sel,      // forwarding select for operand A
  output reg  [1:0] fwd_b_sel,      // forwarding select for operand B
  output wire       stall           // 1 = insert a load-use stall this cycle
);

  // Forwarding select for operand A
  // Only forward into operands that the EX instruction really reads
  // (ex_uses_a). This avoids false matches from unused register fields.

  always @(*) begin
    if (ex_uses_a && mem_reg_we && !mem_mem_to_reg && (mem_rd == ex_ra_addr))
      fwd_a_sel = 2'b10;   // newest value: take from EX/MEM
    else if (ex_uses_a && wb_reg_we && (wb_rd == ex_ra_addr))
      fwd_a_sel = 2'b01;   // older value: take from MEM/WB
    else
      fwd_a_sel = 2'b00;   // no hazard: use the value read in ID
  end

  // Forwarding select for operand B (same rules as port A)

  always @(*) begin
    if (ex_uses_b && mem_reg_we && !mem_mem_to_reg && (mem_rd == ex_rb_addr))
      fwd_b_sel = 2'b10;
    else if (ex_uses_b && wb_reg_we && (wb_rd == ex_rb_addr))
      fwd_b_sel = 2'b01;
    else
      fwd_b_sel = 2'b00;
  end

  // Load-use stall detection.
  // Condition: a load is in EX AND the instruction in ID reads the
  // register that load will write.

  assign stall = id_valid && ex_valid && ex_mem_to_reg &&
                 ((id_uses_a && (id_ra_addr == ex_rd)) ||
                  (id_uses_b && (id_rb_addr == ex_rd)));

endmodule