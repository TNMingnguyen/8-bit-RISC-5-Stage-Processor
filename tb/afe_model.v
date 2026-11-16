`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// File: afe_model.v
// Description: Behavioural model of the analog front end (simulation only).
// ----------------------------------------------------------------------------
// Models what sits outside the ADC controller:
//   - a 4-channel analog multiplexer with a fixed voltage on each channel,
//   - a sample-and-hold (tracks the input while adc_sample = 1, then holds),
//   - an ideal DAC + comparator: cmp = 1 when the DAC guess <= held input.
//
// Voltage -> code:  code = mV * 256 / VREF_MV   (1 LSB = VREF / 256 = 12.9 mV)
//   default inputs: ch0 = 0.400 V -> 0x1F    ch1 = 1.111 V -> 0x56
//                   ch2 = 2.000 V -> 0x9B    ch3 = 3.000 V -> 0xE8
// Plain Verilog-2001, so it also works in Vivado xsim and Icarus Verilog.
//////////////////////////////////////////////////////////////////////////////////
module afe_model #(
    parameter VREF_MV = 3300,   // Full-scale voltage in millivolts
    parameter CH0_MV  = 400,    // Voltage on analog input 0
    parameter CH1_MV  = 1111,   // Voltage on analog input 1
    parameter CH2_MV  = 2000,   // Voltage on analog input 2
    parameter CH3_MV  = 3000    // Voltage on analog input 3
) (
    input  wire       adc_sample,   // 1 = track, 0 = hold
    input  wire [1:0] adc_ch,       // Selected channel
    input  wire [7:0] adc_dac,      // DAC guess from the SAR controller
    output wire       cmp           // 1 = input >= DAC guess
);

    // Convert millivolts to an 8-bit code (clamped to 255)
    function [7:0] mv_to_code;
        input integer mv;
        integer c;
        begin
            c = (mv * 256) / VREF_MV;
            if (c > 255) c = 255;
            if (c < 0)   c = 0;
            mv_to_code = c;
        end
    endfunction

    // Analog multiplexer
    reg [7:0] vin_ch;
    always @(*) begin
        case (adc_ch)
            2'd0:    vin_ch = mv_to_code(CH0_MV);
            2'd1:    vin_ch = mv_to_code(CH1_MV);
            2'd2:    vin_ch = mv_to_code(CH2_MV);
            default: vin_ch = mv_to_code(CH3_MV);
        endcase
    end

    // Sample-and-hold: follow the input while sampling, keep it afterwards
    reg [7:0] vin_held = 8'h00;
    always @(*) begin
        if (adc_sample) vin_held = vin_ch;
    end

    // Ideal comparator
    assign cmp = (adc_dac <= vin_held);

endmodule
