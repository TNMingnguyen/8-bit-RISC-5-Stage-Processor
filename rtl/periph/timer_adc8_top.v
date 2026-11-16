`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// File: timer_adc8_top.v
// Description: Top-level integration module for the peripheral.
// ----------------------------------------------------------------------------
// Key Features:
//   - Instantiates and wires all internal IP blocks.
//   - Contains the ADC Trigger Multiplexer (Software, Timer OVF, Timer CMP).
//   - Routes data and control signals between the Register File and sub-modules.
// Integration: Instantiated inside the CPU Interface wrapper.
// ============================================================================
module timer_adc8_top (
    input  wire       clk,
    input  wire       rst_n,        // Active-low reset
 
    // CPU-side register bus (one access per clock)
    input  wire       cs,           // Chip select
    input  wire       we,           // 1 = write, 0 = read
    input  wire [3:0] addr,         // Register address (0x0 - 0xF)
    input  wire [7:0] wdata,        // Write data
    output wire [7:0] rdata,        // Read data
 
    output wire       irq,          // Interrupt request to CPU
    output wire       pwm_out,      // PWM output from timer
 
    // Analog front-end interface
    output wire       adc_sample,   // 1 = track input, 0 = hold
    output wire [1:0] adc_ch,       // Selected analog channel
    output wire [7:0] adc_dac,      // DAC guess voltage
    input  wire       cmp,          // Comparator result (1 = Vin >= Vdac)
    input  wire [3:0] analog_in     // Analog input value (used only by the testbench model)
);

    // Internal wires

    // Timer
    wire       tmr_en, tmr_oneshot;
    wire [7:0] tmr_presc, tmr_load, tmr_cmp, tmr_cnt;
    wire       tmr_ovf, tmr_cmp_pulse;
 
    // ADC
    wire       adc_en, adc_start;
    wire [1:0] adc_trig_sel;
    wire [7:0] adc_smp, adc_div;
    wire       adc_busy, adc_eoc;
    wire [7:0] adc_result;
 
    // FIFO
    wire       fifo_push = adc_eoc;  // Push every finished conversion into the FIFO
    wire       fifo_pop;             // High while the CPU reads ADC_DATA
    wire [7:0] fifo_dout;
    wire       fifo_empty, fifo_full;
    wire       fifo_ovf;             // Push attempted while the FIFO was full
    wire [3:0] fifo_level;           // 0..8 entries

    // ADC trigger multiplexer
    //   0 = software (START bit), 1 = timer overflow, 2 = timer compare, 3 = none

    wire adc_trigger = (adc_trig_sel == 2'd0) ? adc_start     :
                       (adc_trig_sel == 2'd1) ? tmr_ovf       :
                       (adc_trig_sel == 2'd2) ? tmr_cmp_pulse : 1'b0;

    // 8-bit timer

    timer8 u_timer (
        .clk(clk), .rst_n(rst_n),
        .en(tmr_en), .oneshot(tmr_oneshot),
        .presc(tmr_presc), .load(tmr_load), .cmp(tmr_cmp),
        .cnt(tmr_cnt),
        .ovf_pulse(tmr_ovf), .cmp_pulse(tmr_cmp_pulse),
        .pwm_out(pwm_out)
    );

    // SAR ADC controller

    sar_adc_ctrl u_adc (
        .clk(clk), .rst_n(rst_n),
        .start(adc_trigger), .ch(adc_ch),
        .smp(adc_smp), .div(adc_div),
        .cmp(cmp), .dac(adc_dac),
        .sample(adc_sample), .ch_out(),      // ch_out is not used at this level
        .busy(adc_busy), .eoc(adc_eoc), .result(adc_result)
    );
 
    // Result FIFO (8 entries)

    sync_fifo u_fifo (
        .clk(clk), .rst_n(rst_n),
        .push(fifo_push), .data_in(adc_result),
        .pop(fifo_pop),   .data_out(fifo_dout),
        .empty(fifo_empty), .full(fifo_full),
        .overflow(fifo_ovf),
        .fifo_level(fifo_level)
    );

    // Register file + interrupt logic

    apb_regs8 u_regs (
        .clk(clk), .rst_n(rst_n),
        .cs(cs), .we(we), .addr(addr), .wdata(wdata), .rdata(rdata),
 
        // Timer control / status
        .tmr_en(tmr_en), .tmr_oneshot(tmr_oneshot),
        .tmr_presc(tmr_presc), .tmr_load(tmr_load), .tmr_cmp(tmr_cmp),
        .tmr_cnt(tmr_cnt), .tmr_ovf(tmr_ovf), .tmr_cmp_pulse(tmr_cmp_pulse),
 
        // ADC control / status (thresholds are used only inside apb_regs8)
        .adc_en(adc_en), .adc_start(adc_start),
        .adc_trig_sel(adc_trig_sel), .adc_ch(adc_ch),
        .adc_smp(adc_smp), .adc_div(adc_div),
        .adc_thr_lo(), .adc_thr_hi(),
        .adc_busy(adc_busy), .adc_eoc(adc_eoc), .adc_result(adc_result),
 
        // FIFO status / data
        .fifo_data(fifo_dout), .fifo_empty(fifo_empty), .fifo_full(fifo_full),
        .fifo_ovf(fifo_ovf),
        .fifo_pop(fifo_pop), .fifo_level(fifo_level),
 
        // Interrupt
        .irq(irq)
    );
 
endmodule