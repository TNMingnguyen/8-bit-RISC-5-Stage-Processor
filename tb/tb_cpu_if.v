`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// File: tb_cpu_if.v
// Description: Self-checking Testbench for the CPU Interface.
// ----------------------------------------------------------------------------
// Key Features:
//   - Simulates an 8-bit CPU bus (Address, Write Enable, Data).
//   - Models the Analog Front-End (Comparator logic) to respond to ADC guesses.
//   - Executes a full test sequence: ID check, Timer config, ADC trigger, 
//     FIFO read, and Interrupt verification.
// Integration: Instantiates timer_adc8_cpu_if.
// ============================================================================
module tb_cpu_if();

    reg        clk;
    reg        rst_n;
    reg  [7:0] addr;
    reg        we;
    reg  [7:0] wdata;
    wire [7:0] rdata;

    wire       irq;
    wire       pwm_out;
    wire       adc_sample;
    wire [1:0] adc_ch;
    wire [7:0] adc_dac;
    reg        cmp;
    reg  [3:0] analog_in;

    integer pass_count = 0;
    integer fail_count = 0;

    timer_adc8_cpu_if uut (
        .clk(clk), .rst_n(rst_n),
        .addr(addr), .we(we), .wdata(wdata), .rdata(rdata),
        .irq(irq), .pwm_out(pwm_out),
        .adc_sample(adc_sample), .adc_ch(adc_ch), .adc_dac(adc_dac),
        .cmp(cmp), .analog_in(analog_in)
    );

    // 50 MHz clock
    always #10 clk = ~clk;

    // Ideal comparator: 1 when the DAC guess is not above the input
    always @(*) begin
        cmp = (adc_dac > {analog_in, 4'b0000}) ? 1'b0 : 1'b1;
    end

    // One-clock CPU write, then release the bus
    task cpu_write(input [7:0] a, input [7:0] d);
        begin
            @(posedge clk); addr <= a; we <= 1; wdata <= d;
            @(posedge clk); we <= 0; addr <= 8'h00;
        end
    endtask

    // One-clock CPU read (data is ready in the same clock) and compare with the expected value
    task check_reg(input [7:0] a, input [7:0] expected, input [319:0] name);
        reg [7:0] actual;
        begin
            @(posedge clk); addr <= a; we <= 0;
            #8; actual = rdata;                    // rdata is combinational: sample before the next edge
            @(posedge clk); addr <= 8'h00;         // cs lasts exactly one clock

            if (actual === expected) begin
                $display("[PASS] Check %0s: got=0x%02h exp=0x%02h", name, actual, expected);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] Check %0s: got=0x%02h exp=0x%02h", name, actual, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Check a single condition (used for the irq wire)
    task check_bit(input cond, input [319:0] name);
        begin
            if (cond) begin
                $display("[PASS] Check %0s", name);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] Check %0s", name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        clk = 0; rst_n = 0; addr = 8'h00; we = 0; wdata = 0;
        analog_in = 4'b1010;                       // Input = 0xA0
        #100 rst_n = 1;

        $display("=======================================");
        $display("[TB] Starting 20 CPU Integration Checks...");
        $display("=======================================");

        //  1. Register defaults 
        check_reg(8'hFF, 8'hA8, "01 ID register");
        check_reg(8'hF2, 8'hFF, "02 TMR_LOAD default");
        check_reg(8'hF3, 8'h80, "03 TMR_CMP default");
        check_reg(8'hF6, 8'h04, "04 ADC_SMP default");

        cpu_write(8'hF1, 8'h55);
        check_reg(8'hF1, 8'h55, "05 TMR_PRESC read/write");

        cpu_write(8'hF0, 8'h01);
        check_reg(8'hF0, 8'h01, "06 TMR_CTRL enabled");

        cpu_write(8'hF6, 8'h01);
        check_reg(8'hF6, 8'h01, "07 ADC_SMP config");

        cpu_write(8'hF7, 8'h01);
        check_reg(8'hF7, 8'h01, "08 ADC_DIV config");

        //  2. Software-triggered ADC and interrupt 
        cpu_write(8'hFD, 8'h04);                   // Enable ADC_EOC interrupt
        cpu_write(8'hF5, 8'h22);                   // START, software trigger, channel 2
        #600;                                      // Conversion takes about 24 clocks

        check_reg(8'hFB, 8'h82, "09 ADC_RCH = 0x82 (valid, CH2)");
        check_reg(8'hFA, 8'hA0, "10 ADC_DATA = 0xA0");

        cpu_write(8'hFE, 8'h04);                   // W1C: clear the EOC flag
        #40;
        check_bit(!irq,         "11 irq low after W1C");

        check_reg(8'hFE, 8'h00, "12 EOC cleared in IRQ_STAT");
        check_reg(8'hFE, 8'h00, "13 all IRQ_STAT flags clear");
        check_reg(8'hFC, 8'h10, "14 ADC_STAT: FIFO empty");

        //  3. Thresholds and compare register
        cpu_write(8'hF8, 8'h20);
        check_reg(8'hF8, 8'h20, "15 ADC_THR_LO = 0x20");

        cpu_write(8'hF9, 8'hE0);
        check_reg(8'hF9, 8'hE0, "16 ADC_THR_HI = 0xE0");

        cpu_write(8'hF3, 8'h04);
        check_reg(8'hF3, 8'h04, "17 TMR_CMP = 0x04");

        //  4. Timer-compare-triggered ADC
        cpu_write(8'hF0, 8'h00);                   // Stop and reset the timer first
        cpu_write(8'hF1, 8'h00);                   // PRESC = 0 (tick every clock)
        cpu_write(8'hF2, 8'h0A);                   // LOAD  = 10
        cpu_write(8'hF5, 8'h3B);                   // EN=1, trigger = timer compare, CH3
        cpu_write(8'hF0, 8'h01);                   // Start the timer
        #800;                                      // Wait for the first conversion

        check_reg(8'hFB, 8'h83, "18 ADC_RCH = 0x83 (valid, CH3)");
        check_reg(8'hFA, 8'hA0, "19 CMP-triggered ADC_DATA = 0xA0");

        //  5. One-shot timer
        cpu_write(8'hF0, 8'h00);                   // Stop and reset
        cpu_write(8'hF0, 8'h03);                   // ONESHOT=1, EN=1
        #400;
        check_reg(8'hF0, 8'h02, "20 one-shot TMR_CTRL auto-stopped");

        $display("=======================================");
        $display("tb_cpu_if Summary: %0d PASSED, %0d FAILED (Total: %0d/20)",
                 pass_count, fail_count, pass_count + fail_count);
        $display("=======================================");
        $finish;
    end
endmodule
