`timescale 1ns / 1ps
`include "../src/modules/cmt.v"

module cmt_tb();

    logic        clk;
    logic        rst_n;

    logic        ava_core_valid;
    logic [5:0]  ava_core_id;
    logic [9:0]  task_id_tmt_cmt;
    logic [3:0]  tmt_idx_tmt_cmt;
    logic [9:0]  instance_num_tmt_cmt;
    logic        tmt_cmt_ack;

    logic        task_done_pulse;
    logic [3:0]  terminated_tmt_idx;

    logic [63:0] core_done_vec;
    logic [5:0]  core_id_cmt_core;
    logic        done_ack;

    logic [1:0]  err;

    cmt uut (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .o_ava_core_valid(ava_core_valid),
        .o_ava_core_id(ava_core_id),
        .i_task_id_tmt_cmt(task_id_tmt_cmt),
        .i_tmt_idx_tmt_cmt(tmt_idx_tmt_cmt),
        .i_instance_num_tmt_cmt(instance_num_tmt_cmt),
        .i_tmt_cmt_ack(tmt_cmt_ack),
        .o_task_done_pulse(task_done_pulse),
        .o_terminated_tmt_idx(terminated_tmt_idx),
        .i_core_done_vec(core_done_vec),
        .o_core_id_cmt_core(core_id_cmt_core),
        .o_done_ack(done_ack),
        .o_err(err)
    );

    int error_count = 0;
    int pass_count  = 0;
    int expected_tmt_idx_per_core[64];
    
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    initial begin
        #100000;
        $display("\n\033[0;31m[FATAL] Watchdog Timer Expired! Simulation Hung.\033[0m");
        $finish;
    end

    task reset_system();
        rst_n = 0;
        task_id_tmt_cmt = 0;
        tmt_idx_tmt_cmt = 0;
        instance_num_tmt_cmt = 0;
        tmt_cmt_ack = 0;
        core_done_vec = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask

    task assert_eq(int actual, int expected, string msg);
        if (actual !== expected) begin
            $display("\033[0;31m[FAIL]\033[0m %s | Expected: %0h, Actual: %0h", msg, expected, actual);
            error_count++;
        end else begin
            pass_count++;
        end
    endtask

    task allocate_task(input [9:0] t_id, input [3:0] t_idx, input [9:0] inst_num, output [5:0] allocated_core);
        @(posedge clk);
        #1; 
        if (!ava_core_valid) begin
            $display("\033[0;31m[FAIL]\033[0m Attempted to allocate but no core is valid!");
            error_count++;
        end else begin
            // Code was moved inside the 'else' block to avoid using 'return'
            allocated_core = ava_core_id;
            expected_tmt_idx_per_core[allocated_core] = t_idx;
            
            task_id_tmt_cmt = t_id;
            tmt_idx_tmt_cmt = t_idx;
            instance_num_tmt_cmt = inst_num;
            tmt_cmt_ack = 1;
            
            @(posedge clk);
            #1;
            tmt_cmt_ack = 0;
        end
    endtask

    task core_terminate(input [5:0] core_id);
        @(posedge clk);
        #1;
        core_done_vec[core_id] = 1'b1;
        
        wait(done_ack == 1'b1 && core_id_cmt_core == core_id);
        
        assert_eq(task_done_pulse, 1'b1, $sformatf("Core %0d: task_done_pulse must be 1", core_id));
        assert_eq(terminated_tmt_idx, expected_tmt_idx_per_core[core_id], $sformatf("Core %0d: Incorrect TMT idx reported", core_id));

        // Clear immediately to avoid FDIR double-termination error on next posedge
        core_done_vec[core_id] = 1'b0; 
    endtask

    initial begin
        logic [5:0] core_a, core_b, core_c;
        $display("===============================================================");
        $display("                 STARTING CMT VERIFICATION                     ");
        $display("===============================================================");
        
        reset_system();

        $display("\n--- [TEST 1] Sanity: Single Allocation & Termination ---");
        allocate_task(10'h0A5, 4'd2, 10'd1, core_a);
        assert_eq(core_a, 6'd0, "T1: First allocation should go to Core 0");
        
        core_terminate(core_a);
        
        @(posedge clk);
        assert_eq(uut.core_busy[core_a], 1'b0, "T1: Core 0 should not be busy after termination");

        $display("\n--- [TEST 2] Multi-Instance Allocation ---");
        allocate_task(10'h100, 4'd5, 10'd0, core_a);
        allocate_task(10'h100, 4'd5, 10'd1, core_b);
        allocate_task(10'h100, 4'd5, 10'd2, core_c);
        
        assert_eq(core_a, 6'd0, "T2: Core A should be 0");
        assert_eq(core_b, 6'd1, "T2: Core B should be 1");
        assert_eq(core_c, 6'd2, "T2: Core C should be 2");
        
        core_terminate(core_c);
        core_terminate(core_a);
        core_terminate(core_b);

        $display("\n--- [TEST 3] Simultaneous Terminations (Arbitration) ---");
        allocate_task(10'h200, 4'd1, 10'd0, core_a); 
        allocate_task(10'h201, 4'd2, 10'd0, core_b); 
        allocate_task(10'h202, 4'd3, 10'd0, core_c); 
        
        @(posedge clk);
        core_done_vec[core_a] = 1'b1;
        core_done_vec[core_b] = 1'b1;
        core_done_vec[core_c] = 1'b1;

        @(posedge clk); #1;
        assert_eq(done_ack, 1'b1, "T3: Expected ACK for Core 0");
        assert_eq(core_id_cmt_core, core_a, "T3: Core 0 should win arbitration");
        core_done_vec[core_a] = 1'b0;

        @(posedge clk); #1;
        assert_eq(done_ack, 1'b1, "T3: Expected ACK for Core 1");
        assert_eq(core_id_cmt_core, core_b, "T3: Core 1 should be handled next");
        core_done_vec[core_b] = 1'b0;

        @(posedge clk); #1;
        assert_eq(done_ack, 1'b1, "T3: Expected ACK for Core 2");
        assert_eq(core_id_cmt_core, core_c, "T3: Core 2 should be handled last");
        core_done_vec[core_c] = 1'b0;

        $display("\n--- [TEST 4] Saturation (All 64 Cores) ---");
        reset_system();
        
        for (int i = 0; i < 64; i++) begin
            logic [5:0] temp_core;
            allocate_task(10'h300 + i, i % 16, 10'd0, temp_core);
        end
        
        @(posedge clk); #1;
        assert_eq(ava_core_valid, 1'b0, "T4: ava_core_valid MUST be 0 when all 64 cores are busy");
        assert_eq(uut.core_busy, 64'hFFFF_FFFF_FFFF_FFFF, "T4: All core_busy bits should be 1");

        $display("T4: Releasing Core 42 to check immediate availability...");
        core_terminate(6'd42);
        
        @(posedge clk); #1;
        assert_eq(ava_core_valid, 1'b1, "T4: Core 42 released, valid should be 1");
        assert_eq(ava_core_id, 6'd42, "T4: Core 42 should be the available core");

        $display("\n--- [TEST 5] FDIR: Invalid Termination ---");
        reset_system();
        assert_eq(uut.core_busy[10], 1'b0, "T5: Pre-condition: Core 10 must not be busy");
        
        @(posedge clk);
        core_done_vec[10] = 1'b1;
        
        @(posedge clk); #1;
        assert_eq(err, 2'b10, "T5: Error injected! Err should be 2'b10 (Invalid Termination ID)");
        core_done_vec[10] = 1'b0; 

        @(posedge clk); #1;
        assert_eq(err, 2'b00, "T5: Error should clear in the next cycle");

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