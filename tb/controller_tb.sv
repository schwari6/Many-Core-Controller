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
    // System Telemetry & Event Monitors (For Python Analytics)
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            // 1. System State Monitoring (Every Clock)
            // LOG_SYS, Time, ActiveCores, FIFO_Full
            $display("LOG_SYS,%0t,%0d,%b", $time, $countones(uut.inst_cmt.core_busy), full);
            
            // 2. Allocation Monitoring (When a core is granted by TMT)
            if (uut.tmt_cmt_ack_wire) begin
                $display("LOG_ALLOC,%0t,%0d,%0d", $time, uut.task_id_tmt_cmt_wire, uut.ava_core_id_wire);
            end
            
            // 3. Termination Monitoring (When a core is freed by CMT)
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
            $display("[WARN] FIFO Full. Waiting...");
            @(negedge full);
        end
        @(posedge clk);
        
        // Log the injection of the task
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

        // TC1: Sequential Demo & Screenshots
        $display("[TC1] Generating Data for Project Book Screenshots...");
        host_send_task(10'd500, 10'd5, 32'h1000_0000, 10'd0); // Independent
        host_send_task(10'd501, 10'd2, 32'h2000_0000, 10'd500); // Depends on 500
        
        wait_for_cores(5); 
        #20;
        print_tmt_snapshot();

        @(posedge clk);
        core_done_vec[4:0] = 5'h1F; // Cores 0-4 finish
        wait_for_cores(2); 
        print_tmt_snapshot();

        @(posedge clk);
        core_done_vec[64:0] = ~64'd0; 
        wait_for_cores(0);

        // TC2: 64 Cores Saturation
        $display("\n[TC2] System Stress Test - Saturating all 64 cores...");
        for (int i = 0; i < 8; i++) begin
            host_send_task(10'd10 + i, 10'd8, 32'hAAAA_0000 + i, 10'd0); 
        end

        wait_for_cores(64);
        #20;
        print_tmt_snapshot();
        
        for (int b = 0; b < 4; b++) begin
            @(posedge clk);
            core_done_vec[(b*16) +: 16] = 16'hFFFF;
            #200; 
        end
        wait_for_cores(0);

        // TC3: FDIR (Fault Detection)
        $display("\n[TC3] Injecting Fault: Idle core sending termination...");
        @(posedge clk);
        core_done_vec[63] = 1'b1; 
        #50;
        core_done_vec[63] = 1'b0;

        $display("\n=========================================================");
        $display("   TESTBENCH COMPLETED SUCCESSFULLY");
        $display("=========================================================\n");
        $finish;
    end

endmodule
