`timescale 1ns / 1ps

`include "../src/modules/fifo.v"
`include "../src/modules/cmt.v"
`include "../src/modules/tmt.v"

module controller #(
    parameter FIFO_DEPTH = 128,     // Depth of the ingress FIFO
    parameter FIFO_WIDTH = 64       // Width of the data bus from HOST
)(
    // -------------------------------------------------------------------------
    // Global System Signals
    // -------------------------------------------------------------------------
    input  wire        i_clk,
    input  wire        i_rst_n,

    // -------------------------------------------------------------------------
    // Ingress Interface (From HOST to FIFO)
    // -------------------------------------------------------------------------
    input  wire                  i_cfg_en,
    input  wire [FIFO_WIDTH-1:0] i_cfg_data,
    output wire                  o_full,

    // -------------------------------------------------------------------------
    // Dispatch Interface (From TMT to CORES)
    // -------------------------------------------------------------------------
    output wire [31:0]           o_dispatch_addr,
    output wire [5:0]            o_dispatch_core_id,

    // -------------------------------------------------------------------------
    // Termination Interface (From CORES to CMT)
    // -------------------------------------------------------------------------
    input  wire [63:0]           i_core_done_vec,
    output wire [5:0]            o_core_id_cmt_core,
    output wire                  o_done_ack,

    // -------------------------------------------------------------------------
    // System Status & FDIR
    // -------------------------------------------------------------------------
    // We combine the 2-bit error from TMT and 2-bit error from CMT into a 4-bit bus
    output wire [3:0]            o_err_bus
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
    assign o_err_bus = {tmt_err_wire, cmt_err_wire};

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
        .i_clk             (i_clk),
        .i_rst_n           (i_rst_n),
        
        // Write Port (From HOST)
        .i_cfg_en          (i_cfg_en),
        .i_cfg_data        (i_cfg_data),    // <--- תוקן כאן: היה o_cfg_data בטעות!
        .o_full            (o_full),
        
        // Read Port (To TMT)
        .i_tmt_fifo_ack    (tmt_fifo_ack_wire),
        .o_empty           (empty_wire),
        .o_fifo_tmt_data   (fifo_tmt_data_wire)
    );

    // -------------------------------------------------------------------------
    // 2. Task Management Table (TMT)
    // -------------------------------------------------------------------------
    tmt inst_tmt (
        .i_clk                 (i_clk),
        .i_rst_n               (i_rst_n),
        
        // FIFO Interface
        .i_fifo_tmt_data       (fifo_tmt_data_wire),
        .i_empty               (empty_wire),
        .o_tmt_fifo_ack        (tmt_fifo_ack_wire),
        
        // CMT Interface (Allocation Downstream)
        .i_ava_core_valid      (ava_core_valid_wire),
        .i_ava_core_id         (ava_core_id_wire),
        .o_tmt_cmt_ack         (tmt_cmt_ack_wire),
        .o_tmt_idx_tmt_cmt     (tmt_idx_tmt_cmt_wire),
        .o_task_id_tmt_cmt     (task_id_tmt_cmt_wire),
        .o_instance_id_tmt_cmt (instance_id_tmt_cmt_wire),
        
        // CMT Interface (Termination Upstream)
        .i_task_done_pulse     (task_done_pulse_wire),
        .i_terminated_tmt_idx  (terminated_tmt_idx_wire),
        
        // CORES Interface (Dispatch)
        .o_dispatch_addr       (o_dispatch_addr),
        .o_dispatch_core_id    (o_dispatch_core_id),
        
        // Status / FDIR
        .o_err                 (tmt_err_wire)
    );

    // -------------------------------------------------------------------------
    // 3. Core Management Table (CMT)
    // -------------------------------------------------------------------------
    cmt inst_cmt (
        .i_clk                 (i_clk),
        .i_rst_n               (i_rst_n),
        
        // TMT Interface (Allocation)
        .o_ava_core_valid      (ava_core_valid_wire),
        .o_ava_core_id         (ava_core_id_wire),
        .i_task_id_tmt_cmt     (task_id_tmt_cmt_wire),   
        .i_tmt_idx_tmt_cmt     (tmt_idx_tmt_cmt_wire),
        .i_instance_num_tmt_cmt(instance_id_tmt_cmt_wire),  
        .i_tmt_cmt_ack         (tmt_cmt_ack_wire),
        
        // TMT Interface (Termination)
        .o_task_done_pulse     (task_done_pulse_wire),
        .o_terminated_tmt_idx  (terminated_tmt_idx_wire),
        
        // CORES Interface
        .i_core_done_vec       (i_core_done_vec),
        .o_core_id_cmt_core    (o_core_id_cmt_core),
        .o_done_ack            (o_done_ack),
        
        // Status / FDIR
        .o_err                 (cmt_err_wire)
    );

endmodule
