`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// File: sync_fifo.v
// Description: 8-entry First-In-First-Out memory for ADC results.
// ----------------------------------------------------------------------------
// Key Features:
//   - Independent Push and Pop operations.
//   - 8-bit wide data storage, 8 entries deep (8 bytes total).
//   - Status flags: Empty, Full, and Overflow (error if push on full).
// Integration: Receives data from sar_adc_ctrl, outputs to apb_regs8.
// ============================================================================
module sync_fifo (
    input  wire       clk,         // System clock
    input  wire       rst_n,       // Active-low reset
    input  wire       push,        // Write request
    input  wire [7:0] data_in,     // Data from ADC
    input  wire       pop,         // Read request (advance to next entry)
    output wire [7:0] data_out,    // Oldest entry (0 when empty)
    output wire       empty,       // 1 = no data
    output wire       full,        // 1 = 8 entries stored
    output reg        overflow,    // 1-clock pulse: push attempted while full
    output wire [3:0] fifo_level   // Number of stored entries (0-8)
);
 
    reg [7:0] mem [0:7];           // Storage
    reg [2:0] wr_ptr, rd_ptr;      // Write / read pointers (wrap at 8)
    reg [3:0] count;               // Number of stored entries
 
    assign empty      = (count == 4'd0);
    assign full       = (count == 4'd8);
    assign fifo_level = count;
 
    // Combinational read: data is ready in the same cycle, no extra delay
    assign data_out = empty ? 8'h00 : mem[rd_ptr];
 
    // Accepted operations (ignore push when full, pop when empty)
    wire do_push = push && !full;
    wire do_pop  = pop  && !empty;
 
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr   <= 3'd0;
            rd_ptr   <= 3'd0;
            count    <= 4'd0;
            overflow <= 1'b0;
        end else begin
            overflow <= push && full;          // New data is dropped and flagged
 
            if (do_push) begin
                mem[wr_ptr] <= data_in;
                wr_ptr      <= wr_ptr + 3'd1;
            end
 
            if (do_pop)
                rd_ptr <= rd_ptr + 3'd1;
 
            // Count update: push+pop together cancel out
            case ({do_push, do_pop})
                2'b10:   count <= count + 4'd1;
                2'b01:   count <= count - 4'd1;
                default: count <= count;
            endcase
        end
    end
endmodule