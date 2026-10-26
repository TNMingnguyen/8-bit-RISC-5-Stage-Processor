# 8-bit RISC Processor with a 5-Stage Pipeline (Verilog)

An 8-bit CPU designed from scratch in Verilog, with a 5-stage pipeline, hazard handling,
a small assembler, and automatic tests. Simulated and implemented with Xilinx Vivado.

> **Author:** `<your name>`  
> **Context:** `<internship / company / program name>`  
> **Tools:** Verilog-2001, Vivado 2026.1, Icarus Verilog, Python 3

## 1. What is this project?

A CPU (processor) runs a program, which is a list of instructions stored in memory.
This project builds a small CPU that:

- works on **8-bit numbers** (0 to 255)
- reads **16-bit instructions** (16 different instructions, for example ADD, LOAD, STORE, JUMP)
- has **8 registers** (R0 to R7), a **256-instruction program memory** and a **256-byte data memory**
- uses a **5-stage pipeline**, so up to 5 instructions are being processed at the same time

It is a learning project: the goal is to understand how a real CPU works inside, not to
compete with commercial processors.

## 2. How the pipeline works (in simple words)

A pipeline works like an assembly line. Instead of finishing one instruction completely
before starting the next one, the CPU splits the work into 5 stages:

```
 IF  ->  ID  ->  EX  ->  MEM  ->  WB
Fetch   Decode  Execute  Memory   Write
the     the     (ALU,    (load /  the result
instr.  instr.  branch)  store)   to a register
```

While instruction 1 is in EX, instruction 2 is already in ID and instruction 3 in IF.
Once the pipeline is full, one instruction finishes every clock cycle.

Overlapping instructions can cause problems called **hazards**. This design solves them in hardware:

| Problem (hazard) | Example | Solution in this project | Cost |
|---|---|---|---|
| An instruction needs a result that is not written back yet | `ADD R1,...` then `SUB R2, R1, ...` | **Forwarding**: send the result directly to the ALU input | 0 cycles |
| A value loaded from memory is needed right away | `LD R5,[R4]` then `ADDI R5, 1` | **Stall**: wait one cycle, then forward | 1 cycle |
| A taken branch makes the already-fetched instructions wrong | `BZ`, `BNZ`, `JMP` | **Flush**: cancel the two instructions after the branch | 2 cycles |

## 3. Instruction set

Every instruction is 16 bits. The top 4 bits are the opcode.

| Opcode | Instruction | What it does | Updates flags |
|---|---|---|---|
| 0 | `NOP` | do nothing | no |
| 1 | `ADD rd, rs1, rs2` | rd = rs1 + rs2 | Z, C |
| 2 | `SUB rd, rs1, rs2` | rd = rs1 - rs2 | Z, C |
| 3 | `AND rd, rs1, rs2` | rd = rs1 AND rs2 | Z |
| 4 | `OR rd, rs1, rs2` | rd = rs1 OR rs2 | Z |
| 5 | `XOR rd, rs1, rs2` | rd = rs1 XOR rs2 | Z |
| 6 | `SHL rd, rs1` | rd = rs1 shifted left by 1 | Z, C |
| 7 | `SHR rd, rs1` | rd = rs1 shifted right by 1 | Z, C |
| 8 | `LDI rd, imm8` | rd = a number written in the instruction | no |
| 9 | `ADDI rd, imm8` | rd = rd + imm8 | Z, C |
| A | `LD rd, [rs1]` | rd = data memory at address rs1 | no |
| B | `ST rd, [rs1]` | data memory at address rs1 = rd | no |
| C | `JMP addr` | jump to address | no |
| D | `BZ addr` | jump if Z = 1 (last result was zero) | no |
| E | `BNZ addr` | jump if Z = 0 | no |
| F | `HLT` | stop the processor | no |

**Flags:** `Z` (zero) is 1 when the result is 0. `C` (carry) is 1 when an addition
overflows 8 bits, a subtraction needs a borrow, or it holds the bit shifted out by SHL/SHR.

**Instruction formats** (bit 15 on the left). The opcode is always in bits 15:12.

| Format | Layout (bits) | Used by |
|---|---|---|
| R | `opcode[15:12]` `rd[11:9]` `rs1[8:6]` `rs2[5:3]` `000` | ADD, SUB, AND, OR, XOR |
| R1 | `opcode[15:12]` `rd[11:9]` `rs1[8:6]` `000000` | SHL, SHR, LD, ST |
| I | `opcode[15:12]` `rd[11:9]` `0[8]` `imm8[7:0]` | LDI, ADDI |
| J | `opcode[15:12]` `0000[11:8]` `addr8[7:0]` | JMP, BZ, BNZ |

`rd` is the destination register, `rs1` and `rs2` are source registers, `imm8` is an
8-bit number stored inside the instruction, and `addr8` is a jump target address.

Example: `ADD R2, R2, R1` = `0001 010 010 001 000` = `0x1488`.

## 4. Project structure

```
.
├── rtl/                      the processor (synthesizable Verilog)
│   ├── risc8_5stage_core.v   top level: PC, pipeline registers, flags, branch and halt logic
│   ├── alu.v                 arithmetic and logic unit, produces Z and C
│   ├── control_unit.v        decodes the opcode into control signals
│   ├── regfile.v             8 registers (2 read ports, 1 write port)
│   ├── hazard_unit.v         decides forwarding and load-use stall
│   ├── imem.v                instruction memory (ROM), loaded from program.hex
│   └── dmem.v                data memory (RAM)
├── tb/                       testbenches (simulation only)
│   ├── tb_risc8_5stage.v     main testbench, prints PASS / FAIL
│   └── tb_dump.v             writes the final state to a file for the random test
├── sw/                       Python tools
│   ├── program.s             test program in assembly
│   ├── asm8.py               assembler: program.s -> program.hex
│   ├── iss.py                reference model of the CPU (no pipeline)
│   └── random_test.py        compares the Verilog CPU against iss.py on random programs
└── program.hex               machine code loaded into the instruction memory
```

## 5. How to run

### Option A: Vivado

1. Create an **RTL Project**. Use a folder path **without spaces**.
2. Add the 7 files in `rtl/` as **Design Sources**. The top module is `risc8_5stage_core`.
3. Add `tb/tb_risc8_5stage.v` as a **Simulation Source** and set it as the simulation top.
4. Add `program.hex` as a **Simulation Source** (the CPU loads it with `$readmemh`).
5. Click **Run Behavioral Simulation**. The Tcl console should end with
   `*** ALL TESTS PASSED ***` at 545 ns.

For synthesis and implementation, add a constraints file (`.xdc`) containing one line that
tells Vivado the clock speed (10 ns = 100 MHz):

```
create_clock -period 10.000 -name clk [get_ports clk]
```

Without it, Vivado shows `TIMING-17` critical warnings because it does not know which
signal is the clock. The design itself is not wrong in that case.

### Option B: Icarus Verilog (command line)

Run from the repository root, because `program.hex` is opened with a relative path.

```bash
iverilog -g2005 -Wall -o sim.vvp \
  rtl/alu.v rtl/regfile.v rtl/imem.v rtl/dmem.v \
  rtl/control_unit.v rtl/hazard_unit.v rtl/risc8_5stage_core.v \
  tb/tb_risc8_5stage.v
vvp -n sim.vvp
```

## 6. Results

The test program `sw/program.s` exercises every instruction group: logic and shifts,
forwarding, a taken branch with a wrong-path instruction that must be cancelled, a loop
that adds 5+4+3+2+1, a store followed by a load (load-use stall), a carry, a jump, and `HLT`.

| Check | Expected value | Result |
|---|---|---|
| R1, R2, R3, R4 | `0x00`, `0x0F`, `0x01`, `0x20` | PASS |
| R5, R6, R7 | `0x00`, `0x66`, `0x00` | PASS |
| Data memory at `0x20` | `0x0F` | PASS |
| Flags Z, C | 1, 1 | PASS |

| Metric | Value |
|---|---|
| Cycles / instructions | 51 / 34 |
| CPI (cycles per instruction) | 1.50 (ideal is 1.00) |
| Load-use stalls | 1 |
| Taken branches (2-cycle flush each) | 6 |
| Forwarded operands | 12 |

## 7. Testing with a reference model

A hand-written test only checks the cases the author thought of. To check more, the
project also uses **differential testing**:

1. `sw/random_test.py` generates a random program.
2. The program runs on `sw/iss.py`, a simple Python model that executes one instruction
   at a time with no pipeline, so it cannot have hazard bugs.
3. The same program runs on the Verilog CPU through `tb/tb_dump.v`.
4. The script compares all registers, both flags and all 256 bytes of data memory.

```bash
python3 sw/random_test.py 500
```

Result: `500 random programs: RTL matches golden model in all cases`.

Notes for running it:

- Run it from the repository root, with `iverilog` and `vvp` installed and on your PATH.
- It **overwrites `program.hex`** with random programs. Afterwards, restore the real program:
  `python3 sw/asm8.py sw/program.s program.hex`
- It only generates forward branches (so every program ends). Loops are covered by the
  hand-written program.

### A bug found by this test

The random test found a real bug: the **carry flag after `SHR`** was always 0, but it
should hold the bit that was shifted out. The directed test did not notice it, because
later instructions overwrote the flag before it was checked. The fix in `rtl/alu.v`:

```verilog
SHR : result = {a[0], 1'b0, a[7:1]};   // C = old bit 0
```

After the fix, all 500 random programs match the reference model.

## 8. Write your own program

```asm
        LDI  R1, 5          ; counter
        LDI  R2, 0          ; sum
        LDI  R3, 1
loop:
        ADD  R2, R2, R1     ; sum = sum + counter
        SUB  R1, R1, R3     ; counter = counter - 1
        BNZ  loop           ; repeat while counter is not 0
        HLT
```

Assemble it into the file the CPU loads:

```bash
python3 sw/asm8.py sw/program.s program.hex
```

Note: `tb_risc8_5stage.v` checks fixed expected values for the bundled `program.s`, so it
reports FAIL for a different program. For your own code, look at the per-cycle trace it
prints or at the waveform.

## 9. Concepts practiced in this project

- RTL design: combinational vs sequential logic, registers, multiplexers
- CPU design: instruction set, datapath, control unit, register file, ALU
- Pipelining: pipeline registers, valid bits and bubbles, forwarding, stalls, flushes
- Verification: self-checking testbench, reference model, random differential testing
- Tools: Vivado simulation, synthesis, implementation and timing constraints; Python scripting

## 10. Known limitations

- Memories use asynchronous reads, which keeps the design simple (data is available in the
  same cycle as the address) but means they are built from LUT RAM, not block RAM.
- No interrupts, no subroutine call/return instructions, only Z and C flags.
- Pin assignments for a physical FPGA board are not included. The project was verified in
  simulation and taken through Vivado implementation.
