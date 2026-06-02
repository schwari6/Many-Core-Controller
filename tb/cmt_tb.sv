`timescale 1ns / 1ps
`include "../src/modules/cmt.v"

module cmt_tb();

    // Inputs
    reg         clk;
    reg         rst_n;
    reg  [9:0]  task_id_tmt_cmt;
    reg  [3:0]  tmt_idx_tmt_cmt;
    reg  [9:0]  instance_num_tmt_cmt;
    reg         tmt_cmt_ack;
    reg  [63:0] core_done_vec;

    // Outputs
    wire        ava_core_valid;
    wire [5:0]  ava_core_id;
    wire        task_done_pulse;
    wire [3:0]  terminated_tmt_idx;
    wire [5:0]  core_id_cmt_core;
    wire        done_ack;
    wire [1:0]  err;

    // Instantiate the Unit Under Test (UUT)
    cmt uut (
        .clk(clk),
        .rst_n(rst_n),
        .ava_core_valid(ava_core_valid),
        .ava_core_id(ava_core_id),
        .task_id_tmt_cmt(task_id_tmt_cmt),
        .tmt_idx_tmt_cmt(tmt_idx_tmt_cmt),
        .instance_num_tmt_cmt(instance_num_tmt_cmt),
        .tmt_cmt_ack(tmt_cmt_ack),
        .task_done_pulse(task_done_pulse),
        .terminated_tmt_idx(terminated_tmt_idx),
        .core_done_vec(core_done_vec),
        .core_id_cmt_core(core_id_cmt_core),
        .done_ack(done_ack),
        .err(err)
    );

    // Clock generation (300MHz -> ~3.33ns period, using 4ns for simple 250MHz simulation)
    initial begin
        clk = 0;
        forever #2 clk = ~clk; 
    end

    initial begin
        // Initialize Inputs
        rst_n = 0;
        task_id_tmt_cmt = 10'd0;
        tmt_idx_tmt_cmt = 4'd0;
        tmt_cmt_ack = 0;
        core_done_vec = 64'd0;

        // Reset the system
        #10;
        rst_n = 1;
        #10;

        $display("--- Start of CMT Test ---");

        // ---------------------------------------------------------------------
        // 1. Test Allocation (Idle core detection)
        // ---------------------------------------------------------------------
        $display("Testing Allocation...");
        // UUT should indicate core 0 is available immediately after reset
        if (ava_core_valid && ava_core_id == 6'd0) $display("PASS: Found idle core 0.");
        else $display("FAIL: Did not find idle core 0.");

        // Allocate TMT row index 5 to core 0
        @(posedge clk);
        task_id_tmt_cmt = 10'd57;
        tmt_idx_tmt_cmt = 4'd5;
        tmt_cmt_ack = 1;
        @(posedge clk);
        tmt_cmt_ack = 0; // Drop ack
        
        #1;
        // Now core 0 is busy, core 1 should be the next available
        if (ava_core_valid && ava_core_id == 6'd1) $display("PASS: Core 0 is busy, found next idle core 1.");
        else $display("FAIL: Core 1 not found. Found %d instead.", ava_core_id);

        // Allocate TMT row index 9 to core 1
        @(posedge clk);
        task_id_tmt_cmt = 10'd58;
        tmt_idx_tmt_cmt = 4'd9;
        tmt_cmt_ack = 1;
        @(posedge clk);
        tmt_cmt_ack = 0;

        // ---------------------------------------------------------------------
        // 2. Test Termination & Arbitration (Multiple cores finish together)
        // ---------------------------------------------------------------------
        $display("Testing Termination and Arbitration...");
        
        // Cores 0 and 1 finish simultaneously
        @(posedge clk);
        core_done_vec[0] = 1'b1;
        core_done_vec[1] = 1'b1;

        // Cycle 1: CMT should process core 0 first (due to Priority Encoder)
        @(posedge clk);
        #1;
        if (task_done_pulse && terminated_tmt_idx == 4'd5 && done_ack && core_id_cmt_core == 6'd0) begin
            $display("PASS: Core 0 termination processed correctly.");
            core_done_vec[0] = 1'b0; // Core 0 drops its line after receiving done_ack
        end else $display("FAIL: Core 0 not processed correctly.");

        // Cycle 2: CMT should process core 1 in the very next cycle
        @(posedge clk);
        #1;
        if (task_done_pulse && terminated_tmt_idx == 4'd9 && done_ack && core_id_cmt_core == 6'd1) begin
            $display("PASS: Core 1 termination processed correctly (Arbitration successful).");
            core_done_vec[1] = 1'b0; // Core 1 drops its line
        end else $display("FAIL: Core 1 not processed correctly.");

        // ---------------------------------------------------------------------
        // 3. Test Invalid Termination Error (FDIR)
        // ---------------------------------------------------------------------
        $display("Testing Invalid Termination Error...");
        @(posedge clk);
        core_done_vec[5] = 1'b1; // Core 5 raises Done, but was never allocated!
        
        @(posedge clk);
        #1;
        if (err == 2'b10) $display("PASS: Caught invalid termination on core 5.");
        else $display("FAIL: Did not catch invalid termination. Err = %b", err);
        
        core_done_vec[5] = 1'b0;

        $display("--- End of CMT Test ---");
        $finish;
    end

endmodule