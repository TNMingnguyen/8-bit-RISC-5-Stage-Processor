`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// File: timer_adc8_cpu_if.v
// Description: CPU Interface and Address Decoder Wrapper.
// ----------------------------------------------------------------------------
// Key Features:
//   - Address decoding: Activates the peripheral only for addresses 0xF0 - 0xFF.
//   - Translates CPU read/write signals into internal register addresses.
//   - Provides a clean, memory-mapped interface for any 8-bit RISC CPU.
// Integration: This is the top-level module that connects to the main CPU bus.
// ============================================================================
module timer_adc8_cpu_if (
    input  wire       clk, 
    input  wire       rst_n,
    // CPU Bus
    input  wire [7:0] addr, 
    input  wire       we,         
    input  wire [7:0] wdata,
    output wire [7:0] rdata,
    output wire       irq,
    output wire       pwm_out,
    // Analog Front End
    output wire       adc_sample, 
    output wire [1:0] adc_ch, 
    output wire [7:0] adc_dac,
    input  wire       cmp, 
    input  wire [3:0] analog_in
);

    // Chip Select: Activate only if the upper 4 bits of address are 1111 (0xF0 to 0xFF)
    wire cs = (addr[7:4] == 4'hF); 
    // Map the lower 4 bits to the internal 16 registers (0x0 to 0xF)
    wire [3:0] reg_addr = addr[3:0]; 

    // Instantiate the main hardware top module
    timer_adc8_top u_top (
        .clk(clk), .rst_n(rst_n),
        .cs(cs), .we(we), .addr(reg_addr), .wdata(wdata), .rdata(rdata),
        .irq(irq), .pwm_out(pwm_out),
        .adc_sample(adc_sample), .adc_ch(adc_ch), .adc_dac(adc_dac),
        .cmp(cmp), .analog_in(analog_in)
    );

endmodule
