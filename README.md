# 8-bit RISC Processor with a 5-Stage Pipeline and an 8-bit Timer/ADC Peripheral

A small 8-bit CPU designed in Verilog, with a 5-stage pipeline, hardware hazard handling,
a Python assembler and automatic tests. It is extended with a memory-mapped **8-bit Timer +
8-bit SAR ADC peripheral** (PWM, FIFO, interrupt flags) and a full system testbench.
Simulated and synthesized with Xilinx Vivado.

**Author:** `Than Nguyen Minh Nguyen`

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
| Peripheral | 8-bit timer with PWM, 8-bit SAR ADC (4 channels), 8-entry FIFO, 16 registers at `0xF0` to `0xFF` |

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
| Logic | `AND`, `OR`, `XOR` | bitwise operations, update Z (C is cleared to 0) |
| Shift | `SHL`, `SHR` | shift by 1 bit, update Z and C |
| Data | `LDI`, `LD`, `ST` | load a constant, read memory, write memory |
| Control | `JMP`, `BZ`, `BNZ` | jump, jump if zero, jump if not zero |
| Other | `NOP`, `HLT` | do nothing, stop the CPU |

Every instruction is 16 bits: the top 4 bits are the opcode, the rest hold registers or a
number. Example: `ADD R2, R2, R1` is encoded as `0x1488`.

## Timer + ADC peripheral

The peripheral is connected to the CPU through a small I/O port on the MEM stage. A load or
store whose address is in the page `0xF0` to `0xFF` goes to the peripheral instead of RAM.

```
risc8_soc
 |- u_cpu   risc8_5stage_core   (IO_ENABLE = 1, IO_PAGE = 0xF)
 |- u_tadc  timer_adc8_top
      |- u_timer  timer8        prescaler, counter, compare, PWM
      |- u_adc    sar_adc_ctrl  sample, then 8 guesses (MSB first)
      |- u_fifo   sync_fifo     8 results
      |- u_regs   apb_regs8     16 registers, interrupt flags
```

**Changes to the CPU core** (about 15 lines in the MEM stage of `risc8_5stage_core.v`):

- New parameters `IO_ENABLE` (default 0) and `IO_PAGE` (default `4'hF`), and the port
  `io_cs`, `io_we`, `io_addr`, `io_wdata`, `io_rdata`.
- `io_cs` is high for exactly one clock per `LD`/`ST` to the I/O page, never for bubbles
  or ALU instructions, and never while halted.
- RAM is not written for the I/O page, and `LD` takes `io_rdata` for the I/O page.
- With `IO_ENABLE = 0` the core behaves exactly like the original CPU.
- The CPU reset is active-high, the peripheral reset is active-low: `rst_n = ~rst`.

**Register map**

| Address | Name | Access | Meaning |
|---|---|---|---|
| `0xF0` | TMR_CTRL | RW | bit0 EN, bit1 ONESHOT |
| `0xF1` | TMR_PRESC | RW | tick every PRESC+1 clocks |
| `0xF2` | TMR_LOAD | RW | period = LOAD+1 ticks |
| `0xF3` | TMR_CMP | RW | compare value / PWM duty |
| `0xF4` | TMR_CNT | RO | current count |
| `0xF5` | ADC_CTRL | RW | bit0 EN, bit1 START, bits3:2 TRIG_SEL, bits5:4 CH |
| `0xF6` | ADC_SMP | RW | sample window = SMP+1 ticks |
| `0xF7` | ADC_DIV | RW | ADC clock divider |
| `0xF8` | ADC_THR_LO | RW | window comparator low limit |
| `0xF9` | ADC_THR_HI | RW | window comparator high limit |
| `0xFA` | ADC_DATA | RO | oldest FIFO result (reading pops it) |
| `0xFB` | ADC_RCH | RO | bit7 VALID, bits1:0 channel (no pop) |
| `0xFC` | ADC_STAT | RO | FIFO level, EMPTY, FULL, BUSY |
| `0xFD` | IRQ_EN | RW | interrupt enables |
| `0xFE` | IRQ_STAT | W1C | event flags, write 1 to clear |
| `0xFF` | ID | RO | always `0xA8` |

Formulas: timer period = (PRESC+1) x (LOAD+1) clocks, PWM duty = CMP / (LOAD+1),
ADC conversion time = (SMP+1+8) x (DIV+1) clocks.

The CPU has no interrupt input yet, so the firmware polls `ADC_STAT` and `IRQ_STAT`.
The `irq` pin is brought out of `risc8_soc` so it can be watched.

## Project structure

```
rtl/   the processor and the system top
       risc8_5stage_core.v   top level of the CPU: PC, pipeline registers, I/O port
       risc8_soc.v           system top: CPU + Timer/ADC peripheral
       alu.v                 arithmetic and logic, produces the Z and C flags
       control_unit.v        turns the opcode into control signals
       regfile.v             the 8 registers
       hazard_unit.v         decides forwarding and stalls
       imem.v                program memory, loaded from a memory file
       dmem.v                data memory
rtl/periph/   the Timer/ADC peripheral
       timer8.v              timer: prescaler, counter, compare, PWM
       sar_adc_ctrl.v        SAR ADC state machine
       sync_fifo.v           8-entry result FIFO
       apb_regs8.v           16 registers and interrupt flags
       timer_adc8_top.v      connects the four blocks
       timer_adc8_cpu_if.v   stand-alone bus wrapper (used by tb_cpu_if.v)
tb/    testbenches
       tb_risc8_5stage.v     original CPU test, prints PASS or FAIL
       tb_risc8_soc.v        system test: CPU running the firmware + analog model
       afe_model.v           analog front-end model (mux, sample/hold, DAC, comparator)
       tb_directed.v         register-level test of the peripheral
       tb_cpu_if.v           CPU-style test of the bus wrapper
sw/    Python tools (assembler, reference model, random test)
constrs/
       risc8.xdc             clock constraint for synthesis and implementation
soc_demo.mem                 firmware for the system test (loaded into imem)
program.hex                  program of the original CPU test
```

## How to run (Vivado)

**Original CPU test**

1. Create an RTL project and add the files in `rtl/` as Design Sources (not `risc8_soc.v`
   and `periph/` if you only want the CPU). Top module: `risc8_5stage_core`.
2. Add `tb/tb_risc8_5stage.v` as a Simulation Source and set it as the simulation top.
3. Add `program.hex` as Design Source and Simulation Source.
4. Add `constrs/risc8.xdc` as a Constraints file, then **Run Behavioral Simulation**.

The console ends with `*** ALL TESTS PASSED ***`.

**System test (CPU + Timer/ADC)**

1. Add all files in `rtl/` and `rtl/periph/` as Design Sources. Set `risc8_soc` as top.
2. Add `soc_demo.mem` as a **Memory File** in Design Sources and in Simulation Sources.
   Synthesis and simulation both read it with `$readmemh`. The file name must match the
   `IMEM_FILE` parameter in `risc8_soc.v` and in `tb_risc8_soc.v`.
3. Add `tb/tb_risc8_soc.v`, `tb/afe_model.v` (and optionally `tb_directed.v`,
   `tb_cpu_if.v`) as Simulation Sources. Set `tb_risc8_soc` as the simulation top.
4. Click **Run Behavioral Simulation**, then type `run all` in the Tcl Console
   (the default 1 us is not enough).

Expected end of the log:

```
PASS: PWM high for 30 of 100 clocks
*** SOC TEST PASSED ***  (23 checks)
```

The firmware tests: reading the ID register, a software-started conversion, four
timer-triggered conversions, the window comparator with the irq pin, FIFO order, a pointer
`ADD` that must not touch the peripheral, and the PWM output (30 % duty).

## Results

**Original CPU test** (`sw/program.s`): logic and shifts, forwarding, a taken branch with a
wrong-path instruction that must be cancelled, a loop that adds 5+4+3+2+1, a store followed
by a load, a carry, a jump and `HLT`.

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

**System test (CPU + Timer/ADC)**

| Item | Value |
|---|---|
| System testbench | PASS, 23 checks |
| ADC codes | 1.111 V -> `0x56`, 2.0 V -> `0x9B`, 3.0 V -> `0xE8`, 0.40 V -> `0x1F` |
| PWM | 30 high clocks out of 100 (PRESC=0, LOAD=9, CMP=3) |
| Synthesis (xc7a35tcpg236-1, Vivado 2026.1) | 0 errors, 0 critical warnings |
| Utilization | about 506 LUT, 398 flip-flops, 8 RAM256X1S, no BRAM, no DSP |

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

Note: this script overwrites `program.hex` with random programs. Afterwards, rebuild it with
`python3 sw/asm8.py sw/program.s program.hex` before running the main testbench again.

Result: `500 random programs: RTL matches golden model in all cases`.
(The random test uses `IO_ENABLE = 0`, so the I/O page is plain RAM there.)

## Limitations

- The Timer/ADC is a simplified version: `ADC_CTRL.EN` does not gate the ADC, there is no
  continuous mode (`TRIG_SEL = 3`) and no `TRIG_MISS` flag.
- The CPU has no interrupt input, so the `irq` pin is only observed, not used.
- The analog front end (mux, sample/hold, DAC, comparator) exists only as a simulation
  model. On a real board these pins need external analog hardware.
