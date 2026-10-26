# 8-bit RISC Processor with a 5-Stage Pipeline

A small 8-bit CPU designed in Verilog, with a 5-stage pipeline, hardware hazard handling,
a Python assembler and automatic tests. It was simulated and implemented with Xilinx Vivado.

**Author:** `<your name>`
**Internship / program:** `<name>`
**Tools:** Verilog, Vivado 2026.1, Icarus Verilog, Python 3

## Overview

| Item | Value |
|---|---|
| Data width | 8 bits |
| Instruction width | 16 bits (16 instructions) |
| Registers | 8 registers, R0 to R7 |
| Memory | 256 x 16-bit program memory, 256 x 8-bit data memory (separate, "Harvard") |
| Flags | Z (zero), C (carry / borrow) |
| Pipeline | 5 stages: Fetch, Decode, Execute, Memory, Write-back |
| Hazard handling | Forwarding, 1-cycle load-use stall, 2-cycle branch flush |

## How the pipeline works

A pipeline works like an assembly line. While one instruction is being executed, the next
one is being decoded and the one after that is being fetched, so up to 5 instructions are
in progress at the same time.

```
 IF     ->   ID     ->   EX       ->   MEM     ->   WB
 Fetch       Decode      Execute       Memory       Write the
 the         the         (ALU,         (load or     result into
 instruction instruction branch)       store)       a register
```

Overlapping instructions can cause problems, called hazards. This CPU fixes them in hardware:

| Problem | Example | Fix | Cost |
|---|---|---|---|
| An instruction needs a result that is not written yet | `ADD R1, ...` then `SUB R2, R1, ...` | Forwarding: send the result straight to the ALU | 0 cycles |
| A loaded value is needed immediately | `LD R5, [R4]` then `ADDI R5, 1` | Stall one cycle, then forward | 1 cycle |
| A taken branch makes the fetched instructions wrong | `BZ`, `BNZ`, `JMP` | Flush (cancel) the next 2 instructions | 2 cycles |

## Instruction set

| Group | Instructions | What they do |
|---|---|---|
| Arithmetic | `ADD`, `SUB`, `ADDI` | add and subtract, update Z and C |
| Logic | `AND`, `OR`, `XOR` | bitwise operations, update Z |
| Shift | `SHL`, `SHR` | shift by 1 bit, update Z and C |
| Data | `LDI`, `LD`, `ST` | load a constant, read memory, write memory |
| Control | `JMP`, `BZ`, `BNZ` | jump, jump if zero, jump if not zero |
| Other | `NOP`, `HLT` | do nothing, stop the CPU |

Every instruction is 16 bits: the top 4 bits are the opcode, the rest hold registers or a
number. Example: `ADD R2, R2, R1` is encoded as `0x1488`.

## Project structure

```
rtl/   the processor
       risc8_5stage_core.v   top level: PC, pipeline registers, branch and halt logic
       alu.v                 arithmetic and logic, produces the Z and C flags
       control_unit.v        turns the opcode into control signals
       regfile.v             the 8 registers
       hazard_unit.v         decides forwarding and stalls
       imem.v                program memory, loaded from program.hex
       dmem.v                data memory
tb/    testbenches
       tb_risc8_5stage.v     main test, prints PASS or FAIL
       tb_dump.v             saves the final state for the random test
sw/    Python tools
       program.s             test program in assembly
       asm8.py               assembler: program.s -> program.hex
       iss.py                simple reference model of the CPU
       random_test.py        random test: Verilog CPU vs reference model
program.hex                  the program loaded into the CPU
```

## How to run (Vivado)

1. Create an RTL project. Use a folder path without spaces.
2. Add the files in `rtl/` as Design Sources. The top module is `risc8_5stage_core`.
3. Add `tb/tb_risc8_5stage.v` as a Simulation Source and set it as the simulation top.
4. Add `program.hex` as a Simulation Source.
5. Click **Run Behavioral Simulation**.

The console ends with `*** ALL TESTS PASSED ***` after 545 ns.

For synthesis and implementation, also add a constraints file (`.xdc`) with the clock:

```
create_clock -period 10.000 -name clk [get_ports clk]
```

Without it Vivado shows `TIMING-17` critical warnings, because it does not know which
signal is the clock.

## Results

The test program (`sw/program.s`) covers every instruction group: logic and shifts,
forwarding, a taken branch with a wrong-path instruction that must be cancelled, a loop
that adds 5+4+3+2+1, a store followed by a load, a carry, a jump and `HLT`.

| Item | Value |
|---|---|
| Final registers R1 to R7 | `00 0F 01 20 00 66 00` |
| Data memory at address `0x20` | `0x0F` |
| Flags Z, C | 1, 1 |
| Cycles / instructions | 51 / 34 |
| CPI (cycles per instruction) | 1.50 (ideal is 1.00) |
| Load-use stalls | 1 |
| Taken branches | 6 |
| Forwarded operands | 12 |

All checks in the testbench pass.

## Random testing

A hand-written test only checks the cases I thought of, so the project also compares the
CPU against a reference model:

1. `sw/random_test.py` creates a random program.
2. The program runs on `sw/iss.py`, a simple Python model with no pipeline.
3. The same program runs on the Verilog CPU.
4. The script compares all registers, the flags and all 256 bytes of data memory.

```bash
python3 sw/random_test.py 500
```

Result: `500 random programs: RTL matches golden model in all cases`.

**A bug found this way:** the carry flag after `SHR` was always 0, but it should be the bit
shifted out. The main test did not notice it because later instructions overwrote the flag.
The random test did. Fixed in `rtl/alu.v`:

```verilog
SHR : result = {a[0], 1'b0, a[7:1]};   // C = old bit 0
```

Notes: the script needs Icarus Verilog (`iverilog`, `vvp`) and must be run from the
repository root. It overwrites `program.hex`, so afterwards run
`python3 sw/asm8.py sw/program.s program.hex` to restore the real program.

## Limitations

- No interrupts and no call/return instructions. Only the Z and C flags exist.
- Pin assignments for a physical FPGA board are not included. The design was verified in
  simulation and taken through Vivado implementation.
