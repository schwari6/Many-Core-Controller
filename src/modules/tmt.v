`timescale 1ns / 1ps

module tmt (
    input  wire        clk,
    input  wire        rst_n,

    // FIFO Interface (Ingress)
    input  wire [63:0] fifo_tmt_data,
    input  wire        empty,
    output wire        tmt_fifo_ack,

    // CMT Interface (Allocation Downstream)
    input  wire        ava_core_valid,
    input  wire [5:0]  ava_core_id,
    output reg         tmt_cmt_ack,
    output reg  [3:0]  tmt_idx_tmt_cmt,
    output reg  [9:0]  task_id_tmt_cmt,
    output reg  [9:0]  instance_id_tmt_cmt, // Added for instance tracking

    // CMT Interface (Termination Upstream)
    input  wire        task_done_pulse,
    input  wire [3:0]  terminated_tmt_idx,

    // CORES Interface (Dispatch)
    output reg  [31:0] dispatch_addr,
    output reg  [5:0]  dispatch_core_id,

    // Status / FDIR
    output reg  [1:0]  err
);

    // -------------------------------------------------------------------------
    // Internal TRF (Task Register File) - 16 Rows
    // -------------------------------------------------------------------------
    reg [15:0] trf_valid;                   //'0' if this slot is occupied
    reg [9:0]  trf_task_id      [0:15];
    reg [9:0]  trf_quota        [0:15];
    reg [31:0] trf_addr         [0:15];
    reg [9:0]  trf_dispatch_left[0:15];
    reg [9:0]  trf_done_left    [0:15];

    // Dependency Matrix [row][col] -> Row 'i' depends on Col 'j'
    reg [15:0] dep_matrix [0:15];

    integer i, j;

    // -------------------------------------------------------------------------
    // Combinational Logic: Free Slot Manager (Priority Encoder)
    // -------------------------------------------------------------------------
    wire [15:0] free_slots = ~trf_valid;
    wire        free_slot_valid = |free_slots;
    reg  [3:0]  free_idx;

    always @(*) begin
        free_idx = 4'd0;
        if      (free_slots[0])  free_idx = 4'd0;
        else if (free_slots[1])  free_idx = 4'd1;
        else if (free_slots[2])  free_idx = 4'd2;
        else if (free_slots[3])  free_idx = 4'd3;
        else if (free_slots[4])  free_idx = 4'd4;
        else if (free_slots[5])  free_idx = 4'd5;
        else if (free_slots[6])  free_idx = 4'd6;
        else if (free_slots[7])  free_idx = 4'd7;
        else if (free_slots[8])  free_idx = 4'd8;
        else if (free_slots[9])  free_idx = 4'd9;
        else if (free_slots[10]) free_idx = 4'd10;
        else if (free_slots[11]) free_idx = 4'd11;
        else if (free_slots[12]) free_idx = 4'd12;
        else if (free_slots[13]) free_idx = 4'd13;
        else if (free_slots[14]) free_idx = 4'd14;
        else if (free_slots[15]) free_idx = 4'd15;
    end

    // Acknowledge FIFO if there is data and a free slot
    assign tmt_fifo_ack = (!empty && free_slot_valid);

    // -------------------------------------------------------------------------
    // Combinational Logic: Dependency Comparators (Ingress)
    // ---------------------------------------------------------
    wire [9:0]  incoming_task_id = fifo_tmt_data[63:54];
    wire [9:0]  incoming_quota   = fifo_tmt_data[53:44];
    wire [31:0] incoming_addr    = fifo_tmt_data[43:12];
    wire [9:0]  incoming_dep_id  = fifo_tmt_data[11:2];
    
    wire [15:0] incoming_dep_match;
    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin : gen_match
            // If incoming_dep_id is 0, it means NO dependency. Bypass the comparator.
            assign incoming_dep_match[g] = (incoming_dep_id == 10'd0) ? 1'b0 : 
                                           (trf_valid[g] && (trf_task_id[g] == incoming_dep_id));
        end
    endgenerate

    // -------------------------------------------------------------------------
    // FSM State Definitions (As per MAS Section 3.1 & 7.2.5)
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
            // State is instantly derived from internal counters and matrix.
            // This guarantees zero-latency transitions without clock delays.
            assign trf_fsm_state[g] = 
                (!trf_valid[g])               ? STATE_PENDING :
                (trf_done_left[g] == 0)       ? STATE_TERMINATED :
                (trf_dispatch_left[g] == 0)   ? STATE_ALLOCATED :
                (dep_matrix[g] == 16'd0)      ? STATE_READY : 
                                                STATE_PENDING;
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Combinational Logic: Ready Arbiter (Allocation)
    // -------------------------------------------------------------------------
    wire [15:0] ready_slots;
    generate
        for (g = 0; g < 16; g = g + 1) begin : gen_ready
            // Now the Arbiter purely relies on the explicit FSM State!
            assign ready_slots[g] = (trf_fsm_state[g] == STATE_READY);
        end
    endgenerate

    wire       ready_valid = |ready_slots;
    reg  [3:0] ready_idx;

    always @(*) begin
        ready_idx = 4'd0;
        if      (ready_slots[0])  ready_idx = 4'd0;
        else if (ready_slots[1])  ready_idx = 4'd1;
        else if (ready_slots[2])  ready_idx = 4'd2;
        else if (ready_slots[3])  ready_idx = 4'd3;
        else if (ready_slots[4])  ready_idx = 4'd4;
        else if (ready_slots[5])  ready_idx = 4'd5;
        else if (ready_slots[6])  ready_idx = 4'd6;
        else if (ready_slots[7])  ready_idx = 4'd7;
        else if (ready_slots[8])  ready_idx = 4'd8;
        else if (ready_slots[9])  ready_idx = 4'd9;
        else if (ready_slots[10]) ready_idx = 4'd10;
        else if (ready_slots[11]) ready_idx = 4'd11;
        else if (ready_slots[12]) ready_idx = 4'd12;
        else if (ready_slots[13]) ready_idx = 4'd13;
        else if (ready_slots[14]) ready_idx = 4'd14;
        else if (ready_slots[15]) ready_idx = 4'd15;
    end

    // -------------------------------------------------------------------------
    // Sequential Logic: FSM and Register Updates
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trf_valid <= 16'd0;
            tmt_cmt_ack <= 1'b0;
            tmt_idx_tmt_cmt <= 4'd0;
            task_id_tmt_cmt <= 10'd0;
            instance_id_tmt_cmt <= 10'd0;
            dispatch_addr <= 32'd0;
            dispatch_core_id <= 6'd0;
            err <= 2'b00;
            for (i = 0; i < 16; i = i + 1) begin
                trf_task_id[i] <= 10'd0;
                trf_quota[i] <= 10'd0;
                trf_addr[i] <= 32'd0;
                trf_dispatch_left[i] <= 10'd0;
                trf_done_left[i] <= 10'd0;
                dep_matrix[i] <= 16'd0;
            end
        end else begin
            // Default pulse values
            tmt_cmt_ack <= 1'b0;
            err <= 2'b00;

            // 1. Process FIFO Ingress (Pop new task)
            if (tmt_fifo_ack) begin
                trf_valid[free_idx]         <= 1'b1;
                trf_task_id[free_idx]       <= incoming_task_id;
                trf_quota[free_idx]         <= incoming_quota;
                trf_addr[free_idx]          <= incoming_addr;
                trf_dispatch_left[free_idx] <= incoming_quota;
                trf_done_left[free_idx]     <= incoming_quota;
                dep_matrix[free_idx]        <= incoming_dep_match;
            end

            // 2. Process Allocation to CMT and Cores
            if (ava_core_valid && ready_valid) begin
                tmt_cmt_ack         <= 1'b1;
                tmt_idx_tmt_cmt     <= ready_idx;
                task_id_tmt_cmt     <= trf_task_id[ready_idx];
                // Calculate Instance ID: Quota - Dispatch_Left
                instance_id_tmt_cmt <= trf_quota[ready_idx] - trf_dispatch_left[ready_idx];
                dispatch_addr       <= trf_addr[ready_idx];
                dispatch_core_id    <= ava_core_id;

                // Decrement allocations remaining
                trf_dispatch_left[ready_idx] <= trf_dispatch_left[ready_idx] - 1;
            end

            // 3. Process Termination from CMT (With Safety Gating)
            if (task_done_pulse && trf_valid[terminated_tmt_idx]) begin
                // Decrement the Done_Left counter for the terminated instance
                trf_done_left[terminated_tmt_idx] <= trf_done_left[terminated_tmt_idx] - 1;

                // Check if this was the last instance of the task
                if (trf_done_left[terminated_tmt_idx] == 1) begin
                    trf_valid[terminated_tmt_idx] <= 1'b0; // Free the row
                    
                    // Clear the completed task from the dependency matrix (column reset)
                    for (j = 0; j < 16; j = j + 1) begin
                        dep_matrix[j][terminated_tmt_idx] <= 1'b0;
                    end
                end
            end
            
            // FDIR: Dependency Deadlock Detection (Simplified)
            // If the TRF is completely full, but no task is ready to dispatch, we have a deadlock
            if (trf_valid == 16'hFFFF && !ready_valid) begin
                err <= 2'b01; // Deadlock error
            end
        end
    end

endmodule