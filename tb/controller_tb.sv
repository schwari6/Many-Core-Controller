`timescale 1ns / 1ps
`include "../src/controller.v"
`include "../src/modules/fifo.v"
`include "../src/modules/cmt.v"
`include "../src/modules/tmt.v"

module controller_tb();

    // -------------------------------------------------------------------------
    // Parameters and Signals
    // -------------------------------------------------------------------------
    parameter FIFO_DEPTH = 128;
    parameter FIFO_WIDTH = 64;

    reg                   clk;
    reg                   rst_n;

    // HOST -> FIFO
    reg                   cfg_en;
    reg  [FIFO_WIDTH-1:0] cfg_data;
    wire                  full;

    // TMT -> CORES
    wire [31:0]           dispatch_addr;
    wire [5:0]            dispatch_core_id;

    // CORES -> CMT
    reg  [63:0]           core_done_vec;
    wire [5:0]            core_id_cmt_core;
    wire                  done_ack;

    // Status
    wire [3:0]            err_bus;

    // -------------------------------------------------------------------------
    // Instantiation of the Top Controller (UUT)
    // -------------------------------------------------------------------------
    controller #(
        .FIFO_DEPTH(FIFO_DEPTH),
        .FIFO_WIDTH(FIFO_WIDTH)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .cfg_en(cfg_en),
        .cfg_data(cfg_data),
        .full(full),
        .dispatch_addr(dispatch_addr),
        .dispatch_core_id(dispatch_core_id),
        .core_done_vec(core_done_vec),
        .core_id_cmt_core(core_id_cmt_core),
        .done_ack(done_ack),
        .err_bus(err_bus)
    ) ;

    // -------------------------------------------------------------------------
    // Clock Generation (300MHz)
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #1.666 clk = ~clk; // ~3.33ns period
    end

    // -------------------------------------------------------------------------
    // Waveform Dump (VCD)
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("controller_tb.vcd");
        $dumpvars(0, controller_tb);
    end

    // -------------------------------------------------------------------------
    // Helper Tasks for Stimulus & Verification
    // -------------------------------------------------------------------------
    
    // Send a task from HOST to FIFO (with safety check for FIFO full)
    task host_send_task;
        input [9:0]  id;
        input [9:0]  quota;
        input [31:0] addr;
        input [9:0]  dep;
        begin
            if (full) begin
                $display("[WARN] @%0t: Waiting for FIFO to clear before injecting Task %0d", $time, id);
                @(negedge full);
            end
            @(posedge clk);
            cfg_data = {id, quota, addr, dep, 2'b00};
            cfg_en = 1;
            @(posedge clk);
            cfg_en = 0;
            cfg_data = 0;
        end
    endtask

    // Self-checking task: Verify active cores count
    task assert_active_cores;
        input integer expected_count;
        integer actual_count;
        integer c;
        begin
            actual_count = 0;
            for (c = 0; c < 64; c = c + 1) begin
                if (uut.inst_cmt.core_busy[c]) actual_count = actual_count + 1;
            end
            if (actual_count != expected_count) begin
                $error("[CHECK FAILED] @%0t: Expected %0d active cores, but found %0d!", $time, expected_count, actual_count);
            end else begin
                $display("[CHECK PASSED] @%0t: Active cores count is exactly %0d.", $time, expected_count);
            end
        end
    endtask

    // Wait until all cores are idle (busy vector is 0)
    task wait_for_all_cores_idle;
        begin
            while (uut.inst_cmt.core_busy != 64'd0) begin
                @(posedge clk);
            end
            $display("[STATUS] @%0t: All cores are now IDLE.", $time);
        end
    endtask

    // -------------------------------------------------------------------------
    // Monitor Logic (For Script Parsing & Debug)
    // -------------------------------------------------------------------------
    integer active_cores_count;
    integer c;
    always @(posedge clk) begin
        if (rst_n) begin
            active_cores_count = 0;
            for (c = 0; c < 64; c = c + 1) begin
                if (uut.inst_cmt.core_busy[c]) active_cores_count = active_cores_count + 1;
            end
            // Format meant for a Python script
            $display("STAT_MONITOR, %0t, %0d, %016X", $time, active_cores_count, uut.inst_cmt.core_busy);
        end
    end

    // Print TMT State snapshot
    task print_tmt_snapshot;
        integer idx;
        begin
            $display("---------------------------------------------------------");
            $display("--- TMT SNAPSHOT AT TIME %0t ---", $time);
            $display("IDX | VALID | TASK_ID | QUOTA | DISP_LEFT | DONE_LEFT | FSM_STATE");
            for (idx = 0; idx < 16; idx = idx + 1) begin
                $display("%3d |   %b   |   %4d  |  %4d |     %4d  |     %4d  |     %2b", 
                    idx, 
                    uut.inst_tmt.trf_valid[idx],
                    uut.inst_tmt.trf_task_id[idx],
                    uut.inst_tmt.trf_quota[idx],
                    uut.inst_tmt.trf_dispatch_left[idx],
                    uut.inst_tmt.trf_done_left[idx],
                    uut.inst_tmt.trf_fsm_state[idx]
                );
            end
            $display("---------------------------------------------------------");
        end
    endtask

    // Print CMT State snapshot
    task print_cmt_snapshot;
        integer i;
        begin
            $display("---------------------------------------------------------------------------------------------------");
            $display("--- CMT SNAPSHOT AT TIME %0t ---", $time);
            $display("CORE | BUSY | TMT_IDX || CORE | BUSY | TMT_IDX || CORE | BUSY | TMT_IDX || CORE | BUSY | TMT_IDX");
            for (i = 0; i < 16; i = i + 1) begin
                $display(" %2d  |   %b  |   %2d    ||  %2d  |   %b  |   %2d    ||  %2d  |   %b  |   %2d    ||  %2d  |   %b  |   %2d", 
                    i,    uut.inst_cmt.core_busy[i],    uut.inst_cmt.core_tmt_idx[i],
                    i+16, uut.inst_cmt.core_busy[i+16], uut.inst_cmt.core_tmt_idx[i+16],
                    i+32, uut.inst_cmt.core_busy[i+32], uut.inst_cmt.core_tmt_idx[i+32],
                    i+48, uut.inst_cmt.core_busy[i+48], uut.inst_cmt.core_tmt_idx[i+48]
                );
            end
            $display("---------------------------------------------------------------------------------------------------");
        end
    endtask

    // -------------------------------------------------------------------------
    // Main Test Stimulus
    // -------------------------------------------------------------------------
    initial begin
        // Initialize inputs
        rst_n = 0;
        cfg_en = 0;
        cfg_data = 0;
        core_done_vec = 64'd0;

        #20;
        rst_n = 1;
        #20;

        $display("\n=========================================================");
        $display("STARTING FULL SYSTEM TEST");
        $display("=========================================================\n");

        // ---------------------------------------------------------------------
        // Scenario 1: Heavy Data Parallelism (Single Task, Quota = 10)
        // ---------------------------------------------------------------------
        $display("[SCENARIO 1] Injecting Task 100 with Quota = 10...");
        host_send_task(10'd100, 10'd10, 32'hAAAA_0000, 10'd0);
        
        // Wait for allocation to complete (using clock edges instead of fixed delays where possible)
        repeat(15) @(posedge clk);
        assert_active_cores(10); // בדיקה אוטומטית שהוקצו בדיוק 10 ליבות
        print_tmt_snapshot();

        // ---------------------------------------------------------------------
        // Scenario 2: Sequential Dependency
        // ---------------------------------------------------------------------
        $display("\n[SCENARIO 2] Injecting dependent tasks...");
        host_send_task(10'd200, 10'd2, 32'hBBBB_0000, 10'd100); // תלוי ב-100
        host_send_task(10'd300, 10'd3, 32'hCCCC_0000, 10'd200); // תלוי ב-200
        
        repeat(5) @(posedge clk);
        $display("Tasks injected. Verification: Task 200/300 should be pending due to dependencies.");
        assert_active_cores(10); // המשימות החדשות לא אמורות להתחיל עדיין!
        print_tmt_snapshot();

        // ---------------------------------------------------------------------
        // Scenario 3: Massive Simultaneous Terminations
        // ---------------------------------------------------------------------
        $display("\n[SCENARIO 3] Completing all 10 instances of Task 100 at once!");
        @(posedge clk);
        core_done_vec[9:0] = 10'h3FF; // סימולציה שכל 10 הליבות הראשונות מסיימות ביחד
        
        // נמתין בצורה דינמית עד שהליבות של משימה 100 יתפנו ומשימה 200 תתחיל
        repeat(20) @(posedge clk); 
        
        $display("Task 100 should be terminated. Task 200 should now be allocating/running.");
        assert_active_cores(2); // משימה 200 בעלת Quota=2 צריכה לרוץ כעת
        print_tmt_snapshot();

        // סיום משימה 200 (ליבות 10 ו-11)
        $display("\nCompleting Task 200 instances (Cores 0 and 1)...");
        @(posedge clk);
        core_done_vec[0] = 1'b1;
        core_done_vec[1] = 1'b1;
        #50;

        $display("Task 200 should be terminated. Task 300 should now be allocating/running.");
        print_tmt_snapshot();

        // Complete Task 300 instances (Cores 0, 1, 2 - since they are free again)
        $display("\nCompleting Task 300 instances (Cores 0, 1, 2)...");
        @(posedge clk);
        core_done_vec[0] = 1'b1;
        core_done_vec[1] = 1'b1;
        core_done_vec[2] = 1'b1;
        #50;
        
        // המתנה דינמית עד שכל הליבות חוזרות להיות פנויות
        wait_for_all_cores_idle();
        assert_active_cores(0); // בדיקה סופית שהכל ריק

        print_tmt_snapshot();
        print_cmt_snapshot();

        $display("\n=========================================================");
        $display("END OF TEST - ALL CHECKS COMPLETED");
        $display("=========================================================\n");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Synchronous Auto-Clear Core Done Logic (Fixed & Robust)
    // -------------------------------------------------------------------------
    // כאשר ה-CMT מחזיר done_ack, הליבה הרלוונטית מורידה מיד את קו ה-done שלה
    // בצורה סינכרונית ומדויקת למניעת Race Conditions.
    always @(posedge clk) begin
        if (!rst_n) begin
            // הליבות לא מאפסות את ה-core_done_vec לחלוטין כאן, כדי לא לדרוס 
            // את הסימולציה הידנית ב-initial block, אלא רק מגיבות ל-ack.
        end else if (done_ack) begin
            core_done_vec[core_id_cmt_core] <= 1'b0;
        end
    end

endmodule