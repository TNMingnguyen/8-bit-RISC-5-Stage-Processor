`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// File: tb_directed.v
// Description: Directed Testbench for the internal Top module.
// ----------------------------------------------------------------------------
// Key Features:
//   - Bypasses the CPU wrapper to test the core directly.
//   - Checks default reset values of the registers.
//   - Performs direct register write/read-back tests.
//   - Verifies ADC conversion and FIFO operations.
// Integration: Instantiates timer_adc8_top.v directly.
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

module tb_directed();

    reg        clk;
    reg        rst_n;
    reg        cs;
    reg        we;
    reg  [3:0] addr;
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
    integer k;
    reg [7:0] rd_val;                  // Result of the last read_reg

    timer_adc8_top uut (
        .clk(clk), .rst_n(rst_n),
        .cs(cs), .we(we), .addr(addr), .wdata(wdata), .rdata(rdata),
        .irq(irq), .pwm_out(pwm_out),
        .adc_sample(adc_sample), .adc_ch(adc_ch), .adc_dac(adc_dac),
        .cmp(cmp), .analog_in(analog_in)
    );

    // 50 MHz clock
    always #10 clk = ~clk;

    // Ideal comparator: input voltage = {analog_in, 4'b0000}
    always @(*) begin
        cmp = (adc_dac > {analog_in, 4'b0000}) ? 1'b0 : 1'b1;
    end

    // ---------------- Bus tasks ----------------
    // One-clock register write
    task write_reg(input [3:0] a, input [7:0] d);
        begin
            @(posedge clk); cs <= 1; we <= 1; addr <= a; wdata <= d;
            @(posedge clk); cs <= 0; we <= 0;
        end
    endtask

    // One-clock register read, result stored in rd_val
    task read_reg(input [3:0] a);
        begin
            @(posedge clk); cs <= 1; we <= 0; addr <= a;
            #8; rd_val = rdata;                    // rdata is combinational: sample before the next edge
            @(posedge clk); cs <= 0;               // cs lasts exactly one clock
        end
    endtask

    // ---------------- Checking tasks ----------------
    task report(input ok, input [255:0] name, input [7:0] got, input [7:0] exp);
        begin
            if (ok) begin
                $display("[PASS] %0s: got=0x%02h exp=0x%02h", name, got, exp);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s: got=0x%02h exp=0x%02h", name, got, exp);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Read a register and compare with an exact value
    task check_reg(input [3:0] a, input [7:0] expected, input [255:0] name);
        begin
            read_reg(a);
            report(rd_val === expected, name, rd_val, expected);
        end
    endtask

    // Check a single condition (used for the irq wire)
    task check_bit(input cond, input [255:0] name);
        begin
            if (cond) begin
                $display("[PASS] %0s", name);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s", name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Start one software conversion on channel 0 and wait until it is done
    task do_convert(input [3:0] ain);
        begin
            analog_in = ain;
            write_reg(4'h5, 8'h02);        // START = 1, software trigger
            #300;                          // 15 clocks (conversion takes about 11)
        end
    endtask

    // ---------------- Test sequence ----------------
    initial begin
        clk = 0; rst_n = 0; cs = 0; we = 0; addr = 0; wdata = 0;
        analog_in = 4'b1000;               // Input = 0x80
        #100 rst_n = 1;

        $display("=======================================");
        $display("[TB_DIRECTED] Starting Core Test...");
        $display("=======================================");

        // 1. Reset defaults
        $display("--- 1. Reset defaults ---");
        check_reg(4'hF, 8'hA8, "ID register");
        check_reg(4'h2, 8'hFF, "TMR_LOAD default");
        check_reg(4'h3, 8'h80, "TMR_CMP default");
        check_reg(4'h6, 8'h04, "ADC_SMP default");
        check_reg(4'h9, 8'hFF, "ADC_THR_HI default");
        check_reg(4'hC, 8'h10, "ADC_STAT default (empty)");

        // 2. Register write / read-back
        $display("--- 2. Register read/write ---");
        write_reg(4'h1, 8'h55); check_reg(4'h1, 8'h55, "TMR_PRESC");
        write_reg(4'h7, 8'h3A); check_reg(4'h7, 8'h3A, "ADC_DIV");
        write_reg(4'h8, 8'h12); check_reg(4'h8, 8'h12, "ADC_THR_LO");
        write_reg(4'h9, 8'hEF); check_reg(4'h9, 8'hEF, "ADC_THR_HI");
        write_reg(4'h7, 8'h00);            // Back to fast ADC
        write_reg(4'h8, 8'h00);            // Back to default window (0..255)
        write_reg(4'h9, 8'hFF);

        // 3. Timer, periodic mode
        $display("--- 3. Timer ---");
        write_reg(4'h1, 8'h00);            // PRESC = 0
        write_reg(4'h2, 8'h05);            // LOAD  = 5
        write_reg(4'h3, 8'h02);            // CMP   = 2
        write_reg(4'h0, 8'h01);            // Enable
        #210;
        read_reg(4'h4);
        report(rd_val <= 8'd5, "TMR_CNT within 0..LOAD", rd_val, 8'd5);
        write_reg(4'h0, 8'h00);            // Disable: counter must reset
        repeat (3) @(posedge clk);
        check_reg(4'h4, 8'h00, "TMR_CNT reset when EN=0");
        check_reg(4'hE, 8'h03, "IRQ_STAT: TMR_OVF + TMR_CMP");
        write_reg(4'hE, 8'h03);            // W1C
        check_reg(4'hE, 8'h00, "IRQ_STAT cleared by W1C");

        // 4. Timer, one-shot mode
        write_reg(4'h0, 8'h03);            // ONESHOT = 1, EN = 1
        #400;
        check_reg(4'h0, 8'h02, "one-shot: EN auto-cleared");
        write_reg(4'hE, 8'hFF);            // Clear all flags

        // 5. ADC conversion, interrupt and FIFO read
        $display("--- 5. ADC conversion ---");
        write_reg(4'h6, 8'h00);            // SMP = 0 (fast)
        write_reg(4'h7, 8'h00);            // DIV = 0 (fast)
        write_reg(4'hD, 8'h04);            // Enable ADC_EOC interrupt
        do_convert(4'h8);                  // Input 0x80
        check_bit(irq,                     "irq high after EOC");
        check_reg(4'hC, 8'h01, "ADC_STAT: 1 item, not empty");
        check_reg(4'hB, 8'h80, "ADC_RCH: valid, CH0");
        check_reg(4'hA, 8'h80, "ADC_DATA = 0x80");
        check_reg(4'hC, 8'h10, "ADC_STAT: empty after read");
        check_reg(4'hE, 8'h04, "IRQ_STAT: ADC_EOC");
        write_reg(4'hE, 8'h04);
        repeat (2) @(posedge clk);
        check_bit(!irq,                    "irq low after W1C");

        // 6. Window comparator
        $display("--- 6. Window comparator ---");
        write_reg(4'h8, 8'h30);            // LO = 0x30
        write_reg(4'h9, 8'h70);            // HI = 0x70
        do_convert(4'h2);                  // 0x20 is below LO -> ADC_WD
        check_reg(4'hE, 8'h0C, "below window: EOC + WD");
        check_reg(4'hA, 8'h20, "ADC_DATA = 0x20");
        write_reg(4'hE, 8'hFF);
        do_convert(4'h5);                  // 0x50 inside window -> no WD
        check_reg(4'hE, 8'h04, "inside window: EOC only");
        check_reg(4'hA, 8'h50, "ADC_DATA = 0x50");
        write_reg(4'hE, 8'hFF);
        write_reg(4'h8, 8'h00);
        write_reg(4'h9, 8'hFF);

        // 7. FIFO: fill, overflow, order
        $display("--- 7. FIFO ---");
        for (k = 1; k <= 8; k = k + 1) do_convert(k[3:0]);   // Codes 0x10..0x80
        check_reg(4'hC, 8'h28, "ADC_STAT: full, level 8");
        do_convert(4'h9);                                    // 9th result is dropped
        check_reg(4'hE, 8'h14, "IRQ_STAT: EOC + FIFO_OVR");
        check_reg(4'hC, 8'h28, "ADC_STAT: still full");
        check_reg(4'hA, 8'h10, "FIFO order 1 (oldest)");
        check_reg(4'hC, 8'h07, "ADC_STAT: level 7");
        check_reg(4'hA, 8'h20, "FIFO order 2");
        check_reg(4'hA, 8'h30, "FIFO order 3");
        check_reg(4'hA, 8'h40, "FIFO order 4");
        check_reg(4'hA, 8'h50, "FIFO order 5");
        check_reg(4'hA, 8'h60, "FIFO order 6");
        check_reg(4'hA, 8'h70, "FIFO order 7");
        check_reg(4'hA, 8'h80, "FIFO order 8 (9th was dropped)");
        check_reg(4'hC, 8'h10, "ADC_STAT: empty again");

        $display("=======================================");
        $display("[TB_DIRECTED] Summary: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("=======================================");
        $finish;
    end

endmodule
