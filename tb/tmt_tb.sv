`timescale 1ns / 1ps
`include "../src/modules/tmt.v"

module tmt_tb();

    // -------------------------------------------------------------------------
    // Signals & Interfaces
    // -------------------------------------------------------------------------
    logic        clk;
    logic        rst_n;

    // FIFO interface
    logic [63:0] fifo_tmt_data;
    logic        empty;
    logic        tmt_fifo_ack;

    // CMT interface (Allocation)
    logic        ava_core_valid;
    logic [5:0]  ava_core_id;
    logic        tmt_cmt_ack;
    logic [3:0]  tmt_idx_tmt_cmt;
    logic [9:0]  task_id_tmt_cmt;
    logic [9:0]  instance_id_tmt_cmt;

    // CMT interface (Termination)
    logic        task_done_pulse;
    logic [3:0]  terminated_tmt_idx;

    // Cores Interface
    logic [31:0] dispatch_addr;
    logic [5:0]  dispatch_core_id;
    
    // Status
    logic [1:0]  err;

    // -------------------------------------------------------------------------
    // UUT Instantiation
    // -------------------------------------------------------------------------
    tmt uut (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_fifo_tmt_data(fifo_tmt_data),
        .i_empty(empty),
        .o_tmt_fifo_ack(tmt_fifo_ack),
        .i_ava_core_valid(ava_core_valid),
        .i_ava_core_id(ava_core_id),
        .o_tmt_cmt_ack(tmt_cmt_ack),
        .o_tmt_idx_tmt_cmt(tmt_idx_tmt_cmt),
        .o_task_id_tmt_cmt(task_id_tmt_cmt),
        .o_instance_id_tmt_cmt(instance_id_tmt_cmt),
        .i_task_done_pulse(task_done_pulse),
        .i_terminated_tmt_idx(terminated_tmt_idx),
        .o_dispatch_addr(dispatch_addr),
        .o_dispatch_core_id(dispatch_core_id),
        .o_err(err)
    );

    // -------------------------------------------------------------------------
    // Verification Environment Variables
    // -------------------------------------------------------------------------
    int error_count = 0;
    int pass_count  = 0;
    
    // Associative array to track where tasks were stored internally
    // task_id -> tmt_idx
    int task_location_map[int]; 

    // -------------------------------------------------------------------------
    // Clock Generation & Watchdog
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #2 clk = ~clk; // 250 MHz
    end

    initial begin
        #50000;
        $display("\n\033[0;31m[FATAL] Watchdog Timer Expired! Simulation Hung.\033[0m");
        $finish;
    end

    // -------------------------------------------------------------------------
    // BFM Tasks (Bus Functional Models)
    // -------------------------------------------------------------------------
    
    // Reset System
    task reset_system();
        rst_n = 0;
        empty = 1;
        fifo_tmt_data = 0;
        ava_core_valid = 0;
        ava_core_id = 0;
        task_done_pulse = 0;
        terminated_tmt_idx = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask

    // Assert Helper
    task assert_eq(int actual, int expected, string msg);
        if (actual !== expected) begin
            $display("\033[0;31m[FAIL]\033[0m %s | Expected: %0h, Actual: %0h", msg, expected, actual);
            error_count++;
        end else begin
            pass_count++;
        end
    endtask

    // Push Task to Ingress FIFO
    task push_task(input [9:0] id, input [9:0] quota, input [31:0] addr, input [9:0] dep);
        @(posedge clk);
        #1;
        fifo_tmt_data = {id, quota, addr, dep, 2'b00};
        empty = 0;
        
        // Wait for ACK
        wait(tmt_fifo_ack == 1'b1);
        @(posedge clk);
        #1;
        empty = 1; // De-assert after taken
        fifo_tmt_data = 64'h0;
    endtask

    // Allocate a core and capture the assigned TMT Index
    task allocate_core(input [5:0] core_id, output [9:0] out_task_id, output [3:0] out_tmt_idx);
        @(posedge clk);
        #1;
        ava_core_valid = 1;
        ava_core_id = core_id;
        
        // Wait for allocation ACK
        wait(tmt_cmt_ack == 1'b1);
        out_task_id = task_id_tmt_cmt;
        out_tmt_idx = tmt_idx_tmt_cmt;
        
        // Map it for later termination
        task_location_map[out_task_id] = out_tmt_idx;
        
        @(posedge clk);
        #1;
        ava_core_valid = 0;
    endtask

    // Terminate an instance of a task
    task terminate_task_instance(input [3:0] tmt_idx);
        @(posedge clk);
        #1;
        task_done_pulse = 1;
        terminated_tmt_idx = tmt_idx;
        @(posedge clk);
        #1;
        task_done_pulse = 0;
    endtask

    // -------------------------------------------------------------------------
    // Test Sequences
    // -------------------------------------------------------------------------
    initial begin
        logic [9:0] allocated_task;
        logic [3:0] allocated_idx;

        $display("===============================================================");
        $display("                 STARTING ADVANCED TMT VERIFICATION              ");
        $display("===============================================================");
        
        reset_system();

        // =====================================================================
        // TEST 1: Basic Sanity & Multi-Instance Allocation
        // =====================================================================
        $display("\n--- [TEST 1] Sanity: Multi-Instance Task ---");
        push_task(10'd100, 10'd2, 32'hAAAA_0000, 10'd0);
        
        // Allocate Instance 0
        allocate_core(6'd10, allocated_task, allocated_idx);
        assert_eq(allocated_task, 10'd100, "T1: Allocated Task ID should be 100");
        assert_eq(instance_id_tmt_cmt, 10'd0, "T1: Instance ID should be 0");
        assert_eq(dispatch_addr, 32'hAAAA_0000, "T1: Dispatch Address Mismatch");

        // Allocate Instance 1
        allocate_core(6'd11, allocated_task, allocated_idx);
        assert_eq(instance_id_tmt_cmt, 10'd1, "T1: Instance ID should be 1");

        // Verify FSM State is ALLOCATED (2'b10)
        @(posedge clk);
        assert_eq(uut.trf_fsm_state[allocated_idx], 2'b10, "T1: FSM State should be ALL_ALLOCATED (10)");

        // Terminate both instances
        terminate_task_instance(allocated_idx);
        terminate_task_instance(allocated_idx);
        
        @(posedge clk);
        assert_eq(uut.trf_valid[allocated_idx], 1'b0, "T1: TRF Slot should be freed after termination");

        // =====================================================================
        // TEST 2: Deep Dependency Chain (Task 300 -> 200 -> 100)
        // =====================================================================
        $display("\n--- [TEST 2] Deep Dependency Chain ---");
        
        // Push in reverse order of execution (Dependency target must be present first)
        push_task(10'd10, 10'd1, 32'h0000_0010, 10'd0);  // Task 10, no dep
        push_task(10'd20, 10'd1, 32'h0000_0020, 10'd10); // Task 20, depends on 10
        push_task(10'd30, 10'd1, 32'h0000_0030, 10'd20); // Task 30, depends on 20

        // Only Task 10 should be ready. Let's allocate it.
        allocate_core(6'd1, allocated_task, allocated_idx);
        assert_eq(allocated_task, 10'd10, "T2: Only Task 10 should be ready to allocate");
        
        // Try to allocate Task 20 prematurely (Should Timeout/Fail if we block, but we use a trick)
        ava_core_valid = 1;
        ava_core_id = 6'd2;
        @(posedge clk); #1;
        assert_eq(tmt_cmt_ack, 1'b0, "T2: Task 20 should NOT be acknowledged (Blocked by Dep)");
        ava_core_valid = 0;

        // Terminate Task 10 -> Resolves Task 20's dependency
        terminate_task_instance(allocated_idx);
        
        // Now Task 20 should be ready
        allocate_core(6'd2, allocated_task, allocated_idx);
        assert_eq(allocated_task, 10'd20, "T2: Task 20 should now be allocated");

        // Terminate Task 20 -> Resolves Task 30's dependency
        terminate_task_instance(allocated_idx);

        // Now Task 30 should be ready
        allocate_core(6'd3, allocated_task, allocated_idx);
        assert_eq(allocated_task, 10'd30, "T2: Task 30 should now be allocated");
        
        terminate_task_instance(allocated_idx);

        // =====================================================================
        // TEST 3: Stress Test - Full TRF Capacity (16 Slots)
        // =====================================================================
        $display("\n--- [TEST 3] Stress Test: Full TRF Capacity ---");
        reset_system();
        
        // Fill all 16 slots with independent tasks
        for (int i = 0; i < 16; i++) begin
            push_task(1000 + i, 10'd1, 32'hBBBB_0000 + i, 10'd0);
        end
        
        // Verify TRF is full
        @(posedge clk);
        assert_eq(uut.trf_valid, 16'hFFFF, "T3: TRF should be completely full (FFFF)");
        
        // Attempting to push 17th task should NOT generate ACK immediately
        fifo_tmt_data = {10'd999, 10'd1, 32'h0, 10'd0, 2'b00};
        empty = 0;
        @(posedge clk); #1;
        assert_eq(tmt_fifo_ack, 1'b0, "T3: FIFO should backpressure when TRF is full");
        empty = 1; // Cancel request
        
        // Drain all 16 slots
        for (int i = 0; i < 16; i++) begin
            allocate_core(6'd20 + i, allocated_task, allocated_idx);
            terminate_task_instance(allocated_idx);
        end
        
        @(posedge clk);
        assert_eq(uut.trf_valid, 16'h0000, "T3: TRF should be completely empty after drain");

        // =====================================================================
        // TEST 4: FDIR Deadlock Detection (Err = 01)
        // =====================================================================
        // To trigger the deadlock in this RTL:
        // 1. TRF must be FULL (valid = FFFF)
        // 2. NO task can be in READY state (!ready_valid_comb)
        // We achieve this by:
        // Task 0: Has no dependency, Quota = 10.
        // Task 1-15: Depend on Task 0.
        // Then we allocate ALL 10 instances of Task 0. 
        // Task 0 state goes to ALLOCATED (not READY). 
        // Tasks 1-15 are PENDING (waiting for Task 0 to terminate).
        // Boom -> TRF Full + No Ready Slots = Deadlock Err.
        $display("\n--- [TEST 4] FDIR Deadlock Detection ---");
        reset_system();
        
        // 1. Push blocking task
        push_task(10'd1, 10'd10, 32'hDEAD_0001, 10'd0); // Slot 0
        
        // 2. Push 15 dependent tasks
        for (int i = 1; i < 16; i++) begin
            push_task(10'd2 + i, 10'd1, 32'hDEAD_0000 + i, 10'd1); // Depend on ID 1
        end
        
        @(posedge clk);
        assert_eq(uut.trf_valid, 16'hFFFF, "T4: TRF should be full");
        assert_eq(err, 2'b00, "T4: Err should be 00 before exhaustion");

        // 3. Exhaust Task 1's quota (Allocate 10 times)
        for (int i = 0; i < 10; i++) begin
            allocate_core(6'd40 + i, allocated_task, allocated_idx);
        end
        
        // 4. Check Deadlock Status
        @(posedge clk); #1;
        assert_eq(err, 2'b01, "T4: DEADLOCK SHOULD BE DETECTED! (Err=01)");

        // 5. Relieve Deadlock by terminating Task 1
        $display("T4: Relieving deadlock by terminating Task 1 instances...");
        for (int i = 0; i < 10; i++) begin
            terminate_task_instance(task_location_map[10'd1]); // Using the associative array map
        end

        @(posedge clk); #1;
        assert_eq(err, 2'b00, "T4: Deadlock should be cleared after blocker terminates");

        // =====================================================================
        // END OF VERIFICATION
        // =====================================================================
        $display("\n===============================================================");
        if (error_count == 0) begin
            $display("\033[0;32m   VERIFICATION PASSED! \033[0m");
            $display("   All %0d assertions passed with flying colors.", pass_count);
        end else begin
            $display("\033[0;31m   VERIFICATION FAILED \033[0m");
            $display("   Found %0d errors during testing.", error_count);
        end
        $display("===============================================================\n");
        $finish;
    end

endmodule
