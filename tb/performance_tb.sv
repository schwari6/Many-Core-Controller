`timescale 1ns / 1ps
`include "../src/controller.v"

module performance_tb();

    // -------------------------------------------------------------------------
    // Parameters and Signals
    // -------------------------------------------------------------------------
    parameter FIFO_DEPTH = 128;
    parameter FIFO_WIDTH = 64;

    logic                    clk;
    logic                    rst_n;

    logic                    cfg_en;
    logic [FIFO_WIDTH-1:0]   cfg_data;
    logic                    full;

    logic [31:0]             dispatch_addr;
    logic [5:0]              dispatch_core_id;

    logic [63:0]             core_done_vec;
    logic [5:0]              core_id_cmt_core;
    logic                    done_ack;
    logic [3:0]              err_bus;

    integer                  log_file;

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

    initial begin
        log_file = $fopen("../reports/sim_log.txt", "w");
        if (!log_file) log_file = $fopen("sim_log.txt", "w");
        clk = 0;
        forever #1.666 clk = ~clk; // ~300MHz
    end

    initial begin
        #5000000;
        $display("\n\033[0;31m[FATAL] Simulation Timeout!\033[0m");
        if (log_file) $fclose(log_file);
        $finish;
    end

    // Telemetry
    always @(posedge clk) begin
        if (rst_n && log_file) begin
            $fdisplay(log_file, "LOG_SYS,%0t,%0d,%b", $time, $countones(uut.inst_cmt.core_busy), full);
            $fdisplay(log_file, "CSV_LOG,%0t,%0d", $time, $countones(uut.inst_cmt.core_busy));
            if (uut.tmt_cmt_ack_wire) begin
                $fdisplay(log_file, "LOG_ALLOC,%0t,%0d,%0d", $time, uut.task_id_tmt_cmt_wire, uut.ava_core_id_wire);
            end
            if (done_ack) begin
                $fdisplay(log_file, "LOG_FREE,%0t,%0d,%0d", $time, uut.inst_cmt.core_task_id[core_id_cmt_core], core_id_cmt_core);
            end
        end
    end

    always @(negedge clk) begin
        if (rst_n && done_ack) core_done_vec[core_id_cmt_core] = 1'b0;
    end

    // Core Execution Engine (Slower to simulate heavy DSP math -> forces 64 core saturation)
    always @(posedge clk) begin
        if (rst_n) begin
            for (int i = 0; i < 64; i++) begin
                if (uut.inst_cmt.core_busy[i] == 1'b1 && core_done_vec[i] == 1'b0) begin
                    // 0.5% chance -> ~200 cycles average execution time
                    if (($urandom() % 1000) < 5) begin
                        core_done_vec[i] <= 1'b1;
                    end
                end
            end
        end
    end

    // Host Injection Thread
    initial begin
        logic [9:0] t_id;
        logic [9:0] t_quota;
        logic [9:0] t_dep;
        
        rst_n = 0; cfg_en = 0; cfg_data = 0; core_done_vec = 0;
        #30; rst_n = 1; #30;

        $display("STARTING HIGH-PERFORMANCE BENCHMARK (500 TASKS)");

        for (int i = 1; i <= 500; i++) begin
            t_id = i;
            t_quota = ($urandom() % 8) + 1;
            t_dep = (i > 1 && ($urandom() % 100) < 20) ? i - 1 : 0;

            // Wait if FIFO is full
            if (full) @(negedge full);
            
            @(posedge clk);
            if (log_file) $fdisplay(log_file, "LOG_HOST,%0t,%0d,%0d,%0d", $time, t_id, t_quota, t_dep);
            cfg_data = {t_id, t_quota, 32'hA000_0000 + t_id, t_dep, 2'b00};
            cfg_en = 1;
            
            @(posedge clk);
            cfg_en = 0;
            cfg_data = 0;

            // Paced Injection: prevents massive red lines in Gantt by simulating host processing time
            repeat (($urandom() % 20) + 5) @(posedge clk);
        end

        wait (uut.empty_wire == 1'b1 && $countones(uut.inst_cmt.core_busy) == 0);
        #100; 
        
        if (log_file) begin
            $fclose(log_file);
            $display("High-Performance Telemetry data saved to sim_log.txt");
        end
        $finish;
    end
endmodule