`timescale 1ns / 1ps

module tmt (
    input  wire        i_clk,
    input  wire        i_rst_n,

    // FIFO Interface (Ingress)
    input  wire [63:0] i_fifo_tmt_data,
    input  wire        i_empty,
    output wire        o_tmt_fifo_ack,

    // CMT Interface (Allocation Downstream)
    input  wire        i_ava_core_valid,
    input  wire [5:0]  i_ava_core_id,
    output reg         o_tmt_cmt_ack,
    output reg  [3:0]  o_tmt_idx_tmt_cmt,
    output reg  [9:0]  o_task_id_tmt_cmt,
    output reg  [9:0]  o_instance_id_tmt_cmt, 

    // CMT Interface (Termination Upstream)
    input  wire        i_task_done_pulse,
    input  wire [3:0]  i_terminated_tmt_idx,

    // CORES Interface (Dispatch)
    output reg  [31:0] o_dispatch_addr,
    output reg  [5:0]  o_dispatch_core_id,

    // Status / FDIR
    output reg  [1:0]  o_err
);

    // -------------------------------------------------------------------------
    // Internal TRF (Task Register File) - 16 Rows
    // -------------------------------------------------------------------------
    reg [15:0] trf_valid;                   
    reg [9:0]  trf_task_id          [0:15];
    reg [9:0]  trf_quota            [0:15];
    reg [31:0] trf_addr             [0:15];
    reg [9:0]  trf_dispatched_count [0:15]; 
    reg [9:0]  trf_finished_count   [0:15]; 

    // Dependency Matrix [row][col] -> Row 'i' depends on Col 'j'
    reg [15:0] dep_matrix [0:15];

    integer i, j;

    // -------------------------------------------------------------------------
    // Combinational Logic: Free Slot Manager (Optimized Parallel Encoder)
    // -------------------------------------------------------------------------
    wire [15:0] free_slots = ~trf_valid;
    wire        free_slot_valid_comb = |free_slots;
    reg  [3:0]  free_idx_comb;

    wire [3:0] group_free_valid;
    assign group_free_valid[0] = |free_slots[3:0];
    assign group_free_valid[1] = |free_slots[7:4];
    assign group_free_valid[2] = |free_slots[11:8];
    assign group_free_valid[3] = |free_slots[15:12];

    wire [1:0] free_group_enc = group_free_valid[0] ? 2'd0 :
                                group_free_valid[1] ? 2'd1 :
                                group_free_valid[2] ? 2'd2 : 2'd3;

    reg [3:0] selected_free_group;
    always @(*) begin
        case (free_group_enc)
            2'd0: selected_free_group = free_slots[3:0];
            2'd1: selected_free_group = free_slots[7:4];
            2'd2: selected_free_group = free_slots[11:8];
            2'd3: selected_free_group = free_slots[15:12];
        endcase
    end

    wire [1:0] free_within_group_enc = selected_free_group[0] ? 2'd0 :
                                       selected_free_group[1] ? 2'd1 :
                                       selected_free_group[2] ? 2'd2 : 2'd3;

    always @(*) begin
        free_idx_comb = {free_group_enc, free_within_group_enc};
    end

    assign o_tmt_fifo_ack = (!i_empty && free_slot_valid_comb);

    // -------------------------------------------------------------------------
    // Combinational Logic: Dependency Comparators (Ingress)
    // -------------------------------------------------------------------------
    wire [9:0]  incoming_task_id = i_fifo_tmt_data[63:54];
    wire [9:0]  incoming_quota   = i_fifo_tmt_data[53:44];
    wire [31:0] incoming_addr    = i_fifo_tmt_data[43:12];
    wire [9:0]  incoming_dep_id  = i_fifo_tmt_data[11:2];
    
    wire [15:0] incoming_dep_match;
    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : gen_match
            assign incoming_dep_match[g] = (incoming_dep_id == 10'd0) ? 1'b0 : 
                                           (trf_valid[g] && (trf_task_id[g] == incoming_dep_id));
        end
    endgenerate

    // -------------------------------------------------------------------------
    // FSM State Definitions 
    // -------------------------------------------------------------------------
    localparam STATE_PENDING    = 2'b00;
    localparam STATE_READY      = 2'b01;
    localparam STATE_ALLOCATED  = 2'b10;
    localparam STATE_TERMINATED = 2'b11; 

    wire [1:0] trf_fsm_state [0:15];

    // -------------------------------------------------------------------------
    // Combinational FSM State Management
    // -------------------------------------------------------------------------
    generate
        for (g = 0; g < 16; g = g + 1) begin : gen_state
            assign trf_fsm_state[g] = 
                (!trf_valid[g])                                       ? STATE_PENDING :
                (trf_finished_count[g] == trf_quota[g])               ? STATE_TERMINATED :
                (trf_dispatched_count[g] == trf_quota[g])             ? STATE_ALLOCATED :
                (dep_matrix[g] == 16'd0)                              ? STATE_READY : 
                                                                        STATE_PENDING;
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Combinational Logic: Ready Arbiter (Optimized Parallel Encoder)
    // -------------------------------------------------------------------------
    wire [15:0] ready_slots;
    generate
        for (g = 0; g < 16; g = g + 1) begin : gen_ready
            assign ready_slots[g] = (trf_fsm_state[g] == STATE_READY);
        end
    endgenerate

    wire        ready_valid_comb = |ready_slots;
    reg  [3:0]  ready_idx_comb;

    wire [3:0] group_ready_valid;
    assign group_ready_valid[0] = |ready_slots[3:0];
    assign group_ready_valid[1] = |ready_slots[7:4];
    assign group_ready_valid[2] = |ready_slots[11:8];
    assign group_ready_valid[3] = |ready_slots[15:12];

    wire [1:0] ready_group_enc = group_ready_valid[0] ? 2'd0 :
                                 group_ready_valid[1] ? 2'd1 :
                                 group_ready_valid[2] ? 2'd2 : 2'd3;

    reg [3:0] selected_ready_group;
    always @(*) begin
        case (ready_group_enc)
            2'd0: selected_ready_group = ready_slots[3:0];
            2'd1: selected_ready_group = ready_slots[7:4];
            2'd2: selected_ready_group = ready_slots[11:8];
            2'd3: selected_ready_group = ready_slots[15:12];
        endcase
    end

    wire [1:0] ready_within_group_enc = selected_ready_group[0] ? 2'd0 :
                                        selected_ready_group[1] ? 2'd1 :
                                        selected_ready_group[2] ? 2'd2 : 2'd3;

    always @(*) begin
        ready_idx_comb = {ready_group_enc, ready_within_group_enc};
    end

    // -------------------------------------------------------------------------
    // Sequential Logic: FSM and Register Updates
    // -------------------------------------------------------------------------
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            trf_valid             <= 16'd0;
            o_tmt_cmt_ack         <= 1'b0;
            o_tmt_idx_tmt_cmt     <= 4'd0;
            o_task_id_tmt_cmt     <= 10'd0;
            o_instance_id_tmt_cmt <= 10'd0;
            o_dispatch_addr       <= 32'd0;
            o_dispatch_core_id    <= 6'd0;
            o_err                 <= 2'b00;
            for (i = 0; i < 16; i = i + 1) begin
                trf_task_id[i]          <= 10'd0;
                trf_quota[i]            <= 10'd0;
                trf_addr[i]             <= 32'd0;
                trf_dispatched_count[i] <= 10'd0;
                trf_finished_count[i]   <= 10'd0; 
                dep_matrix[i]           <= 16'd0;
            end
        end else begin
            o_tmt_cmt_ack <= 1'b0;
            o_err         <= 2'b00;

            // 1. Process FIFO Ingress
            if (o_tmt_fifo_ack) begin
                trf_valid[free_idx_comb]            <= 1'b1;
                trf_task_id[free_idx_comb]          <= incoming_task_id;
                trf_quota[free_idx_comb]            <= incoming_quota;
                trf_addr[free_idx_comb]             <= incoming_addr;
                trf_dispatched_count[free_idx_comb] <= 10'd0;
                trf_finished_count[free_idx_comb]   <= 10'd0; 
                dep_matrix[free_idx_comb]           <= incoming_dep_match;
            end

            // 2. Process Allocation 
            if (i_ava_core_valid && ready_valid_comb) begin
                o_tmt_cmt_ack         <= 1'b1;
                o_tmt_idx_tmt_cmt     <= ready_idx_comb;
                o_task_id_tmt_cmt     <= trf_task_id[ready_idx_comb];
                o_instance_id_tmt_cmt <= trf_dispatched_count[ready_idx_comb]; 
                o_dispatch_addr       <= trf_addr[ready_idx_comb];
                o_dispatch_core_id    <= i_ava_core_id;

                trf_dispatched_count[ready_idx_comb] <= trf_dispatched_count[ready_idx_comb] + 1'b1;
            end

            // 3. Process Termination 
            if (i_task_done_pulse && trf_valid[i_terminated_tmt_idx]) begin
                
                trf_finished_count[i_terminated_tmt_idx] <= trf_finished_count[i_terminated_tmt_idx] + 1'b1;

                if (trf_finished_count[i_terminated_tmt_idx] + 1'b1 == trf_quota[i_terminated_tmt_idx]) begin
                    trf_valid[i_terminated_tmt_idx] <= 1'b0; 
                    
                    for (j = 0; j < 16; j = j + 1) begin
                        dep_matrix[j][i_terminated_tmt_idx] <= 1'b0;
                    end
                end
            end
            
            // FDIR: Dependency Deadlock Detection
            if (trf_valid == 16'hFFFF && !ready_valid_comb) begin
                o_err <= 2'b01; 
            end
        end
    end

endmodule
