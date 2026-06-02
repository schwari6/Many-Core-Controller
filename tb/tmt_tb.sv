`timescale 1ns / 1ps
`include "../src/modules/tmt.v"

module tmt_tb();

    reg         clk;
    reg         rst_n;

    // FIFO interface
    reg  [63:0] fifo_tmt_data;
    reg         empty;
    wire        tmt_fifo_ack;

    // CMT interface (Allocation)
    reg         ava_core_valid;
    reg  [5:0]  ava_core_id;
    wire        tmt_cmt_ack;
    wire [3:0]  tmt_idx_tmt_cmt;
    wire [9:0]  task_id_tmt_cmt;
    wire [9:0]  instance_id_tmt_cmt;

    // CMT interface (Termination)
    reg         task_done_pulse;
    reg  [3:0]  terminated_tmt_idx;

    // Cores Interface
    wire [31:0] dispatch_addr;
    wire [5:0]  dispatch_core_id;
    
    // Status
    wire [1:0]  err;

    tmt uut (
        .clk(clk),
        .rst_n(rst_n),
        .fifo_tmt_data(fifo_tmt_data),
        .empty(empty),
        .tmt_fifo_ack(tmt_fifo_ack),
        .ava_core_valid(ava_core_valid),
        .ava_core_id(ava_core_id),
        .tmt_cmt_ack(tmt_cmt_ack),
        .tmt_idx_tmt_cmt(tmt_idx_tmt_cmt),
        .task_id_tmt_cmt(task_id_tmt_cmt),
        .instance_id_tmt_cmt(instance_id_tmt_cmt),
        .task_done_pulse(task_done_pulse),
        .terminated_tmt_idx(terminated_tmt_idx),
        .dispatch_addr(dispatch_addr),
        .dispatch_core_id(dispatch_core_id),
        .err(err)
    );

    // Clock generation (300MHz -> ~3.33ns period, using 4ns for simple 250MHz simulation)
    initial begin
        clk = 0;
        forever #2 clk = ~clk;
    end

    // Helper task to format the 64-bit word
    task set_fifo_data;
        input [9:0]  id;
        input [9:0]  quota;
        input [31:0] addr;
        input [9:0]  dep;
        begin
            // [63:54] ID, [53:44] Quota, [43:12] Addr, [11:2] Dep, [1:0] Rsvd
            fifo_tmt_data = {id, quota, addr, dep, 2'b00};
        end
    endtask

    initial begin
        // Init
        rst_n = 0;
        empty = 1;
        fifo_tmt_data = 0;
        ava_core_valid = 0;
        ava_core_id = 0;
        task_done_pulse = 0;
        terminated_tmt_idx = 0;

        #10;
        rst_n = 1;
        #10;

        $display("--- Start of TMT Test ---");

        // ---------------------------------------------------------------------
        // 1. Ingress: Task 100 enters (No dependencies, Quota = 2)
        // ---------------------------------------------------------------------
        $display("Ingress: Loading Task 100...");
        set_fifo_data(10'd100, 10'd2, 32'h0000_1000, 10'd0);
        empty = 0;
        @(posedge clk);
        #1;
        empty = 1; // FIFO empty again

        // Wait a cycle for internal routing and FSM update
        @(posedge clk);
        #1;
        // Verify FSM State is READY (01) for row 0
        if (uut.trf_fsm_state[0] == 2'b01) $display("PASS: Task 100 State is READY (01).");
        else $display("FAIL: Task 100 State is %b, expected 01", uut.trf_fsm_state[0]);

        // ---------------------------------------------------------------------
        // 2. Allocation: Dispatch Instance 0
        // ---------------------------------------------------------------------
        $display("Allocation: Requesting core for Task 100...");
        ava_core_valid = 1;
        ava_core_id = 6'd12; // Core 12 is free
        @(posedge clk);
        #1;
        if (tmt_cmt_ack && task_id_tmt_cmt == 10'd100 && instance_id_tmt_cmt == 10'd0)
            $display("PASS: Dispatched Task 100, Instance 0 to Core 12");
        else
            $display("FAIL: Dispatch incorrect. Task=%d, Inst=%d", task_id_tmt_cmt, instance_id_tmt_cmt);
            
        // ---------------------------------------------------------------------
        // 3. Allocation: Dispatch Instance 1
        // ---------------------------------------------------------------------
        ava_core_id = 6'd13; // Core 13 is free
        @(posedge clk);
        #1;
        if (tmt_cmt_ack && instance_id_tmt_cmt == 10'd1)
            $display("PASS: Dispatched Task 100, Instance 1 to Core 13");
        else
            $display("FAIL: Dispatch incorrect. Inst=%d", instance_id_tmt_cmt);
            
        ava_core_valid = 0; // Stop asking for cores

        @(posedge clk);
        #1;
        // Verify FSM State is ALL_ALLOCATED (10) for row 0 since dispatch_left == 0
        if (uut.trf_fsm_state[0] == 2'b10) $display("PASS: Task 100 State is ALL_ALLOCATED (10).");
        else $display("FAIL: Task 100 State is %b, expected 10", uut.trf_fsm_state[0]);

        // ---------------------------------------------------------------------
        // 4. Ingress: Task 200 enters (Depends on Task 100, Quota = 1)
        // ---------------------------------------------------------------------
        $display("Ingress: Loading Task 200 (Depends on 100)...");
        set_fifo_data(10'd200, 10'd1, 32'h0000_2000, 10'd100);
        empty = 0;
        @(posedge clk);
        #1;
        empty = 1;
        
        @(posedge clk);
        #1;
        // Verify FSM State is PENDING (00) for row 1
        if (uut.trf_fsm_state[1] == 2'b00) $display("PASS: Task 200 State is PENDING (00).");
        else $display("FAIL: Task 200 State is %b, expected 00", uut.trf_fsm_state[1]);

        // Ensure Task 200 is NOT dispatched (it should be stuck in pending)
        ava_core_valid = 1;
        ava_core_id = 6'd14;
        @(posedge clk);
        #1;
        if (!tmt_cmt_ack)
            $display("PASS: Task 200 correctly blocked by dependency.");
        else
            $display("FAIL: Task 200 was dispatched early!");
            
        ava_core_valid = 0;

        // ---------------------------------------------------------------------
        // 5. Termination: Both instances of Task 100 finish
        // ---------------------------------------------------------------------
        $display("Termination: Completing Task 100 to resolve dependency...");
        @(posedge clk);
        task_done_pulse = 1;
        terminated_tmt_idx = 4'd0; // Assuming Task 100 was placed in row 0
        @(posedge clk);
        // Second instance finishes
        @(posedge clk);
        task_done_pulse = 0;
        
        @(posedge clk);
        #1;
        // Task 100 row should be freed (valid=0), so state returns to PENDING (00) by default logic
        if (uut.trf_valid[0] == 1'b0) $display("PASS: Task 100 row correctly freed.");
        else $display("FAIL: Task 100 row still active.");

        // Verify FSM State is READY (01) for row 1 (Task 200) since dependency cleared
        if (uut.trf_fsm_state[1] == 2'b01) $display("PASS: Task 200 State is now READY (01).");
        else $display("FAIL: Task 200 State is %b, expected 01", uut.trf_fsm_state[1]);

        // ---------------------------------------------------------------------
        // 6. Allocation: Task 200 should now be unblocked
        // ---------------------------------------------------------------------
        ava_core_valid = 1;
        ava_core_id = 6'd14;
        @(posedge clk);
        #1;
        if (tmt_cmt_ack && task_id_tmt_cmt == 10'd200)
            $display("PASS: Task 200 dependency resolved and dispatched.");
        else
            $display("FAIL: Task 200 not dispatched after dependency resolution.");

        $display("--- End of TMT Test ---");
        $finish;
    end
endmodule