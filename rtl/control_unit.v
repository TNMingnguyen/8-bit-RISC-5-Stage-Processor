`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// It receives a 4-bit opcode (the top 4 bits of an instruction)
// and outputs all the control signals needed by the rest of the CPU.
//
// In the 5-stage pipeline, these signals are generated in stage 2 (ID)
// and then carried down the pipeline registers (ID/EX -> EX/MEM -> MEM/WB).
// Each later stage uses only the signals it needs:
//   EX  uses : alu_op, alu_src_imm, flag_we, jump, br_z, br_nz
//   MEM uses : mem_we, mem_to_reg
//   WB  uses : reg_we
// This module is purely combinational: it only looks at the opcode.
//////////////////////////////////////////////////////////////////////////////////

module control_unit (
  input  wire [3:0] opcode,      // 4-bit opcode from instruction
  output reg  [2:0] alu_op,      // ALU operation select
  output reg        alu_src_imm, // 1 = use immediate instead of register
  output reg        ra_is_rd,    // 1 = port A reads rd (for ADDI)
  output reg        rb_is_rd,    // 1 = port B reads rd (for ST)
  output reg        uses_a,      // 1 = instruction reads port A
  output reg        uses_b,      // 1 = instruction reads port B
  output reg        reg_we,      // 1 = write result to register
  output reg        mem_to_reg,  // 1 = write-back from memory (LD)
  output reg        mem_we,      // 1 = write to memory (ST)
  output reg        flag_we,     // 1 = update Z and C flags
  output reg        jump,        // 1 = JMP
  output reg        br_z,        // 1 = BZ
  output reg        br_nz,       // 1 = BNZ
  output reg        halt         // 1 = HLT
);
  // Opcode values
  localparam NOP   = 4'h0, ADD  = 4'h1, SUB  = 4'h2, AND_OP = 4'h3,
             OR_OP = 4'h4, XOR_OP = 4'h5, SHL  = 4'h6, SHR  = 4'h7,
             LDI   = 4'h8, ADDI = 4'h9, LD   = 4'hA, ST   = 4'hB,
             JMP   = 4'hC, BZ   = 4'hD, BNZ  = 4'hE, HLT  = 4'hF;

  always @(*) begin
    // Default: all signals off (same as NOP) -> prevents latch
    alu_op = 3'd0; alu_src_imm = 1'b0; ra_is_rd = 1'b0; rb_is_rd = 1'b0;
    uses_a = 1'b0; uses_b = 1'b0;
    reg_we = 1'b0; mem_to_reg = 1'b0; mem_we = 1'b0; flag_we = 1'b0;
    jump = 1'b0; br_z = 1'b0; br_nz = 1'b0; halt = 1'b0;

    case (opcode)
      // ALU ops: read 2 regs, write 1, update flags
      ADD   : begin alu_op = 3'd0; uses_a = 1; uses_b = 1; reg_we = 1; flag_we = 1; end
      SUB   : begin alu_op = 3'd1; uses_a = 1; uses_b = 1; reg_we = 1; flag_we = 1; end
      AND_OP: begin alu_op = 3'd2; uses_a = 1; uses_b = 1; reg_we = 1; flag_we = 1; end
      OR_OP : begin alu_op = 3'd3; uses_a = 1; uses_b = 1; reg_we = 1; flag_we = 1; end
      XOR_OP: begin alu_op = 3'd4; uses_a = 1; uses_b = 1; reg_we = 1; flag_we = 1; end

      // Shifts: read only port A
      SHL   : begin alu_op = 3'd5; uses_a = 1; reg_we = 1; flag_we = 1; end
      SHR   : begin alu_op = 3'd6; uses_a = 1; reg_we = 1; flag_we = 1; end

      // LDI: load immediate, no register read
      LDI   : begin alu_op = 3'd7; alu_src_imm = 1; reg_we = 1; end

      // ADDI: rd = rd + imm, reads rd via port A
      ADDI  : begin alu_op = 3'd0; alu_src_imm = 1; ra_is_rd = 1;
                    uses_a = 1; reg_we = 1; flag_we = 1; end

      // LD: rd = MEM[rs1], reads rs1 via port A
      LD    : begin uses_a = 1; reg_we = 1; mem_to_reg = 1; end

      // ST: MEM[rs1] = rd, reads rs1 (A) and rd (B)
      ST    : begin uses_a = 1; uses_b = 1; rb_is_rd = 1; mem_we = 1; end

      // Branch / jump
      JMP   : jump  = 1;
      BZ    : br_z  = 1;
      BNZ   : br_nz = 1;
      // Halt
      HLT   : halt  = 1;
      // NOP and unused opcodes: keep defaults
      default: ;
    endcase
  end
endmodule