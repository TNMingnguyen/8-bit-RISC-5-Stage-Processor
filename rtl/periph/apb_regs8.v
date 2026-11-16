`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// File: apb_regs8.v
// Description: 16-Register Control Center and Interrupt Logic.
// ----------------------------------------------------------------------------
// Key Features:
//   - Memory-mapped 16 registers (0x0 to 0xF) for CPU configuration.
//   - Sticky interrupt flags (W1C - Write 1 to Clear) for robust event handling.
//   - Aggregates 6 interrupt sources (Timer, ADC, FIFO) into a single IRQ wire.
//   - Automatically pops FIFO when CPU reads the ADC_DATA register.
// Integration: Acts as the central hub, controlling Timer, ADC, and FIFO.
// ============================================================================
module apb_regs8 (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       cs,              // Register access this clock
    input  wire       we,              // 1 = write, 0 = read
    input  wire [3:0] addr,            // Register address
    input  wire [7:0] wdata,
    output reg  [7:0] rdata,

    // Timer
    output reg        tmr_en,
    output reg        tmr_oneshot,
    output reg  [7:0] tmr_presc,
    output reg  [7:0] tmr_load,
    output reg  [7:0] tmr_cmp,
    input  wire [7:0] tmr_cnt,
    input  wire       tmr_ovf,
    input  wire       tmr_cmp_pulse,

    // ADC
    output reg        adc_en,
    output reg        adc_start,       // 1-clock pulse
    output reg  [1:0] adc_trig_sel,
    output reg  [1:0] adc_ch,
    output reg  [7:0] adc_smp,
    output reg  [7:0] adc_div,
    output reg  [7:0] adc_thr_lo,
    output reg  [7:0] adc_thr_hi,
    input  wire       adc_busy,
    input  wire       adc_eoc,
    input  wire [7:0] adc_result,

    // FIFO
    input  wire [7:0] fifo_data,
    input  wire       fifo_empty,
    input  wire       fifo_full,
    input  wire       fifo_ovf,
    output wire       fifo_pop,        // Combinational: high while CPU reads ADC_DATA
    input  wire [3:0] fifo_level,      // 0..8

    output wire       irq
);

    reg [7:0] reg_irq_en;              // Interrupt enable bits
    reg [7:0] reg_irq_stat;            // Sticky interrupt flags
    reg [7:0] last_rch;                // {VALID, 5'b0, channel} of the last result

    // Reading ADC_DATA removes one entry from the FIFO in the same clock
    assign fifo_pop = cs && !we && (addr == 4'hA);

    // Event flags (one per interrupt source)
    wire flag_tmr_ovf  = tmr_ovf;
    wire flag_tmr_cmp  = tmr_cmp_pulse;
    wire flag_adc_eoc  = adc_eoc;
    wire flag_adc_wd   = adc_eoc && ((adc_result < adc_thr_lo) || (adc_result > adc_thr_hi));
    wire flag_fifo_ovr = fifo_ovf;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tmr_en       <= 1'b0;
            tmr_oneshot  <= 1'b0;
            tmr_presc    <= 8'h00;
            tmr_load     <= 8'hFF;
            tmr_cmp      <= 8'h80;
            adc_en       <= 1'b0;
            adc_start    <= 1'b0;
            adc_trig_sel <= 2'b00;
            adc_ch       <= 2'b00;
            adc_smp      <= 8'h04;
            adc_div      <= 8'h00;
            adc_thr_lo   <= 8'h00;
            adc_thr_hi   <= 8'hFF;
            reg_irq_en   <= 8'h00;
            reg_irq_stat <= 8'h00;
            last_rch     <= 8'h00;
        end else begin
            adc_start <= 1'b0;                         // START is a one-clock pulse

            // Remember which channel produced the latest result
            if (adc_eoc)
                last_rch <= {1'b1, 5'b00000, adc_ch};

            // CPU write 
            if (cs && we) begin
                case (addr)
                    4'h0: begin tmr_oneshot <= wdata[1]; tmr_en <= wdata[0]; end
                    4'h1: tmr_presc <= wdata;
                    4'h2: tmr_load  <= wdata;
                    4'h3: tmr_cmp   <= wdata;
                    4'h5: begin
                        adc_en       <= wdata[0];
                        adc_start    <= wdata[1];
                        adc_trig_sel <= wdata[3:2];
                        adc_ch       <= wdata[5:4];
                    end
                    4'h6: adc_smp    <= wdata;
                    4'h7: adc_div    <= wdata;
                    4'h8: adc_thr_lo <= wdata;
                    4'h9: adc_thr_hi <= wdata;
                    4'hD: reg_irq_en <= wdata;
                    4'hE: reg_irq_stat <= reg_irq_stat & ~wdata;   // W1C
                    default: ;
                endcase
            end

            // One-shot: hardware clears EN after the first overflow.
            // Placed after the CPU write so it has higher priority.
            if (tmr_ovf && tmr_oneshot)
                tmr_en <= 1'b0;

            // Set sticky flags. These come last so a new event wins over a
            // same-clock CPU clear (no event is ever lost).
            if (flag_tmr_ovf)  reg_irq_stat[0] <= 1'b1;
            if (flag_tmr_cmp)  reg_irq_stat[1] <= 1'b1;
            if (flag_adc_eoc)  reg_irq_stat[2] <= 1'b1;
            if (flag_adc_wd)   reg_irq_stat[3] <= 1'b1;
            if (flag_fifo_ovr) reg_irq_stat[4] <= 1'b1;
        end
    end

    // CPU read (combinational): the byte is ready in the same clock as cs/addr.
    // It is 0 when not selected, so it can be OR-ed with other devices.

    always @(*) begin
        rdata = 8'h00;
        if (cs && !we) begin
            case (addr)
                4'h0: rdata = {6'b0, tmr_oneshot, tmr_en};
                4'h1: rdata = tmr_presc;
                4'h2: rdata = tmr_load;
                4'h3: rdata = tmr_cmp;
                4'h4: rdata = tmr_cnt;
                4'h5: rdata = {2'b0, adc_ch, adc_trig_sel, 1'b0, adc_en};  // START reads 0
                4'h6: rdata = adc_smp;
                4'h7: rdata = adc_div;
                4'h8: rdata = adc_thr_lo;
                4'h9: rdata = adc_thr_hi;
                4'hA: rdata = fifo_data;                                   // Pops FIFO (see fifo_pop)
                4'hB: rdata = last_rch;
                4'hC: rdata = {1'b0, adc_busy, fifo_full, fifo_empty, fifo_level};
                4'hD: rdata = reg_irq_en;
                4'hE: rdata = reg_irq_stat;
                4'hF: rdata = 8'hA8;                                       // ID
                default: rdata = 8'h00;
            endcase
        end
    end

    // IRQ is high while any enabled flag is set
    assign irq = |(reg_irq_stat & reg_irq_en);

endmodule
