`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// File: tb_risc8_soc.v
// Description: Self-checking system testbench: CPU + Timer/ADC peripheral.
// ----------------------------------------------------------------------------
// What it does:
//   1. Runs the firmware soc_demo.hex (built from sw/soc_demo.s) on risc8_soc.
//   2. Connects the analog front-end model (afe_model.v) to the ADC pins.
//   3. After the CPU halts, checks the 18 result bytes the firmware stored in
//      RAM (0x80-0x91), the irq pin behaviour and the PWM duty cycle.
//   4. Writes io_trace.csv (one line per clock) to inspect every bus access.
//
// Checks (23): 1 CPU halted, 18 RAM bytes, RAM page 0xF0-0xFF untouched,
//              irq went high in part D, irq is low at the end,
//              PWM is high 30 of 100 clocks.
// Optional: compile with -DDUMP to write risc8_soc.vcd for a waveform viewer.
//////////////////////////////////////////////////////////////////////////////////
module tb_risc8_soc;

    // ------------------------------------------------------------------
    // Signals
    // ------------------------------------------------------------------
    reg         clk = 1'b0;
    reg         rst = 1'b1;

    wire        halted;
    wire [7:0]  pc;
    wire        irq;
    wire        pwm_out;
    wire        adc_sample;
    wire [1:0]  adc_ch;
    wire [7:0]  adc_dac;
    wire        adc_cmp;

    integer     errors   = 0;
    integer     checks   = 0;
    integer     cycles   = 0;      // clocks since reset release
    integer     io_count = 0;      // clocks with a peripheral access
    integer     pwm_high = 0;      // PWM-high clocks counted after halt
    integer     k;
    reg         irq_seen = 1'b0;   // irq pin was high at some time
    reg         ram_clean;         // RAM bytes 0xF0-0xFF were never written
    integer     trace;             // file handle of io_trace.csv

    // ------------------------------------------------------------------
    // Device under test and analog model
    // ------------------------------------------------------------------
    risc8_soc #(.IMEM_FILE("soc_demo.mem")) dut (
        .clk(clk), .rst(rst),
        .halted(halted), .pc_out(pc),
        .irq(irq), .pwm_out(pwm_out),
        .adc_sample(adc_sample), .adc_ch(adc_ch),
        .adc_dac(adc_dac), .adc_cmp(adc_cmp)
    );

    afe_model u_afe (
        .adc_sample(adc_sample), .adc_ch(adc_ch),
        .adc_dac(adc_dac), .cmp(adc_cmp)
    );

    // 100 MHz clock
    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // Monitors
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst && !halted) cycles <= cycles + 1;
        if (dut.io_cs)       io_count <= io_count + 1;
        if (irq)             irq_seen <= 1'b1;
    end

    // io_trace.csv: the bus signals as the CPU sees them in each clock
    initial begin
        trace = $fopen("io_trace.csv", "w");
        $fwrite(trace, "cycle,pc,io_cs,io_we,io_addr,io_wdata,io_rdata,irq\n");
    end
    always @(posedge clk) if (!rst) begin
        $fwrite(trace, "%0d,%02h,%b,%b,%h,%02h,%02h,%b\n",
                cycles, pc, dut.io_cs, dut.io_we, dut.io_addr,
                dut.io_wdata, dut.io_rdata, irq);
    end

    // ------------------------------------------------------------------
    // Check tasks
    // ------------------------------------------------------------------
    task check_mem(input [7:0] a, input [7:0] exp, input [319:0] name);
        reg [7:0] got;
        begin
            got = dut.u_cpu.u_dmem.mem[a];
            checks = checks + 1;
            if (got === exp)
                $display("PASS: MEM[%02h] = %02h  %0s", a, got, name);
            else begin
                $display("FAIL: MEM[%02h] = %02h, expected %02h  %0s", a, got, exp, name);
                errors = errors + 1;
            end
        end
    endtask

    task check_cond(input ok, input [319:0] name);
        begin
            checks = checks + 1;
            if (ok) $display("PASS: %0s", name);
            else begin
                $display("FAIL: %0s", name);
                errors = errors + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Main sequence
    // ------------------------------------------------------------------
    initial begin
`ifdef DUMP
        $dumpfile("risc8_soc.vcd");
        $dumpvars(0, tb_risc8_soc);
`endif
        $display("[1/1] Running soc_demo.hex on risc8_soc");
        #22 rst = 1'b0;

        // Wait for HLT, with a watchdog (200 000 clocks)
        fork : run
            begin wait (halted); disable run; end
            begin repeat (200000) @(posedge clk); disable run; end
        join

        check_cond(halted === 1'b1, "01  CPU reached HLT (no timeout)");
        $display("CPU halted after %0d cycles, %0d I/O accesses", cycles, io_count);

        // A: ID register
        check_mem(8'h80, 8'hA8, "A: ID register");
        // B: software start, channel 1 (1.111 V)
        check_mem(8'h81, 8'h81, "B: ADC_RCH = valid, ch1");
        check_mem(8'h82, 8'h56, "B: ch1 code (1.111 V)");
        // C: four timer-triggered samples, channel 2 (2.0 V)
        for (k = 0; k < 4; k = k + 1) begin
            check_mem(8'h83 + 2*k, 8'h82, "C: ADC_RCH = valid, ch2");
            check_mem(8'h84 + 2*k, 8'h9B, "C: ch2 code (2.0 V), timer start");
        end
        check_mem(8'h8B, 8'h07, "C: IRQ_STAT = OVF|CMP|EOC");
        check_mem(8'h8C, 8'h03, "C: IRQ_STAT after W1C 0x04");
        // D: window comparator, channel 3 (3.0 V > 100)
        check_mem(8'h8D, 8'h0C, "D: IRQ_STAT = EOC|WD");
        check_mem(8'h8E, 8'hE8, "D: ch3 code (3.0 V)");
        // F: two queued results popped back to back
        check_mem(8'h8F, 8'h1F, "F: 1st pop, ch0 code (0.40 V)");
        check_mem(8'h90, 8'h56, "F: 2nd pop, ch1 code (1.111 V)");
        check_mem(8'h91, 8'h10, "F: ADC_STAT = empty after 2 pops");

        // Stores to the I/O page go to the peripheral and never reach the RAM
        ram_clean = 1'b1;
        for (k = 0; k < 16; k = k + 1)
            if (dut.u_cpu.u_dmem.mem[8'hF0 + k] !== 8'h00) ram_clean = 1'b0;
        check_cond(ram_clean, "I/O page stores never reached RAM");

        // irq pin
        check_cond(irq_seen === 1'b1, "irq pin went high during part D");
        check_cond(irq === 1'b0,      "irq pin was cleared by the acknowledge");

        // E: PWM duty cycle. The timer keeps running after HLT.
        // Period = 10 clocks, so 100 clocks hold exactly 10 periods.
        for (k = 0; k < 100; k = k + 1) begin
            @(posedge clk);
            if (pwm_out) pwm_high = pwm_high + 1;
        end
        check_cond(pwm_high == 30, "PWM high for 30 of 100 clocks");
        $display("PWM high clocks: %0d of 100", pwm_high);

        $display("--------------------------------------------------");
        if (errors == 0) $display("*** SOC TEST PASSED ***  (%0d checks)", checks);
        else             $display("*** SOC TEST FAILED ***  (%0d of %0d checks failed)", errors, checks);
        $display("--------------------------------------------------");
        $fclose(trace);
        $finish;
    end

endmodule
