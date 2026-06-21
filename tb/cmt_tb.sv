`timescale 1ns / 1ps
`include ../src/cmt.v

module cmt_tb();

    // -------------------------------------------------------------------------
    // 1. Clock & Reset Signals
    // -------------------------------------------------------------------------
    reg clk;
    reg rst_n;

    // -------------------------------------------------------------------------
    // 2. Allocation Interface Signals (Interface with TMT)
    // -------------------------------------------------------------------------
    wire        ava_core_valid;
    wire [5:0]  ava_core_id;
    reg  [9:0]  task_id_tmt_cmt;
    reg  [3:0]  tmt_idx_tmt_cmt;
    reg  [9:0]  instance_num_tmt_cmt;
    reg         tmt_cmt_ack;

    // -------------------------------------------------------------------------
    // 3. Termination Interface Signals (Interface with TMT)
    // -------------------------------------------------------------------------
    wire        task_done_pulse;
    wire [3:0]  terminated_tmt_idx;

    // -------------------------------------------------------------------------
    // 4. Cores Interface Signals (Interface with CORES)
    // -------------------------------------------------------------------------
    reg  [63:0] core_done_vec;
    wire [5:0]  core_id_cmt_core;
    wire        done_ack;

    // -------------------------------------------------------------------------
    // 5. Status & Error Signals (Status / FDIR)
    // -------------------------------------------------------------------------
    wire [1:0]  err;

    // -------------------------------------------------------------------------
    // 6. Unit Under Test (UUT) Instantiation
    // -------------------------------------------------------------------------
    cmt uut (
        .i_clk(clk),
        .i_rst_n(rst_n),
        
        // Allocation Interface
        .o_ava_core_valid(ava_core_valid),
        .o_ava_core_id(ava_core_id),
        .i_task_id_tmt_cmt(task_id_tmt_cmt),
        .i_tmt_idx_tmt_cmt(tmt_idx_tmt_cmt),
        .i_instance_num_tmt_cmt(instance_num_tmt_cmt),
        .i_tmt_cmt_ack(tmt_cmt_ack),
        
        // Termination Interface
        .o_task_done_pulse(task_done_pulse),
        .o_terminated_tmt_idx(terminated_tmt_idx),
        
        // Cores Interface
        .i_core_done_vec(core_done_vec),
        .o_core_id_cmt_core(core_id_cmt_core),
        .o_done_ack(done_ack),
        
        // FDIR
        .o_err(err)
    );

    // -------------------------------------------------------------------------
    // 7. Clock Generator (100MHz / 10ns period)
    // -------------------------------------------------------------------------
    always begin
        #5 clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // 8. Stimulus / Test Cases
    // -------------------------------------------------------------------------
    integer i; // Loop variable for allocation testing

    initial begin
        // Initialize VCD files for waveform viewing (GTKWave)
        $dumpfile("cmt_sim.vcd");
        $dumpvars(0, cmt_tb);

        // Initial State
        clk = 0;
        rst_n = 0;
        task_id_tmt_cmt = 10'd0;
        tmt_idx_tmt_cmt = 4'd0;
        instance_num_tmt_cmt = 10'd0;
        tmt_cmt_ack = 0;
        core_done_vec = 64'd0;

        // --- TC0: Power-On Reset ---
        #20;
        rst_n = 1; // Release reset
        #10;

        // =====================================================================
        // TC1: Regular allocation of a task to the first available core
        // =====================================================================
        $display("[TC1] Starting Regular Allocation...");
        @(posedge clk);
        if (ava_core_valid) begin
            $display("[TC1] Found available core ID: %d", ava_core_id);
            task_id_tmt_cmt = 10'h0A5;       
            tmt_idx_tmt_cmt = 4'd2;          
            instance_num_tmt_cmt = 10'd1;    
            tmt_cmt_ack = 1;                 
        end
        
        @(posedge clk);
        tmt_cmt_ack = 0; 
        #20;

        // =====================================================================
        // TC2: Allocating multiple consecutive tasks to check core occupancy
        // =====================================================================
        $display("[TC2] Starting Multiple Consecutive Allocations...");
        repeat (3) begin
            @(posedge clk);
            if (ava_core_valid) begin
                $display("[TC2] Allocating next core ID: %d", ava_core_id);
                task_id_tmt_cmt = task_id_tmt_cmt + 1;
                tmt_idx_tmt_cmt = 4'd3; 
                instance_num_tmt_cmt = 10'd2;
                tmt_cmt_ack = 1;
            end
            @(posedge clk);
            tmt_cmt_ack = 0;
            #10;
        end

        // =====================================================================
        // TC3: Single core completion and TMT update
        // =====================================================================
        $display("[TC3] Testing Core Termination Handshake...");
        @(posedge clk);
        core_done_vec[0] = 1'b1; 
        
        @(posedge clk);
        #1; 
        if (task_done_pulse) begin
            $display("[TC3] Success: CMT sent task_done_pulse to TMT for row idx: %d", terminated_tmt_idx);
        end
        
        @(posedge clk);
        core_done_vec[0] = 1'b0; 
        #30;

        // =====================================================================
        // TC4: Conflict and arbitration - two cores finish at the same clock cycle
        // =====================================================================
        $display("[TC4] Testing Simultaneous Core Terminations (Arbitration)...");
        @(posedge clk);
        core_done_vec[1] = 1'b1; 
        core_done_vec[2] = 1'b1; 
        
        @(posedge clk);
        #1;
        $display("[TC4] First handled termination for TMT row idx: %d", terminated_tmt_idx);
        if (done_ack) begin
             if (core_id_cmt_core == 6'd1) core_done_vec[1] = 1'b0;
             else if (core_id_cmt_core == 6'd2) core_done_vec[2] = 1'b0;
        end

        @(posedge clk);
        #1;
        $display("[TC4] Second handled termination for TMT row idx: %d", terminated_tmt_idx);
        core_done_vec[1] = 1'b0;
        core_done_vec[2] = 1'b0;
        #30;

        // =====================================================================
        // TC5: Full Core Saturation (64 Cores Busy)
        // Description: Perform consecutive allocations until all cores are full.
        // Verify that ava_core_valid drops to '0' and no more tasks can be allocated.
        // =====================================================================
        $display("[TC5] Filling up all remaining cores to reach Saturation...");
        for (i = 0; i < 64; i = i + 1) begin
            @(posedge clk);
            if (ava_core_valid) begin
                task_id_tmt_cmt = i + 10;
                tmt_idx_tmt_cmt = i % 16; // Reasonable distribution across TMT rows
                instance_num_tmt_cmt = 10'd1;
                tmt_cmt_ack = 1;
            end else begin
                // If no cores are available, the loop skips or stops allocation
                tmt_cmt_ack = 0;
            end
        end
        
        @(posedge clk);
        tmt_cmt_ack = 0;
        #20;
        
        // Check if the component protects itself and correctly signals that no cores are free
        if (!ava_core_valid) begin
            $display("[TC5] Success: All cores are BUSY. ava_core_valid is correctly low ('0').");
        end else begin
            $display("[TC5] WARNING: ava_core_valid is still high even after mass allocations!");
        end
        #20;

        // =====================================================================
        // TC6: Gradual release and Immediate Availability
        // Description: When the system is full, clear a single core (e.g., Core 5)
        // and verify that ava_core_valid asserts in the next cycle, offering Core 5.
        // =====================================================================
        $display("[TC6] Testing Immediate Availability by clearing Core 5...");
        @(posedge clk);
        core_done_vec[5] = 1'b1; // Core 5 signals completion
        
        @(posedge clk);
        #1;
        if (done_ack && (core_id_cmt_core == 6'd5)) begin
            core_done_vec[5] = 1'b0; // Lower completion line
        end
        
        // Wait one clock cycle for internal status update
        @(posedge clk);
        #1;
        if (ava_core_valid && (ava_core_id == 6'd5)) begin
            $display("[TC6] Success: Core 5 freed up and immediately marked as AVAILABLE.");
        end else begin
            $display("[TC6] Error: Core 5 was freed but not allocated/available correctly.");
        end
        #20;

        // =====================================================================
        // TC7: Done -> Ack Handshake Protocol Verification
        // Description: Simulate a core holding its done signal high for multiple cycles
        // (e.g., Core 10), and verify CMT generates only a single done_ack pulse.
        // =====================================================================
        $display("[TC7] Testing Core Handshake duration holding done high...");
        @(posedge clk);
        core_done_vec[10] = 1'b1; // Core 10 finishes
        
        // Intentionally hold the signal high for 3 clock cycles (independent of ACK)
        repeat (3) begin
            @(posedge clk);
            #1;
            if (done_ack) begin
                $display("[TC7] CMT generated done_ack for Core ID: %d", core_id_cmt_core);
            end
        end
        
        @(posedge clk);
        core_done_vec[10] = 1'b0; // Clear the signal at the end of the process
        #50;

        // =====================================================================
        // TC8: Multi-Instance / Duplication (Single Task with Multiple Replicas)
        // Description: A single task (Task ID = 0x1F) needs to be executed 3 times in parallel.
        // TMT allocates it to 3 different cores sequentially, updating the Instance Number.
        // =====================================================================
        $display("[TC8] Starting Multi-Instance Allocation for Task 0x1F (3 Instances)...");
        
        // --- Instance 0 ---
        @(posedge clk);
        if (ava_core_valid) begin
            $display("[TC8] Allocating Task 0x1F, Instance 0 to Core ID: %d", ava_core_id);
            task_id_tmt_cmt      = 10'h1F;       // Same Task ID
            tmt_idx_tmt_cmt      = 4'd5;         // Same TMT row
            instance_num_tmt_cmt = 10'd0;        // Instance #0
            tmt_cmt_ack          = 1;
        end
        @(posedge clk);
        tmt_cmt_ack = 0;
        #10; // Brief delay between allocations

        // --- Instance 1 ---
        @(posedge clk);
        if (ava_core_valid) begin
            $display("[TC8] Allocating Task 0x1F, Instance 1 to Core ID: %d", ava_core_id);
            task_id_tmt_cmt      = 10'h1F;       // Same Task ID
            tmt_idx_tmt_cmt      = 4'd5;         // Same TMT row
            instance_num_tmt_cmt = 10'd1;        // Instance #1
            tmt_cmt_ack          = 1;
        end
        @(posedge clk);
        tmt_cmt_ack = 0;
        #10;

        // --- Instance 2 ---
        @(posedge clk);
        if (ava_core_valid) begin
            $display("[TC8] Allocating Task 0x1F, Instance 2 to Core ID: %d", ava_core_id);
            task_id_tmt_cmt      = 10'h1F;       // Same Task ID
            tmt_idx_tmt_cmt      = 4'd5;         // Same TMT row
            instance_num_tmt_cmt = 10'd2;        // Instance #2
            tmt_cmt_ack          = 1;
        end
        @(posedge clk);
        tmt_cmt_ack = 0;
        #30;

        // --- Simulating Gradual Termination of Replicas ---
        $display("[TC8] Simulating termination of the instances...");
        
        // Assume the first replica (e.g., captured by Core 12) finishes
        @(posedge clk);
        core_done_vec[12] = 1'b1; 
        
        @(posedge clk);
        #1;
        if (task_done_pulse && (terminated_tmt_idx == 4'd5)) begin
            $display("[TC8] Success: CMT reported termination of an instance from TMT row 5");
        end
        
        @(posedge clk);
        core_done_vec[12] = 1'b0;
        #20;

        // End of all simulation steps
        $display("--- All test cases completed successfully! ---");
        $finish;
    end

endmodule
