`timescale 1ns / 1ps

module fifo #(
    parameter FIFO_DEPTH = 128,     //number of RAM rows
    parameter FIFO_WIDTH = 64       //size of the DATA from HOST
)(
    input i_clk,
    input i_rst_n,

    // Write Port
    input i_cfg_en,
    input [FIFO_WIDTH-1:0] i_cfg_data,
    output o_full,

    // Read Port
    input i_tmt_fifo_ack,
    output o_empty,
    output wire [FIFO_WIDTH-1:0] o_fifo_tmt_data
);

    // Calculate pointer width
    localparam PTR_WIDTH = $clog2(FIFO_DEPTH);

    // Memory
    reg [FIFO_WIDTH-1:0] FIFO_mem_array [0:FIFO_DEPTH-1];

    // Binary and Gray pointers
    reg [PTR_WIDTH:0] wr_ptr_bin = 0, rd_ptr_bin = 0;
    reg [PTR_WIDTH:0] wr_ptr_gray = 0, rd_ptr_gray = 0;

    assign o_fifo_tmt_data = FIFO_mem_array[rd_ptr_bin[PTR_WIDTH-1:0]];

    // Write logic
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            wr_ptr_bin  <= 0;
            wr_ptr_gray <= 0;
        end else if (i_cfg_en && !o_full) begin
            FIFO_mem_array[wr_ptr_bin[PTR_WIDTH-1:0]] <= i_cfg_data;
            wr_ptr_bin  <= wr_ptr_bin + 1;
            wr_ptr_gray <= (wr_ptr_bin + 1) ^ (( wr_ptr_bin+ 1) >> 1);
        end
    end

    // Read logic
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            rd_ptr_bin       <= 0;
            rd_ptr_gray      <= 0;
        end else if (i_tmt_fifo_ack && !o_empty) begin
            rd_ptr_bin       <= rd_ptr_bin + 1;
            rd_ptr_gray      <= (rd_ptr_bin + 1) ^ ((rd_ptr_bin + 1) >> 1);
        end
    end

    // o_Empty condition: write and read pointers equal
    assign o_empty = (wr_ptr_gray == rd_ptr_gray);

    // o_Full condition: write pointer is one step ahead of read pointer in circular buffer
    assign o_full = (wr_ptr_gray == {~rd_ptr_gray[PTR_WIDTH:PTR_WIDTH-1], rd_ptr_gray[PTR_WIDTH-2:0]});

endmodule
