`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// File: sar_adc_ctrl.v
// Description: Successive Approximation Register (SAR) ADC Controller.
// ----------------------------------------------------------------------------
// Key Features:
//   - 4-state FSM: IDLE, SAMPLE, CONVERT, DONE.
//   - Configurable sample time to allow analog front-end settling.
//   - 8-bit binary search algorithm (Guesses MSB down to LSB).
//   - Generates End-Of-Conversion (EOC) pulse for FIFO synchronization.
// Integration: Triggered by Timer or Software. Sends DAC guesses and reads CMP.
// ============================================================================
module sar_adc_ctrl (
    input  wire       clk,
    input  wire       rst_n,      // Active-low reset
    input  wire       start,      // 1-clock pulse to start a new conversion
    input  wire [1:0] ch,         // Analog channel select (0-3)
    input  wire [7:0] smp,        // Sample time (steps to track the input)
    input  wire [7:0] div,        // Clock divider (clocks per step = div + 1)
    input  wire       cmp,        // Comparator result (1 = Vin >= Vdac)
    output reg  [7:0] dac,        // DAC guess voltage
    output reg        sample,     // 1 = Sample (track), 0 = Hold
    output reg  [1:0] ch_out,     // Channel currently being converted
    output reg        busy,       // Conversion in progress flag
    output reg        eoc,        // End-Of-Conversion 1-clock pulse
    output reg  [7:0] result      // Final 8-bit conversion result
);
 
    // FSM states
    localparam IDLE = 2'b00, SAMPLE = 2'b01, CONVERT = 2'b10, DONE = 2'b11;
    reg [1:0] state;
 
    reg [7:0] div_cnt;            // Clock divider counter
    reg [7:0] smp_cnt;            // Sample step counter
    reg [2:0] bit_cnt;            // Bit index being tested (7 down to 0)
    reg [7:0] sar_reg;            // Bits decided so far
    integer i;                    // Loop variable for the DAC logic

    // DAC guess (combinational)
    //   bits above bit_cnt : already decided (from sar_reg)
    //   bit bit_cnt        : set to 1 to test it
    //   bits below bit_cnt : 0
    // A for-loop is used because Verilog has no variable part-select.

    always @(*) begin
        dac = 8'h00;
        if (state == SAMPLE) begin
            dac = 8'h80;                              // Half-scale while tracking
        end else if (state == CONVERT) begin
            for (i = 0; i < 8; i = i + 1) begin
                if (i > bit_cnt)       dac[i] = sar_reg[i];
                else if (i == bit_cnt) dac[i] = 1'b1;
                else                   dac[i] = 1'b0;
            end
        end
    end

    // State machine

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            busy    <= 1'b0;
            eoc     <= 1'b0;
            sample  <= 1'b0;
            result  <= 8'h00;
            div_cnt <= 8'h00;
            smp_cnt <= 8'h00;
            bit_cnt <= 3'd0;
            sar_reg <= 8'h00;
            ch_out  <= 2'b00;
        end else begin
            eoc <= 1'b0;                              // Default: EOC is a single pulse
 
            case (state)
                // Wait for a start trigger
                IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy    <= 1'b1;
                        state   <= SAMPLE;
                        sample  <= 1'b1;              // Start tracking the input
                        ch_out  <= ch;                // Latch the channel
                        smp_cnt <= 8'h00;
                        div_cnt <= 8'h00;
                    end
                end
 
                // Track the input so the hold capacitor can settle
                SAMPLE: begin
                    if (div_cnt == div) begin
                        div_cnt <= 8'h00;
                        if (smp_cnt == smp) begin
                            sample  <= 1'b0;          // Hold the voltage
                            state   <= CONVERT;
                            bit_cnt <= 3'd7;          // Start from the MSB
                            sar_reg <= 8'h00;
                        end else begin
                            smp_cnt <= smp_cnt + 8'd1;
                        end
                    end else begin
                        div_cnt <= div_cnt + 8'd1;
                    end
                end
 
                // 8-step binary search
                CONVERT: begin
                    if (div_cnt == div) begin
                        div_cnt <= 8'h00;
 
                        // Keep the bit if the input is >= the guess
                        sar_reg[bit_cnt] <= cmp;
 
                        if (bit_cnt == 3'd0) begin
                            state  <= DONE;
                            // sar_reg[0] is not updated yet, so take bit 0 from cmp
                            result <= {sar_reg[7:1], cmp};
                        end else begin
                            bit_cnt <= bit_cnt - 3'd1;
                        end
                    end else begin
                        div_cnt <= div_cnt + 8'd1;
                    end
                end
 
                // Pulse EOC and return to IDLE
                DONE: begin
                    eoc   <= 1'b1;
                    state <= IDLE;
                end
            endcase
        end
    end
 
endmodule
 