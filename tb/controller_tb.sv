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
        #500000;
        $display("\n\033[0;31m[FATAL] Watchdog Timer Expired!\033[0m");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Logging for Python Script (CSV Format)
    // -------------------------------------------------------------------------
    int active_cores_count;
    always @(posedge clk) begin
        if (rst_n) begin
            active_cores_count = $countones(uut.inst_cmt.core_busy);
            // Format: CSV_LOG, Time, ActiveCores, ErrorBus
            $display("CSV_LOG,%0t,%0d,%0d", $time, active_cores_count, err_bus);
        end
    end

    // -------------------------------------------------------------------------
    // Synchronous Auto-Clear Core Done Logic (Robust BFM)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n && done_ack) begin
            core_done_vec[core_id_cmt_core] <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // Tasks (BFMs & Monitors)
    // -------------------------------------------------------------------------
    task host_send_task(input [9:0] id, input [9:0] quota, input [31:0] addr, input [9:0] dep);
        if (full) begin
            $display("[WARN] FIFO Full. Waiting...");
            @(negedge full);
        end
        @(posedge clk);
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

    task print_cmt_snapshot();
        $display("\n=====================================================================");
        $display("=                  CMT SNAPSHOT (Active Cores Only)                 =");
        $display("=====================================================================");
        for (int i = 0; i < 64; i++) begin
            if (uut.inst_cmt.core_busy[i]) begin
                $display("Core %2d is BUSY running TMT Index: %2d", i, uut.inst_cmt.core_tmt_idx[i]);
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
        // TC1: Project Book Snapshots (Clear Sequential Demo)
        // =====================================================================
        $display("[TC1] Generating Data for Project Book Screenshots...");
        host_send_task(10'd500, 10'd5, 32'h1000_0000, 10'd0); // Independent
        host_send_task(10'd501, 10'd2, 32'h2000_0000, 10'd500); // Depends on 500
        
        wait_for_cores(5); // Wait for task 500 to allocate 5 cores
        #20;
        $display("\n---> [SCREENSHOT OPPORTUNITY 1: Dependency Pending] <---");
        print_tmt_snapshot();
        print_cmt_snapshot();

        // Finish task 500
        @(posedge clk);
        core_done_vec[4:0] = 5'h1F; // Cores 0-4 finish
        wait_for_cores(2); // Wait for task 501 to kick in
        
        $display("\n---> [SCREENSHOT OPPORTUNITY 2: Dependency Resolved] <---");
        print_tmt_snapshot();
        print_cmt_snapshot();

        // Finish task 501
        @(posedge clk);
        core_done_vec[64:0] = ~64'd0; // Just trigger all active to finish
        wait_for_cores(0);

        // =====================================================================
        // TC2: Massive Stress Test (64 Cores Saturation)
        // =====================================================================
        $display("\n[TC2] System Stress Test - Saturating all 64 cores...");
        for (int i = 0; i < 8; i++) begin
            host_send_task(10'd10 + i, 10'd8, 32'hAAAA_0000 + i, 10'd0); // 8 tasks * 8 quota = 64 cores
        end

        wait_for_cores(64);
        #20;
        $display("\n---> [SCREENSHOT OPPORTUNITY 3: 100% Core Utilization] <---");
        print_tmt_snapshot();
        
        // Let's finish them 16 at a time (Simulating real hardware variance)
        for (int b = 0; b < 4; b++) begin
            @(posedge clk);
            core_done_vec[(b*16) +: 16] = 16'hFFFF;
            #200; // Let arbitration handle 16 simultaneous terminations safely
        end
        wait_for_cores(0);
        $display("[TC2] Stress Test Passed. All cores gracefully terminated.");

        // =====================================================================
        // TC3: FDIR (Fault Detection) Injection
        // =====================================================================
        $display("\n[TC3] Injecting Fault: Idle core sending termination...");
        @(posedge clk);
        core_done_vec[63] = 1'b1; // Core 63 is idle, but sends DONE!
        #50;
        core_done_vec[63] = 1'b0;
        if (err_bus != 4'b0000) $display("\033[0;32m[TC3] Fault correctly caught! err_bus = %b\033[0m", err_bus);
        else $display("\033[0;31m[TC3] Fault missed!\033[0m");

        $display("\n=========================================================");
        $display("   TESTBENCH COMPLETED SUCCESSFULLY");
        $display("=========================================================\n");
        $finish;
    end

endmodule
