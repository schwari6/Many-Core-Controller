`timescale 1ns / 1ps

module controller #(
    parameter FIFO_DEPTH = 128,     // Depth of the ingress FIFO
    parameter FIFO_WIDTH = 64       // Width of the data bus from HOST
)(
    // -------------------------------------------------------------------------
    // Global System Signals
    // -------------------------------------------------------------------------
    input  wire        clk,
    input  wire        rst_n,

    // -------------------------------------------------------------------------
    // Ingress Interface (From HOST to FIFO)
    // -------------------------------------------------------------------------
    input  wire                  cfg_en,
    input  wire [FIFO_WIDTH-1:0] cfg_data,
    output wire                  full,

    // -------------------------------------------------------------------------
    // Dispatch Interface (From TMT to CORES)
    // -------------------------------------------------------------------------
    output wire [31:0]           dispatch_addr,
    output wire [5:0]            dispatch_core_id,

    // -------------------------------------------------------------------------
    // Termination Interface (From CORES to CMT)
    // -------------------------------------------------------------------------
    input  wire [63:0]           core_done_vec,
    output wire [5:0]            core_id_cmt_core,
    output wire                  done_ack,

    // -------------------------------------------------------------------------
    // System Status & FDIR
    // -------------------------------------------------------------------------
    // We combine the 2-bit error from TMT and 2-bit error from CMT into a 4-bit bus
    output wire [3:0]            err_bus
);

    // =========================================================================
    // Internal Wires (Interconnects between Sub-Modules)
    // =========================================================================

    // FIFO <---> TMT
    wire [FIFO_WIDTH-1:0] fifo_tmt_data_wire;
    wire                  empty_wire;
    wire                  tmt_fifo_ack_wire;

    // CMT <---> TMT (Allocation Path)
    wire                  ava_core_valid_wire;
    wire [5:0]            ava_core_id_wire;
    wire                  tmt_cmt_ack_wire;
    wire [3:0]            tmt_idx_tmt_cmt_wire;
    wire [9:0]            task_id_tmt_cmt_wire;
    wire [9:0]            instance_id_tmt_cmt_wire;

    // CMT <---> TMT (Termination Path)
    wire                  task_done_pulse_wire;
    wire [3:0]            terminated_tmt_idx_wire;

    // Internal Errors
    wire [1:0]            tmt_err_wire;
    wire [1:0]            cmt_err_wire;

    // Assign internal errors to external bus [TMT_ERR, CMT_ERR]
    assign err_bus = {tmt_err_wire, cmt_err_wire};

    // =========================================================================
    // Sub-Module Instantiations
    // =========================================================================

    // -------------------------------------------------------------------------
    // 1. Ingress FIFO
    // -------------------------------------------------------------------------
    fifo #(
        .FIFO_DEPTH(FIFO_DEPTH),
        .FIFO_WIDTH(FIFO_WIDTH)
    ) inst_fifo (
        .clk             (clk),
        .rst_n           (rst_n),
        
        // Write Port (From HOST)
        .cfg_en          (cfg_en),
        .cfg_data        (cfg_data),
        .full            (full),
        
        // Read Port (To TMT)
        .tmt_fifo_ack    (tmt_fifo_ack_wire),
        .empty           (empty_wire),
        .fifo_tmt_data   (fifo_tmt_data_wire)
    );

    // -------------------------------------------------------------------------
    // 2. Task Management Table (TMT)
    // -------------------------------------------------------------------------
    tmt inst_tmt (
        .clk                 (clk),
        .rst_n               (rst_n),
        
        // FIFO Interface
        .fifo_tmt_data       (fifo_tmt_data_wire),
        .empty               (empty_wire),
        .tmt_fifo_ack        (tmt_fifo_ack_wire),
        
        // CMT Interface (Allocation Downstream)
        .ava_core_valid      (ava_core_valid_wire),
        .ava_core_id         (ava_core_id_wire),
        .tmt_cmt_ack         (tmt_cmt_ack_wire),
        .tmt_idx_tmt_cmt     (tmt_idx_tmt_cmt_wire),
        .task_id_tmt_cmt     (task_id_tmt_cmt_wire),
        .instance_id_tmt_cmt (instance_id_tmt_cmt_wire),
        
        // CMT Interface (Termination Upstream)
        .task_done_pulse     (task_done_pulse_wire),
        .terminated_tmt_idx  (terminated_tmt_idx_wire),
        
        // CORES Interface (Dispatch)
        .dispatch_addr       (dispatch_addr),
        .dispatch_core_id    (dispatch_core_id),
        
        // Status / FDIR
        .err                 (tmt_err_wire)
    );

// -------------------------------------------------------------------------
    // 3. Core Management Table (CMT)
    // -------------------------------------------------------------------------
    cmt inst_cmt (
        .clk                 (clk),
        .rst_n               (rst_n),
        
        // TMT Interface (Allocation)
        .ava_core_valid      (ava_core_valid_wire),
        .ava_core_id         (ava_core_id_wire),
        .task_id_tmt_cmt     (task_id_tmt_cmt_wire),   
        .tmt_idx_tmt_cmt     (tmt_idx_tmt_cmt_wire),
        .instance_num_tmt_cmt(instance_id_tmt_cmt_wire),  
        .tmt_cmt_ack         (tmt_cmt_ack_wire),
        
        // TMT Interface (Termination)
        .task_done_pulse     (task_done_pulse_wire),
        .terminated_tmt_idx  (terminated_tmt_idx_wire),
        
        // CORES Interface
        .core_done_vec       (core_done_vec),
        .core_id_cmt_core    (core_id_cmt_core),
        .done_ack            (done_ack),
        
        // Status / FDIR
        .err                 (cmt_err_wire)
    );

endmodule