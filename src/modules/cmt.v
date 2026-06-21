`timescale 1ns / 1ps

module cmt (
    input  wire        i_clk,
    input  wire        i_rst_n,

    // Interface with TMT (Allocation)
    output wire        o_ava_core_valid,
    output wire [5:0]  o_ava_core_id,
    input  wire [9:0]  i_task_id_tmt_cmt,
    input  wire [3:0]  i_tmt_idx_tmt_cmt,      // 4-bit TMT row index
    input  wire [9:0]  i_instance_num_tmt_cmt,
    input  wire        i_tmt_cmt_ack,          // TMT confirms allocation

    // Interface with TMT (Termination)
    output reg         o_task_done_pulse,
    output reg  [3:0]  o_terminated_tmt_idx,   // 4-bit TMT row index back to TMT
    
    // Interface with CORES
    input  wire [63:0] i_core_done_vec,
    output reg  [5:0]  o_core_id_cmt_core,
    output reg         o_done_ack,

    // Status / FDIR
    output reg  [1:0]  o_err
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
    reg        idle_valid_comb;
    reg [5:0]  idle_core_id_comb;
    
    // Step 1: Find the first bit set to 1 (lowest non-busy index) using masking
    wire [63:0] core_idle = ~core_busy;
    wire [63:0] lowest_idle_bit;
    
    // Classic hardware trick: isolates the Least Significant Bit (LSB) that equals 1
    assign lowest_idle_bit = core_idle & (~core_idle + 1'b1);

    // Step 2: Encode the obtained One-Hot bit vector into a 6-bit binary value
    always @(*) begin
        idle_valid_comb   = |core_idle; // Valid if at least one core is idle
        idle_core_id_comb = 6'd0;
        
        // Parallel logic tree (OR-Tree) for position encoding
        idle_core_id_comb[0] = |(lowest_idle_bit & 64'hAAAAAAAAAAAAAAAA);
        idle_core_id_comb[1] = |(lowest_idle_bit & 64'hCCCCCCCCCCCCCCCC);
        idle_core_id_comb[2] = |(lowest_idle_bit & 64'hF0F0F0F0F0F0F0F0);
        idle_core_id_comb[3] = |(lowest_idle_bit & 64'hFF00FF00FF00FF00);
        idle_core_id_comb[4] = |(lowest_idle_bit & 64'hFFFF0000FFFF0000);
        idle_core_id_comb[5] = |(lowest_idle_bit & 64'hFFFFFFFF00000000);
    end

    assign o_ava_core_valid = idle_valid_comb;
    assign o_ava_core_id    = idle_core_id_comb;

    // -------------------------------------------------------------------------
    // Combinational Logic: Priority Encoder for Terminated Core (Arbitration)
    // -------------------------------------------------------------------------
    reg        term_valid_comb;
    reg [5:0]  term_core_id_comb;

    // Step 1: Isolate the LSB that equals 1 (lowest index that has finished)
    wire [63:0] lowest_done_bit;
    
    // Classic hardware trick: leaves only the rightmost 1 active and clears the rest
    assign lowest_done_bit = i_core_done_vec & (~i_core_done_vec + 1'b1);

    // Step 2: Encode the One-Hot bit vector into a 6-bit binary value
    always @(*) begin
        term_valid_comb   = |i_core_done_vec; // Valid if at least one core has finished
        term_core_id_comb = 6'd0;
        
        // Parallel logic tree (OR-Tree) for position encoding in O(log N)
        term_core_id_comb[0] = |(lowest_done_bit & 64'hAAAAAAAAAAAAAAAA);
        term_core_id_comb[1] = |(lowest_done_bit & 64'hCCCCCCCCCCCCCCCC);
        term_core_id_comb[2] = |(lowest_done_bit & 64'hF0F0F0F0F0F0F0F0);
        term_core_id_comb[3] = |(lowest_done_bit & 64'hFF00FF00FF00FF00);
        term_core_id_comb[4] = |(lowest_done_bit & 64'hFFFF0000FFFF0000);
        term_core_id_comb[5] = |(lowest_done_bit & 64'hFFFFFFFF00000000);
    end

    // -------------------------------------------------------------------------
    // Sequential Logic: State Updates
    // -------------------------------------------------------------------------
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            core_busy            <= 64'd0;
            o_task_done_pulse    <= 1'b0;
            o_terminated_tmt_idx <= 4'd0;
            o_done_ack           <= 1'b0;
            o_core_id_cmt_core   <= 6'd0;
            o_err                <= 2'b00;
            for (k = 0; k < 64; k = k + 1) begin
                core_tmt_idx[k]         <= 4'd0;
                core_task_id[k]         <= 10'd0;
                core_instance_number[k] <= 10'd0;
            end
        end else begin
            // Default pulse values (single cycle pulses)
            o_task_done_pulse <= 1'b0;
            o_done_ack        <= 1'b0;
            o_err             <= 2'b00;

            // 1. Process Allocation (TMT -> CMT)
            if (i_tmt_cmt_ack && o_ava_core_valid) begin
                core_busy[o_ava_core_id]            <= 1'b1;
                core_tmt_idx[o_ava_core_id]         <= i_tmt_idx_tmt_cmt;
                core_task_id[o_ava_core_id]         <= i_task_id_tmt_cmt; // FIXED: Changed from o_ava_core_valid to o_ava_core_id
                core_instance_number[o_ava_core_id] <= i_instance_num_tmt_cmt;
            end

            // 2. Process Termination Arbitration (CORES -> CMT)
            if (term_valid_comb) begin
                o_task_done_pulse    <= 1'b1;
                o_terminated_tmt_idx <= core_tmt_idx[term_core_id_comb];
                o_done_ack           <= 1'b1;
                o_core_id_cmt_core   <= term_core_id_comb;

                // Free the core
                core_busy[term_core_id_comb] <= 1'b0;

                // o_error Injection / Detection: Core terminated but wasn't busy
                if (!core_busy[term_core_id_comb]) begin
                    o_err <= 2'b10; // Code 10: Invalid Termination ID
                end
            end
        end
    end

endmodule
