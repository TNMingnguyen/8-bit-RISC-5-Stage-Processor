`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// File: risc8_soc.v
// Description: System top = 8-bit RISC 5-stage CPU + 8-bit Timer/ADC peripheral.
// ----------------------------------------------------------------------------
// What it does:
//   - Instantiates the CPU core with its I/O port enabled (page 0xF0-0xFF).
//   - Connects the CPU I/O port to the peripheral with five bus wires:
//         io_cs -> cs     io_we -> we     io_addr -> addr[3:0]
//         io_wdata -> wdata               rdata -> io_rdata
//   - Shares the clock. The CPU reset is active-high and synchronous, the
//     peripheral reset is active-low and asynchronous, so rst_n = ~rst.
//   - Brings irq, pwm_out and the four analog wires out as pins.
//
// Why timer_adc8_top and not timer_adc8_cpu_if?
//   The CPU core already decodes the I/O page and drives a one-clock chip
//   select (io_cs), so the address decoder inside timer_adc8_cpu_if is not
//   needed here. timer_adc8_cpu_if stays available for stand-alone tests.
//
// The CPU has no interrupt input yet: firmware polls ADC_STAT / IRQ_STAT.
// The irq pin is brought out so it can be watched on an LED or in simulation.
//////////////////////////////////////////////////////////////////////////////////
module risc8_soc #(
    parameter IMEM_FILE = "soc_demo.mem"   // Program loaded into instruction memory
) (
    input  wire       clk,          // System clock
    input  wire       rst,          // Synchronous reset, active high

    // CPU debug outputs
    output wire       halted,       // 1 after HLT has left the pipeline
    output wire [7:0] pc_out,       // Current program counter

    // Peripheral pins
    output wire       irq,          // Interrupt request (polling only for now)
    output wire       pwm_out,      // Timer PWM output

    // Analog front end (model in simulation, real mux/S&H/DAC/comparator on a chip)
    output wire       adc_sample,   // 1 = track input, 0 = hold
    output wire [1:0] adc_ch,       // Selected analog channel
    output wire [7:0] adc_dac,      // DAC guess voltage
    input  wire       adc_cmp       // Comparator result (1 = Vin >= Vdac)
);

    // CPU <-> peripheral bus
    wire       io_cs;               // One-clock chip select per LD / ST
    wire       io_we;               // 1 = store, 0 = load
    wire [3:0] io_addr;             // Register number 0x0 - 0xF
    wire [7:0] io_wdata;            // Store data
    wire [7:0] io_rdata;            // Load data (combinational, 0 when not selected)

    // CPU core with the I/O page enabled

    risc8_5stage_core #(
        .IMEM_FILE (IMEM_FILE),
        .IO_ENABLE (1),
        .IO_PAGE   (4'hF)
    ) u_cpu (
        .clk        (clk),
        .rst        (rst),
        .halted     (halted),
        .pc_out     (pc_out),
        .flags_out  (),
        .instr_done (),
        .io_cs      (io_cs),
        .io_we      (io_we),
        .io_addr    (io_addr),
        .io_wdata   (io_wdata),
        .io_rdata   (io_rdata)
    );

    // Timer + ADC peripheral

    timer_adc8_top u_tadc (
        .clk        (clk),
        .rst_n      (~rst),             // polarity conversion
        .cs         (io_cs),
        .we         (io_we),
        .addr       (io_addr),
        .wdata      (io_wdata),
        .rdata      (io_rdata),
        .irq        (irq),
        .pwm_out    (pwm_out),
        .adc_sample (adc_sample),
        .adc_ch     (adc_ch),
        .adc_dac    (adc_dac),
        .cmp        (adc_cmp),
        .analog_in  (4'b0000)           // unused by the RTL (testbench-only input)
    );

endmodule
