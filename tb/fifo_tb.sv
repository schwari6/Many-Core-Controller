`timescale 1ns / 1ps
`include "../src/modules/fifo.v"

module fifo_tb();

    // Parameters
    parameter FIFO_DEPTH = 128;
    parameter FIFO_WIDTH = 64;

    // Inputs
    reg clk;
    reg rst_n;
    reg cfg_en;
    reg [FIFO_WIDTH-1:0] cfg_data;
    reg tmt_fifo_ack;

    // Outputs
    wire full;
    wire empty;
    wire [FIFO_WIDTH-1:0] fifo_tmt_data;

    // Instantiate the Unit Under Test (UUT)
    fifo #(
        .FIFO_DEPTH(FIFO_DEPTH),
        .FIFO_WIDTH(FIFO_WIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_en(cfg_en),
        .cfg_data(cfg_data),
        .full(full),
        .tmt_fifo_ack(tmt_fifo_ack),
        .empty(empty),
        .fifo_tmt_data(fifo_tmt_data)
    );

    // Clock generation (300MHz -> ~3.33ns period, using 4ns for simplicity = 250MHz)
    initial begin
        clk = 0;
        forever #2 clk = ~clk; 
    end

    // Test vector variable
    integer i;

    initial begin
        // Initialize Inputs
        rst_n = 0;
        cfg_en = 0;
        cfg_data = 0;
        tmt_fifo_ack = 0;

        // Reset system
        #10;
        rst_n = 1;
        #10;

        $display("--- Start of FIFO Test ---");

        // 1. Basic Write
        $display("Writing first task...");
        @(posedge clk);
        cfg_data = 64'hAAAA_BBBB_CCCC_DDDD;
        cfg_en = 1;
        @(posedge clk);
        cfg_en = 0;
        
        // Check if not empty
        #1;
        if (empty == 0) $display("PASS: FIFO is not empty after write.");
        else $display("FAIL: FIFO is still empty.");

        // 2. Basic Read
        $display("Reading first task...");
        @(posedge clk);
        tmt_fifo_ack = 1;
        @(posedge clk);
        tmt_fifo_ack = 0;
        
        // Check read value and empty flag
        #1;
        if (fifo_tmt_data == 64'hAAAA_BBBB_CCCC_DDDD) $display("PASS: Data matched.");
        else $display("FAIL: Data mismatch! Got %h", fifo_tmt_data);
        
        if (empty == 1) $display("PASS: FIFO is empty after read.");
        else $display("FAIL: FIFO is not empty.");

        // 3. Fill the FIFO entirely to check 'full' flag
        $display("Filling up the FIFO...");
        @(posedge clk);
        for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
            cfg_data = i; // Write index as data
            cfg_en = 1;
            @(posedge clk);
        end
        cfg_en = 0;

        // Check full flag
        #1;
        if (full == 1) $display("PASS: FIFO 'full' flag is high.");
        else $display("FAIL: FIFO 'full' flag is low.");

        // Try to write while full (should be ignored by FIFO logic)
        @(posedge clk);
        cfg_data = 64'hFFFF_FFFF;
        cfg_en = 1;
        @(posedge clk);
        cfg_en = 0;

        // 4. Read all data back and verify
        $display("Emptying the FIFO...");
        @(posedge clk);
        for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
            tmt_fifo_ack = 1;
            @(posedge clk);
            if (fifo_tmt_data !== i) $display("FAIL at index %d: Got %h", i, fifo_tmt_data);
        end
        tmt_fifo_ack = 0;

        // Verify empty
        #1;
        if (empty == 1) $display("PASS: FIFO correctly emptied.");
        else $display("FAIL: FIFO not empty after full read.");

        $display("--- End of FIFO Test ---");
        $finish;
    end

endmodule