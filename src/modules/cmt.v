`timescale 1ns / 1ps

module cmt (
    input  wire        clk,
    input  wire        rst_n,

    // Interface with TMT (Allocation)
    output wire        ava_core_valid,
    output wire [5:0]  ava_core_id,
    input  wire [9:0]  task_id_tmt_cmt,
    input  wire [3:0]  tmt_idx_tmt_cmt,      // 4-bit TMT row index
    input  wire [9:0]  instance_num_tmt_cmt,
    input  wire        tmt_cmt_ack,          // TMT confirms allocation

    // Interface with TMT (Termination)
    output reg         task_done_pulse,
    output reg  [3:0]  terminated_tmt_idx,   // 4-bit TMT row index back to TMT
    
    // Interface with CORES
    input  wire [63:0] core_done_vec,
    output reg  [5:0]  core_id_cmt_core,
    output reg         done_ack,

    // Status / FDIR
    output reg  [1:0]  err
);

    // -------------------------------------------------------------------------
    // Internal Registers
    // -------------------------------------------------------------------------
    reg [63:0] core_busy;
    reg [3:0]  core_tmt_idx        [0:63]; // Stores the 4-bit TMT index for each core
    reg [9:0]  core_task_id        [0:63];
    reg [9:0]  core_instance_number[0:63];

    integer k;

    // -------------------------------------------------------------------------
    // Combinational Logic: Priority Encoder for Idle Core (Allocation)
    // -------------------------------------------------------------------------
    reg       idle_valid_comb;
    reg [5:0] idle_core_id_comb;
    integer   i;

    always @(*) begin
        idle_valid_comb = 1'b0;
        idle_core_id_comb = 6'd0;
        // Search from 63 down to 0, so the lowest available index wins
        for (i = 63; i >= 0; i = i - 1) begin
            if (~core_busy[i]) begin
                idle_valid_comb = 1'b1;
                idle_core_id_comb = i[5:0];
            end
        end
    end

    assign ava_core_valid = idle_valid_comb;
    assign ava_core_id    = idle_core_id_comb;

    // -------------------------------------------------------------------------
    // Combinational Logic: Priority Encoder for Terminated Core (Arbitration)
    // -------------------------------------------------------------------------
    reg       term_valid_comb;
    reg [5:0] term_core_id_comb;
    integer   j;

    always @(*) begin
        term_valid_comb = 1'b0;
        term_core_id_comb = 6'd0;
        // Search from 63 down to 0, so the lowest terminating core wins arbitration
        for (j = 63; j >= 0; j = j - 1) begin
            if (core_done_vec[j]) begin
                term_valid_comb = 1'b1;
                term_core_id_comb = j[5:0];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Sequential Logic: State Updates
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            core_busy          <= 64'd0;
            task_done_pulse    <= 1'b0;
            terminated_tmt_idx <= 4'd0;
            done_ack           <= 1'b0;
            core_id_cmt_core   <= 6'd0;
            err                <= 2'b00;
            for (k = 0; k < 64; k = k + 1) begin
                core_tmt_idx[k]         <= 4'd0;
                core_task_id[k]         <= 10'd0;
                core_instance_number[k] <= 10'd0;
            end
        end else begin
            // Default pulse values (single cycle pulses)
            task_done_pulse <= 1'b0;
            done_ack        <= 1'b0;
            err             <= 2'b00;

            // 1. Process Allocation (TMT -> CMT)
            if (tmt_cmt_ack && ava_core_valid) begin
                core_busy[ava_core_id]            <= 1'b1;
                core_tmt_idx[ava_core_id]         <= tmt_idx_tmt_cmt;
                core_task_id[ava_core_id]         <= task_id_tmt_cmt; // FIXED: Changed from ava_core_valid to ava_core_id
                core_instance_number[ava_core_id] <= instance_num_tmt_cmt;
            end

            // 2. Process Termination Arbitration (CORES -> CMT)
            if (term_valid_comb) begin
                task_done_pulse    <= 1'b1;
                terminated_tmt_idx <= core_tmt_idx[term_core_id_comb];
                done_ack           <= 1'b1;
                core_id_cmt_core   <= term_core_id_comb;

                // Free the core
                core_busy[term_core_id_comb] <= 1'b0;
                
                // Clear tracking registers for completed core to keep snapshots clean
                core_tmt_idx[term_core_id_comb]         <= 4'd0;
                core_task_id[term_core_id_comb]         <= 10'd0;
                core_instance_number[term_core_id_comb] <= 10'd0;

                // Error Injection / Detection: Core terminated but wasn't busy
                if (!core_busy[term_core_id_comb]) begin
                    err <= 2'b10; // Code 10: Invalid Termination ID
                end
            end
        end
    end

endmodule