`timescale 1ns / 1ps
`include "../src/controller.v"

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
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_cfg_en(cfg_en),
        .i_cfg_data(cfg_data),
        .o_full(full),
        .o_dispatch_addr(dispatch_addr),
        .o_dispatch_core_id(dispatch_core_id),
        .i_core_done_vec(core_done_vec),
        .o_core_id_cmt_core(core_id_cmt_core),
        .o_done_ack(done_ack),
        .o_err_bus(err_bus)
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
    // Synchronous Auto-Clear Core Done Logic
    // -------------------------------------------------------------------------
    always @(negedge clk) begin
        if (rst_n && done_ack) begin
            core_done_vec[core_id_cmt_core] = 1'b0;
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
        core_done_vec |= (mask & uut.inst_cmt.core_busy);
    endtask

    // Random finisher: mimics real-world unpredictable core completion times
    task run_random_completions(input int cycles);
        int active_count;
        repeat(cycles) begin
            @(posedge clk);
            for (int i = 0; i < 64; i++) begin
                if (uut.inst_cmt.core_busy[i] == 1'b1 && core_done_vec[i] == 1'b0) begin
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

        finish_active_cores(64'h0000_0000_0000_001F);
        
        #100; // Allow 5 cores to fully drain
        wait_for_cores(2); 

        finish_active_cores(64'hFFFF_FFFF_FFFF_FFFF);
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
            finish_active_cores(64'hFFFF << (b*16));
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

        wait_for_cores(2);
        // A uses Cores 0,1. Mask is 0x03
        finish_active_cores(64'h0000_0000_0000_0003); 
        
        wait_for_cores(3);
        // B uses Cores 0,1,2 (since 0,1 were just freed!). Mask is 0x07
        finish_active_cores(64'h0000_0000_0000_0007); 
        
        wait_for_cores(4);
        // C uses Cores 0,1,2,3. Mask is 0x0F
        finish_active_cores(64'h0000_0000_0000_000F); 
        
        wait_for_cores(5);
        // Clear everything using FFFF
        finish_active_cores(64'hFFFF_FFFF_FFFF_FFFF); 
        wait_for_cores(0);

        // =====================================================================
        // TC5: TRF Overload & FIFO Backpressure
        // =====================================================================
        $display("\n[TC5] TRF Overload & FIFO Backpressure...");
        host_send_task(10'd900, 10'd2, 32'h9000_0000, 10'd0);
        
        for (int i = 1; i <= 15; i++) begin
            host_send_task(10'd900 + i, 10'd1, 32'h9100_0000, 10'd900);
        end
        
        $display("[TC5] Injecting 5 more tasks. These should buffer in the FIFO...");
        for (int i = 16; i <= 20; i++) begin
            host_send_task(10'd900 + i, 10'd1, 32'h9200_0000, 10'd900);
        end

        @(posedge clk); #1;
        if (!uut.empty_wire) $display("[TC5] SUCCESS: FIFO is correctly holding backpressure data!");

        $display("[TC5] Releasing bottleneck (Task 900 completes)...");
        // Task 900 uses Cores 0 and 1
        finish_active_cores(64'h0000_0000_0000_0003); 
        
        // =====================================================================
        // TC6: Constrained Random Chaos
        // =====================================================================
        $display("\n[TC6] Random Execution Chaos (Stress Testing Arbiter)...");
        fork
            begin
                for (int i = 0; i < 30; i++) begin
                    host_send_task(10'd200 + i, ($urandom() % 6) + 1, 32'hDEAD_0000, (($urandom() % 2) == 0) ? 0 : (10'd200 + i - 1));
                end
            end
            begin
                run_random_completions(10000);
            end
        join

        finish_active_cores(64'hFFFF_FFFF_FFFF_FFFF);
        wait_for_cores(0);

        // =====================================================================
        // TC7: Ghost Dependency (Already Resolved Task)
        // =====================================================================
        $display("\n[TC7] Ghost Dependency (Task depends on a task that already finished)...");
        host_send_task(10'd300, 10'd2, 32'hBEEF_0000, 10'd0);
        wait_for_cores(2);
        finish_active_cores(64'hFFFF_FFFF_FFFF_FFFF);
        wait_for_cores(0);
        
        repeat(10) @(posedge clk);

        $display("[TC7] Injecting Task 301 depending on Task 300 (which is gone).");
        host_send_task(10'd301, 10'd4, 32'hBEEF_0001, 10'd300);
        
        wait_for_cores(4);
        $display("[TC7] SUCCESS: Task 301 correctly ignored the ghost dependency and started!");
        
        finish_active_cores(64'hFFFF_FFFF_FFFF_FFFF);
        wait_for_cores(0);

        // =====================================================================
        // TC8: Warm Reset Mid-Operation
        // =====================================================================
        $display("\n[TC8] Warm Reset Test: Yanking the reset line during heavy load...");
        host_send_task(10'd400, 10'd30, 32'hC000_0000, 10'd0);
        wait_for_cores(30);
        
        @(posedge clk);
        $display("[TC8] ASSERTING RESET!");
        rst_n = 0;
        core_done_vec = 0; 
        
        repeat(5) @(posedge clk);
        rst_n = 1; 
        $display("[TC8] RESET RELEASED.");

        repeat(5) @(posedge clk);
        if ($countones(uut.inst_cmt.core_busy) == 0 && uut.empty_wire == 1'b1) begin
            $display("[TC8] SUCCESS: System is totally idle and recovered from Warm Reset.");
        end else begin
            $display("[TC8] FAIL: System did not clear properly after reset!");
        end

        host_send_task(10'd401, 10'd5, 32'hC000_0001, 10'd0);
        wait_for_cores(5);
        $display("[TC8] SUCCESS: System successfully processed a new task post-reset.");
        
        finish_active_cores(64'hFFFF_FFFF_FFFF_FFFF);
        wait_for_cores(0);

        // =====================================================================
        // TC9: Circular Dependency Deadlock (Software Bug Injection)
        // =====================================================================
        $display("\n[TC9] Circular Deadlock Injection (FDIR Check)...");
        for (int i = 0; i < 16; i++) begin
            host_send_task(10'd600 + i, 10'd1, 32'hDEAD_DEAD, 10'd600 + ((i + 1) % 16)); 
        end
        
        repeat(20) @(posedge clk);
        
        if (err_bus[3:2] == 2'b01) begin
            $display("\033[0;32m[TC9] SUCCESS: TMT FDIR correctly detected the Circular Deadlock! (err_bus = %b)\033[0m", err_bus);
        end else begin
            $display("\033[0;31m[TC9] FAIL: TMT did not flag the deadlock! (err_bus = %b)\033[0m", err_bus);
        end
        
        $display("\n=========================================================");
        $display("   TESTBENCH COMPLETED SUCCESSFULLY");
        $display("=========================================================\n");
        $finish;
    end

endmodule