`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// 8-bit Timer with Prescaler, Compare, and PWM output.
//////////////////////////////////////////////////////////////////////////////////

module timer8 (
    input  wire       clk,         // System clock
    input  wire       rst_n,       // Active-low reset
    input  wire       en,          // 1 = run, 0 = stop and reset
    input  wire       oneshot,     // 1 = stop after overflow (stopping is done in apb_regs8)
    input  wire [7:0] presc,       // Prescaler (divide clock by presc + 1)
    input  wire [7:0] load,        // Max count value (then wraps to 0)
    input  wire [7:0] cmp,         // Compare value for PWM and cmp_pulse
    output reg  [7:0] cnt,         // Current counter value
    output reg        ovf_pulse,   // 1-clock pulse when the counter wraps
    output reg        cmp_pulse,   // 1-clock pulse when counter == cmp
    output reg        pwm_out      // PWM output (high while cnt < cmp)
);
 
    reg [7:0] presc_cnt;           // Prescaler counter
    reg       tick;                // 1-clock pulse: counter should step

    // Prescaler: generates one tick every (presc + 1) clocks

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            presc_cnt <= 8'd0;
            tick      <= 1'b0;
        end else if (en) begin
            if (presc_cnt >= presc) begin
                presc_cnt <= 8'd0;
                tick      <= 1'b1;
            end else begin
                presc_cnt <= presc_cnt + 8'd1;
                tick      <= 1'b0;
            end
        end else begin
            presc_cnt <= 8'd0;     // Timer off: prescaler is reset
            tick      <= 1'b0;
        end
    end

    // Main counter: counts 0..load, then wraps and pulses ovf

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt       <= 8'd0;
            ovf_pulse <= 1'b0;
            cmp_pulse <= 1'b0;
        end else if (en) begin
            if (tick) begin
                if (cnt == load) begin
                    cnt       <= 8'd0;
                    ovf_pulse <= 1'b1;
                end else begin
                    cnt       <= cnt + 8'd1;
                    ovf_pulse <= 1'b0;
                end
                cmp_pulse <= (cnt == cmp);
            end else begin
                ovf_pulse <= 1'b0;
                cmp_pulse <= 1'b0;
            end
        end else begin
            cnt       <= 8'd0;     // Timer off: counter is reset
            ovf_pulse <= 1'b0;
            cmp_pulse <= 1'b0;
        end
    end

    // PWM: high while cnt < cmp

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)    pwm_out <= 1'b0;
        else if (en)   pwm_out <= (cnt < cmp);
        else           pwm_out <= 1'b0;
    end
 
endmodule