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
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_cfg_en(cfg_en),
        .i_cfg_data(cfg_data),
        .o_full(full),
        .i_tmt_fifo_ack(tmt_fifo_ack),
        .o_empty(empty),
        .o_fifo_tmt_data(fifo_tmt_data)
    );

    // Clock generation (250MHz)
    initial begin
        clk = 0;
        forever #2 clk = ~clk; 
    end

    // Test vector variable
    integer i;
    int error_count = 0;

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
        else begin $display("FAIL: FIFO is still empty."); error_count++; end

        // 2. Basic Read
        $display("Reading first task...");
        // In FWFT FIFO, data is available immediately! Read BEFORE ack clock cycle.
        #1;
        if (fifo_tmt_data === 64'hAAAA_BBBB_CCCC_DDDD) $display("PASS: Data matched.");
        else begin $display("FAIL: Data mismatch! Got %h", fifo_tmt_data); error_count++; end

        @(posedge clk);
        tmt_fifo_ack = 1;
        @(posedge clk);
        tmt_fifo_ack = 0;
        
        // Check empty flag
        #1;
        if (empty == 1) $display("PASS: FIFO is empty after read.");
        else begin $display("FAIL: FIFO is not empty."); error_count++; end

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
        else begin $display("FAIL: FIFO 'full' flag is low."); error_count++; end

        // Try to write while full (should be ignored by FIFO logic)
        @(posedge clk);
        cfg_data = 64'hFFFF_FFFF;
        cfg_en = 1;
        @(posedge clk);
        cfg_en = 0;

        // 4. Read all data back and verify
        $display("Emptying the FIFO...");
        
        for (i = 0; i < FIFO_DEPTH; i = i + 1) begin
            @(posedge clk); // Align to clock edge
            #1; // Sample the data slightly after the edge (to let combinational logic settle)
            
            // Check current data
            if (fifo_tmt_data !== i) begin
                $display("FAIL at index %d: Got %h", i, fifo_tmt_data);
                error_count++;
            end
            
            // Assert ACK so the NEXT clock edge pops it
            tmt_fifo_ack = 1; 
        end
        
        // Clear ACK after the last pop
        @(posedge clk); #1
        tmt_fifo_ack = 0;

        // Verify empty
        #1;
        if (empty == 1) $display("PASS: FIFO correctly emptied.");
        else begin $display("FAIL: FIFO not empty after full read."); error_count++; end

        $display("===============================================================");
        if (error_count == 0) $display("   FIFO VERIFICATION PASSED WITH 0 ERRORS!");
        else $display("   FIFO VERIFICATION FAILED with %0d errors.", error_count);
        $display("===============================================================");
        
        $finish;
    end

endmodule