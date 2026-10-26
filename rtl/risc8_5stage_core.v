`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
//
// risc8_5stage_core.v - Top-level of the 8-bit RISC 5-stage CPU
//
// Connects all modules into a classic 5-stage pipelined CPU:
//
//   Stage 1  IF  : fetch instruction at PC
//   Stage 2  ID  : decode, read registers
//   Stage 3  EX  : forwarding, ALU, flags, resolve branches
//   Stage 4  MEM : load/store to data memory
//   Stage 5  WB  : write result to register file
//
// Pipeline registers between stages:
//   IF/ID -> ID/EX -> EX/MEM -> MEM/WB
//
// Hazard handling:
//   - Data hazards    : forwarding (hazard_unit) + write-through bypass (regfile)
//   - Load-use hazard : 1-cycle stall (hazard_unit)
//   - Control hazard  : branch resolved in EX, flush 2 younger instructions
//   - HLT             : fetch stops, older instructions drain, then halted=1
//////////////////////////////////////////////////////////////////////////////////

module risc8_5stage_core #(
  parameter IMEM_FILE = "program.hex"  // Program file to load into instruction memory
) (
  input  wire       clk,        // System clock
  input  wire       rst,        // Synchronous reset, active high
  output reg        halted,     // Goes high after HLT reaches WB and pipeline drains
  output wire [7:0] pc_out,     // Current Program Counter (for debug)
  output wire [1:0] flags_out,  // Status flags {Z, C} (for debug)
  output wire       instr_done  // Pulses high when an instruction completes WB (for debug)
);

  // STAGE 1: INSTRUCTION FETCH (IF)

  
  // Registers are initialized to 0 at declaration to prevent 'X' states in simulation.
  reg  [7:0]  pc = 8'h00; 
  wire [15:0] if_instr;

  // Instruction Memory (ROM)
  imem #(.INIT_FILE(IMEM_FILE)) u_imem (
    .addr  (pc),
    .instr (if_instr)
  );

  // IF/ID Pipeline Register
  reg [15:0] ifid_instr = 16'h0000;
  reg        ifid_valid = 1'b0;

  // STAGE 2: INSTRUCTION DECODE (ID)

  
  // Extract instruction fields
  wire [3:0] id_opcode = ifid_instr[15:12];
  wire [2:0] id_rd     = ifid_instr[11:9];
  wire [2:0] id_rs1    = ifid_instr[8:6];
  wire [2:0] id_rs2    = ifid_instr[5:3];
  wire [7:0] id_imm8   = ifid_instr[7:0];

  // Control signals
  wire [2:0] id_alu_op;
  wire id_alu_src_imm, id_ra_is_rd, id_rb_is_rd, id_uses_a, id_uses_b,
       id_reg_we, id_mem_to_reg, id_mem_we, id_flag_we,
       id_jump, id_br_z, id_br_nz, id_halt;

  // Control Unit (Decoder)
  control_unit u_ctrl (
    .opcode      (id_opcode),
    .alu_op      (id_alu_op),
    .alu_src_imm (id_alu_src_imm),
    .ra_is_rd    (id_ra_is_rd),
    .rb_is_rd    (id_rb_is_rd),
    .uses_a      (id_uses_a),
    .uses_b      (id_uses_b),
    .reg_we      (id_reg_we),
    .mem_to_reg  (id_mem_to_reg),
    .mem_we      (id_mem_we),
    .flag_we     (id_flag_we),
    .jump        (id_jump),
    .br_z        (id_br_z),
    .br_nz       (id_br_nz),
    .halt        (id_halt)
  );

  // Register Read Addresses (ADDI reads rd; ST reads rd as data)
  wire [2:0] id_ra_addr = id_ra_is_rd ? id_rd : id_rs1;
  wire [2:0] id_rb_addr = id_rb_is_rd ? id_rd : id_rs2;
  wire [7:0] id_ra_data, id_rb_data;

  // MEM/WB Pipeline Register (declared early for WB write-back)
  reg        memwb_valid  = 1'b0;
  reg        memwb_reg_we = 1'b0;
  reg  [2:0] memwb_rd     = 3'd0;
  reg  [7:0] memwb_data   = 8'h00;
  reg        memwb_halt   = 1'b0;
  wire [7:0] wb_data = memwb_data;

  // Register File (Read in ID, Write in WB)
  regfile u_rf (
    .clk     (clk),
    .rst     (rst),
    .ra_addr (id_ra_addr), .ra_data (id_ra_data),
    .rb_addr (id_rb_addr), .rb_data (id_rb_data),
    .we      (memwb_reg_we),
    .wr_addr (memwb_rd),
    .wr_data (wb_data)
  );

  // ID/EX Pipeline Register
  reg        idex_valid       = 1'b0;
  reg  [2:0] idex_alu_op      = 3'd0;
  reg        idex_alu_src_imm = 1'b0, idex_uses_a = 1'b0, idex_uses_b = 1'b0;
  reg        idex_reg_we      = 1'b0, idex_mem_to_reg = 1'b0, idex_mem_we = 1'b0, idex_flag_we = 1'b0;
  reg        idex_jump        = 1'b0, idex_br_z = 1'b0, idex_br_nz = 1'b0, idex_halt = 1'b0;
  reg  [2:0] idex_rd          = 3'd0, idex_ra_addr = 3'd0, idex_rb_addr = 3'd0;
  reg  [7:0] idex_ra_data     = 8'h00, idex_rb_data = 8'h00, idex_imm = 8'h00;

  // EX/MEM Pipeline Register
  reg        exmem_valid      = 1'b0;
  reg        exmem_reg_we     = 1'b0, exmem_mem_to_reg = 1'b0, exmem_mem_we = 1'b0, exmem_halt = 1'b0;
  reg  [2:0] exmem_rd         = 3'd0;
  reg  [7:0] exmem_alu_y      = 8'h00;
  reg  [7:0] exmem_addr       = 8'h00;
  reg  [7:0] exmem_store_data = 8'h00;

  // HAZARD UNIT (Forwarding Select + Stall)

  wire [1:0] fwd_a_sel, fwd_b_sel;
  wire       stall;

  hazard_unit u_hazard (
    .id_valid       (ifid_valid),
    .id_ra_addr     (id_ra_addr),
    .id_rb_addr     (id_rb_addr),
    .id_uses_a      (id_uses_a),
    .id_uses_b      (id_uses_b),
    .ex_valid       (idex_valid),
    .ex_mem_to_reg  (idex_mem_to_reg),
    .ex_rd          (idex_rd),
    .ex_ra_addr     (idex_ra_addr),
    .ex_rb_addr     (idex_rb_addr),
    .ex_uses_a      (idex_uses_a),
    .ex_uses_b      (idex_uses_b),
    .mem_reg_we     (exmem_reg_we),
    .mem_mem_to_reg (exmem_mem_to_reg),
    .mem_rd         (exmem_rd),
    .wb_reg_we      (memwb_reg_we),
    .wb_rd          (memwb_rd),
    .fwd_a_sel      (fwd_a_sel),
    .fwd_b_sel      (fwd_b_sel),
    .stall          (stall)
  );

  // STAGE 3: EXECUTE (EX)

  
  // Forwarding Multiplexers for Operands A and B
  // 2'b10: Use EX/MEM result (Newest value)
  // 2'b01: Use MEM/WB result (Older value)
  // 2'b00: Use value read from ID
  wire [7:0] ex_opA = (fwd_a_sel == 2'b10) ? exmem_alu_y :
                      (fwd_a_sel == 2'b01) ? wb_data     : idex_ra_data;
  wire [7:0] ex_opB = (fwd_b_sel == 2'b10) ? exmem_alu_y :
                      (fwd_b_sel == 2'b01) ? wb_data     : idex_rb_data;

  // ALU Input B Multiplexer (Immediate or Register)
  wire [7:0] ex_alu_b = idex_alu_src_imm ? idex_imm : ex_opB;
  wire [7:0] ex_alu_y;
  wire       ex_alu_c, ex_alu_z;

  // Arithmetic Logic Unit
  alu u_alu (
    .a      (ex_opA),
    .b      (ex_alu_b),
    .alu_op (idex_alu_op),
    .y      (ex_alu_y),
    .c      (ex_alu_c),
    .z      (ex_alu_z)
  );

  // Status Flags
  reg flag_z = 1'b0, flag_c = 1'b0;

  // Branch Resolution logic
  wire take_branch = idex_valid &&
                     (idex_jump || (idex_br_z && flag_z) || (idex_br_nz && !flag_z));
  wire [7:0] branch_target = idex_imm;

  // Halt logic: stop fetching when HLT reaches EX
  wire ex_halt = idex_valid && idex_halt;
  reg  draining = 1'b0; // 1 = HLT seen, draining older instructions
  wire fetch_stop = draining || ex_halt;

  // STAGE 4: MEMORY ACCESS (MEM)

  wire [7:0] mem_rdata;
  wire       mem_we = exmem_mem_we && !halted;

  // Data Memory (RAM)
  dmem u_dmem (
    .clk   (clk),
    .we    (mem_we),
    .addr  (exmem_addr),
    .wdata (exmem_store_data),
    .rdata (mem_rdata)
  );

  // MEM result: Loaded data for LD, ALU result for others
  wire [7:0] mem_result = exmem_mem_to_reg ? mem_rdata : exmem_alu_y;

  // SEQUENTIAL LOGIC: PC, Pipeline Registers, Flags, Halt

  always @(posedge clk) begin
    if (rst) begin
      // Synchronous Reset: clear all registers to initial state
      pc          <= 8'h00;
      ifid_instr  <= 16'h0000;  ifid_valid  <= 1'b0;
      idex_valid  <= 1'b0;
      idex_alu_op <= 3'd0; idex_alu_src_imm <= 1'b0;
      idex_uses_a <= 1'b0; idex_uses_b <= 1'b0;
      idex_reg_we <= 1'b0; idex_mem_to_reg <= 1'b0; idex_mem_we <= 1'b0;
      idex_flag_we <= 1'b0; idex_jump <= 1'b0; idex_br_z <= 1'b0;
      idex_br_nz <= 1'b0; idex_halt <= 1'b0;
      idex_rd <= 3'd0; idex_ra_addr <= 3'd0; idex_rb_addr <= 3'd0;
      idex_ra_data <= 8'h00; idex_rb_data <= 8'h00; idex_imm <= 8'h00;
      exmem_valid <= 1'b0; exmem_reg_we <= 1'b0; exmem_mem_to_reg <= 1'b0;
      exmem_mem_we <= 1'b0; exmem_halt <= 1'b0; exmem_rd <= 3'd0;
      exmem_alu_y <= 8'h00; exmem_addr <= 8'h00; exmem_store_data <= 8'h00;
      memwb_valid <= 1'b0; memwb_reg_we <= 1'b0; memwb_rd <= 3'd0;
      memwb_data  <= 8'h00; memwb_halt <= 1'b0;
      flag_z <= 1'b0; flag_c <= 1'b0;
      draining <= 1'b0; halted <= 1'b0;

    end else if (!halted) begin
  
      // PC and IF/ID Register Update
      // Priority: Branch Flush > Halt > Load-use Stall > Normal Execution
 
      if (take_branch) begin
        pc         <= branch_target;
        ifid_instr <= 16'h0000;   // Flush wrong-path instruction
        ifid_valid <= 1'b0;
      end else if (fetch_stop) begin
        ifid_instr <= 16'h0000;   // HLT: stop fetching
        ifid_valid <= 1'b0;
      end else if (stall) begin
        // Load-use stall: keep PC and IF/ID unchanged
      end else begin
        pc         <= pc + 8'd1;  // Normal sequential execution
        ifid_instr <= if_instr;
        ifid_valid <= 1'b1;
      end

      // ID/EX Register Update
  
      if (take_branch || fetch_stop || stall) begin
        idex_valid <= 1'b0;       // Insert a bubble
      end else begin
        idex_valid       <= ifid_valid;
        idex_alu_op      <= id_alu_op;
        idex_alu_src_imm <= id_alu_src_imm;
        idex_uses_a      <= id_uses_a;
        idex_uses_b      <= id_uses_b;
        idex_reg_we      <= id_reg_we;
        idex_mem_to_reg  <= id_mem_to_reg;
        idex_mem_we      <= id_mem_we;
        idex_flag_we     <= id_flag_we;
        idex_jump        <= id_jump;
        idex_br_z        <= id_br_z;
        idex_br_nz       <= id_br_nz;
        idex_halt        <= id_halt;
        idex_rd          <= id_rd;
        idex_ra_addr     <= id_ra_addr;
        idex_rb_addr     <= id_rb_addr;
        idex_ra_data     <= id_ra_data;
        idex_rb_data     <= id_rb_data;
        idex_imm         <= id_imm8;
      end

      // EX/MEM Register Update
      // Control bits are ANDed with idex_valid to prevent bubbles from
      // accidentally writing to the register file or data memory.
 
      exmem_valid      <= idex_valid;
      exmem_reg_we     <= idex_valid && idex_reg_we;
      exmem_mem_to_reg <= idex_valid && idex_mem_to_reg;
      exmem_mem_we     <= idex_valid && idex_mem_we;
      exmem_halt       <= ex_halt;
      exmem_rd         <= idex_rd;
      exmem_alu_y      <= ex_alu_y;
      exmem_addr       <= ex_opA;      // Address = R[rs1] (forwarded)
      exmem_store_data <= ex_opB;      // Store data = R[rd] (forwarded)

      // Update flags if the instruction permits it
      if (idex_valid && idex_flag_we) begin
        flag_z <= ex_alu_z;
        flag_c <= ex_alu_c;
      end

      // Signal that HLT has been seen in EX
      if (ex_halt) draining <= 1'b1;

      // MEM/WB Register Update
    
      memwb_valid  <= exmem_valid;
      memwb_reg_we <= exmem_reg_we;
      memwb_rd     <= exmem_rd;
      memwb_data   <= mem_result;
      memwb_halt   <= exmem_halt;

      // If HLT reaches WB, the pipeline is completely empty. Freeze the CPU.
      if (memwb_halt) halted <= 1'b1;

    end else begin
      // HALTED state: Stop all write operations
      memwb_reg_we <= 1'b0;
    end
  end

  // DEBUG OUTPUTS
  
  assign pc_out     = pc;
  assign flags_out  = {flag_z, flag_c};
  assign instr_done = memwb_valid;

endmodule