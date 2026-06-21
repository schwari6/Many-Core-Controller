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

    logic                    clk;
    logic                    rst_n;

    // HOST -> FIFO
    logic                    cfg_en;
    logic [FIFO_WIDTH-1:0]   cfg_data;
    logic                    full;

    // TMT -> CORES
    logic [31:0]             dispatch_addr;
    logic [5:0]              dispatch_core_id;

    // CORES -> CMT
    logic [63:0]             core_done_vec;
    logic [5:0]              core_id_cmt_core;
    logic                    done_ack;

    // Status
    logic [3:0]              err_bus;

    // -------------------------------------------------------------------------
    // UUT Instantiation
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
    );

    // -------------------------------------------------------------------------
    // Clock & Watchdog
    // -------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #1.666 clk = ~clk; // ~300MHz
    end

    initial begin
        #2000000;
        $display("\n\033[0;31m[FATAL] Watchdog Timer Expired!\033[0m");
        $finish;
    end

    // -------------------------------------------------------------------------
    // System Telemetry & Event Monitors (For Python Analytics)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            $display("LOG_SYS,%0t,%0d,%b", $time, $countones(uut.inst_cmt.core_busy), full);
            
            if (uut.tmt_cmt_ack_wire) begin
                $display("LOG_ALLOC,%0t,%0d,%0d", $time, uut.task_id_tmt_cmt_wire, uut.ava_core_id_wire);
            end
            
            if (done_ack) begin
                $display("LOG_FREE,%0t,%0d,%0d", $time, 
                         uut.inst_cmt.core_task_id[core_id_cmt_core], 
                         core_id_cmt_core);
            end
        end
    end

    // -------------------------------------------------------------------------
    // Synchronous Auto-Clear Core Done Logic
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n && done_ack) begin
            core_done_vec[core_id_cmt_core] <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Tasks (BFMs & Print Monitors)
    // -------------------------------------------------------------------------
    task host_send_task(input [9:0] id, input [9:0] quota, input [31:0] addr, input [9:0] dep);
        if (full) begin
            $display("[WARN] FIFO Full. Waiting for system to drain...");
            @(negedge full);
        end
        @(posedge clk);
        
        $display("LOG_HOST,%0t,%0d,%0d,%0d", $time, id, quota, dep); 
        
        cfg_data = {id, quota, addr, dep, 2'b00};
        cfg_en = 1;
        @(posedge clk);
        cfg_en = 0;
        cfg_data = 0;
    endtask

    task wait_for_cores(input int target_cores);
        int current_cores;
        do begin
            @(posedge clk);
            current_cores = $countones(uut.inst_cmt.core_busy);
        end while (current_cores != target_cores);
    endtask

    task finish_active_cores(input [63:0] mask);
        @(posedge clk);
        core_done_vec |= mask;
    endtask

    // Random finisher: mimics real-world unpredictable core completion times
    task run_random_completions(input int cycles);
        int active_count;
        repeat(cycles) begin
            @(posedge clk);
            for (int i = 0; i < 64; i++) begin
                // Only finish cores that are currently busy (to avoid FDIR triggers)
                if (uut.inst_cmt.core_busy[i] == 1'b1 && core_done_vec[i] == 1'b0) begin
                    // 2% chance per cycle to finish a busy core
                    if (($urandom() % 100) < 2) begin
                        core_done_vec[i] <= 1'b1;
                    end
                end
            end
        end
    endtask

    task print_tmt_snapshot();
        $display("\n=====================================================================");
        $display("=                  TMT SNAPSHOT @ TIME %0t                   =", $time);
        $display("=====================================================================");
        $display("IDX | VALID | TASK_ID | QUOTA | DISP_CNT | FINISHED_CNT | STATE");
        for (int i = 0; i < 16; i++) begin
            if (uut.inst_tmt.trf_valid[i]) begin
                $display("%3d |   1   |   %4d  |  %4d |    %4d  |      %4d    |   %2b", 
                    i, uut.inst_tmt.trf_task_id[i], uut.inst_tmt.trf_quota[i],
                    uut.inst_tmt.trf_dispatched_count[i], uut.inst_tmt.trf_finished_count[i],
                    uut.inst_tmt.trf_fsm_state[i]);
            end
        end
        $display("=====================================================================\n");
    endtask

    // -------------------------------------------------------------------------
    // Main Test Sequence
    // -------------------------------------------------------------------------
    initial begin
        rst_n = 0;
        cfg_en = 0;
        cfg_data = 0;
        core_done_vec = 0;

        #30; rst_n = 1; #30;

        // =====================================================================
        // TC1: Sequential Demo & Screenshots (Sanity)
        // =====================================================================
        $display("\n[TC1] Generating Data for Project Book Screenshots...");
        host_send_task(10'd500, 10'd5, 32'h1000_0000, 10'd0); 
        host_send_task(10'd501, 10'd2, 32'h2000_0000, 10'd500); 
        
        wait_for_cores(5); 
        #20;
        print_tmt_snapshot();

        finish_active_cores(64'h0000_0000_0000_001F); // Cores 0-4
        wait_for_cores(2); 

        finish_active_cores(64'hFFFF_FFFF_FFFF_FFFF); // Clear everything
        wait_for_cores(0);

        // =====================================================================
        // TC2: 64 Cores Saturation
        // =====================================================================
        $display("\n[TC2] System Stress Test - Saturating all 64 cores...");
        for (int i = 0; i < 8; i++) begin
            host_send_task(10'd10 + i, 10'd8, 32'hAAAA_0000 + i, 10'd0); 
        end

        wait_for_cores(64);
        #20;
        
        for (int b = 0; b < 4; b++) begin
            finish_active_cores(64'hFFFF << (b*16)); // Finish 16 at a time
            #200; 
        end
        wait_for_cores(0);

        // =====================================================================
        // TC3: FDIR (Fault Detection)
        // =====================================================================
        $display("\n[TC3] Injecting Fault: Idle core sending termination...");
        @(posedge clk);
        core_done_vec[63] = 1'b1; 
        #50;
        core_done_vec[63] = 1'b0;

        // =====================================================================
        // TC4: The Dependency Waterfall (A -> B -> C -> D)
        // =====================================================================
        $display("\n[TC4] Dependency Waterfall (A -> B -> C -> D)...");
        host_send_task(10'd800, 10'd2, 32'h8000_0000, 10'd0);   // A
        host_send_task(10'd801, 10'd3, 32'h8100_0000, 10'd800); // B depends on A
        host_send_task(10'd802, 10'd4, 32'h8200_0000, 10'd801); // C depends on B
        host_send_task(10'd803, 10'd5, 32'h8300_0000, 10'd802); // D depends on C

        // A is running (2 cores)
        wait_for_cores(2);
        finish_active_cores(64'h0000_0000_0000_0003); // Cores 0-1 finish
        
        // B should start (3 cores)
        wait_for_cores(3);
        finish_active_cores(64'h0000_0000_0000_001C); // Cores 2-4 finish
        
        // C should start (4 cores)
        wait_for_cores(4);
        finish_active_cores(64'h0000_0000_0000_01E0); // Cores 5-8 finish
        
        // D should start (5 cores)
        wait_for_cores(5);
        finish_active_cores(64'hFFFF_FFFF_FFFF_FFFF); // Clear everything
        wait_for_cores(0);

        // =====================================================================
        // TC5: TRF Overload & FIFO Backpressure
        // =====================================================================
        $display("\n[TC5] TRF Overload & FIFO Backpressure...");
        // 1 Blocker task that will occupy cores
        host_send_task(10'd900, 10'd2, 32'h9000_0000, 10'd0);
        
        // 15 Tasks that depend on 900 (This fills the remaining 15 TMT slots)
        for (int i = 1; i <= 15; i++) begin
            host_send_task(10'd900 + i, 10'd1, 32'h9100_0000, 10'd900);
        end
        
        // TRF is now FULL (16/16). The next tasks should wait in the FIFO!
        $display("[TC5] Injecting 5 more tasks. These should buffer in the FIFO...");
        for (int i = 16; i <= 20; i++) begin
            host_send_task(10'd900 + i, 10'd1, 32'h9200_0000, 10'd900);
        end

        @(posedge clk); #1;
        if (!uut.empty_wire) $display("[TC5] SUCCESS: FIFO is correctly holding backpressure data!");

        // Release the bottleneck (Task 900 finishes)
        $display("[TC5] Releasing bottleneck (Task 900 completes)...");
        finish_active_cores(64'h0000_0000_0000_0003); 
        
        // System should now rapidly allocate the dependent tasks, making room in TRF,
        // which will pull the remaining 5 tasks from the FIFO automatically.
        // We will let the random finisher handle draining them all.

        // =====================================================================
        // TC6: Constrained Random Chaos
        // =====================================================================
        $display("\n[TC6] Random Execution Chaos (Stress Testing Arbiter)...");
        
        fork
            // Thread 1: Inject random noise (Tasks with varying quotas)
            begin
                for (int i = 0; i < 30; i++) begin
                    // Random quota between 1 and 6, Random dependency 0 or previous
                    host_send_task(10'd2000 + i, ($urandom() % 6) + 1, 32'hDEAD_0000, (($urandom() % 2) == 0) ? 0 : (10'd2000 + i - 1));
                end
            end
            
            // Thread 2: Randomly finish cores over 10,000 clock cycles
            begin
                run_random_completions(10000);
            end
        join

        // Ensure everything is drained before exiting
        finish_active_cores(64'hFFFF_FFFF_FFFF_FFFF); 
        wait_for_cores(0);

        $display("\n=========================================================");
        $display("   TESTBENCH COMPLETED SUCCESSFULLY");
        $display("=========================================================\n");
        $finish;
    end

endmodule
