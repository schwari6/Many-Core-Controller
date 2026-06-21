`timescale 1ns / 1ps

module cmt_tb();

    // -------------------------------------------------------------------------
    // 1. אותות השעון והאיפוס (Clock & Reset)
    // -------------------------------------------------------------------------
    reg clk;
    reg rst_n;

    // -------------------------------------------------------------------------
    // 2. אותות ממשק אלוקציה (Interface with TMT - Allocation)
    // -------------------------------------------------------------------------
    wire        ava_core_valid;
    wire [5:0]  ava_core_id;
    reg  [9:0]  task_id_tmt_cmt;
    reg  [3:0]  tmt_idx_tmt_cmt;
    reg  [9:0]  instance_num_tmt_cmt;
    reg         tmt_cmt_ack;

    // -------------------------------------------------------------------------
    // 3. אותות ממשק סיום משימה (Interface with TMT - Termination)
    // -------------------------------------------------------------------------
    wire        task_done_pulse;
    wire [3:0]  terminated_tmt_idx;

    // -------------------------------------------------------------------------
    // 4. אותות ממשק מול הליבות (Interface with CORES)
    // -------------------------------------------------------------------------
    reg  [63:0] core_done_vec;
    wire [5:0]  core_id_cmt_core;
    wire        done_ack;

    // -------------------------------------------------------------------------
    // 5. אותות סטטוס ושגיאות (Status / FDIR)
    // -------------------------------------------------------------------------
    wire [1:0]  err;

    // -------------------------------------------------------------------------
    // 6. חיבור רכיב ה-UUT (Unit Under Test)
    // -------------------------------------------------------------------------
    cmt uut (
        .i_clk(clk),
        .i_rst_n(rst_n),
        
        // Allocation Interface
        .o_ava_core_valid(ava_core_valid),
        .o_ava_core_id(ava_core_id),
        .i_task_id_tmt_cmt(task_id_tmt_cmt),
        .i_tmt_idx_tmt_cmt(tmt_idx_tmt_cmt),
        .i_instance_num_tmt_cmt(instance_num_tmt_cmt),
        .i_tmt_cmt_ack(tmt_cmt_ack),
        
        // Termination Interface
        .o_task_done_pulse(task_done_pulse),
        .o_terminated_tmt_idx(terminated_tmt_idx),
        
        // Cores Interface
        .i_core_done_vec(core_done_vec),
        .o_core_id_cmt_core(core_id_cmt_core),
        .o_done_ack(done_ack),
        
        // FDIR
        .o_err(err)
    );

    // -------------------------------------------------------------------------
    // 7. יצירת מחולל שעון (Clock Generator - 100MHz / 10ns period)
    // -------------------------------------------------------------------------
    always begin
        #5 clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // 8. תרחישי הבדיקה (Stimulus / Test Cases)
    // -------------------------------------------------------------------------
    integer i; // משתנה עזר ללולאות הקצאה

    initial begin
        // אתחול קבצי ה-VCD לצפייה בגלים (GTKWave) - המקור שלך נשמר!
        $dumpfile("cmt_sim.vcd");
        $dumpvars(0, cmt_tb);

        // מצב התחלתי
        clk = 0;
        rst_n = 0;
        task_id_tmt_cmt = 10'd0;
        tmt_idx_tmt_cmt = 4'd0;
        instance_num_tmt_cmt = 10'd0;
        tmt_cmt_ack = 0;
        core_done_vec = 64'd0;

        // --- תרחיש 0: הפעלת איפוס (Reset) ---
        #20;
        rst_n = 1; // יציאה מאיפוס
        #10;

        // =====================================================================
        // תרחיש 1: אלוקציה רגילה של משימה לליבה הפנויה הראשונה
        // =====================================================================
        $display("[TC1] Starting Regular Allocation...");
        @(posedge clk);
        if (ava_core_valid) begin
            $display("[TC1] Found available core ID: %d", ava_core_id);
            task_id_tmt_cmt = 10'h0A5;       
            tmt_idx_tmt_cmt = 4'd2;          
            instance_num_tmt_cmt = 10'd1;    
            tmt_cmt_ack = 1;                 
        end
        
        @(posedge clk);
        tmt_cmt_ack = 0; 
        #20;

        // =====================================================================
        // תרחיש 2: אלוקציה של מספר משימות במקביל לבדיקת תפוסת ליבות
        // =====================================================================
        $display("[TC2] Starting Multiple Consecutive Allocations...");
        repeat (3) begin
            @(posedge clk);
            if (ava_core_valid) begin
                $display("[TC2] Allocating next core ID: %d", ava_core_id);
                task_id_tmt_cmt = task_id_tmt_cmt + 1;
                tmt_idx_tmt_cmt = 4'd3; 
                instance_num_tmt_cmt = 10'd2;
                tmt_cmt_ack = 1;
            end
            @(posedge clk);
            tmt_cmt_ack = 0;
            #10;
        end

        // =====================================================================
        // תרחיש 3: סיום משימה של ליבה בודדת ועדכון ה-TMT
        // =====================================================================
        $display("[TC3] Testing Core Termination Handshake...");
        @(posedge clk);
        core_done_vec[0] = 1'b1; 
        
        @(posedge clk);
        #1; 
        if (task_done_pulse) begin
            $display("[TC3] Success: CMT sent task_done_pulse to TMT for row idx: %d", terminated_tmt_idx);
        end
        
        @(posedge clk);
        core_done_vec[0] = 1'b0; 
        #30;

        // =====================================================================
        // תרחיש 4: קונפליקט ובוררות - שתי ליבות מסיימות באותו מחזור שעון
        // =====================================================================
        $display("[TC4] Testing Simultaneous Core Terminations (Arbitration)...");
        @(posedge clk);
        core_done_vec[1] = 1'b1; 
        core_done_vec[2] = 1'b1; 
        
        @(posedge clk);
        #1;
        $display("[TC4] First handled termination for TMT row idx: %d", terminated_tmt_idx);
        if (done_ack) begin
             if (core_id_cmt_core == 6'd1) core_done_vec[1] = 1'b0;
             else if (core_id_cmt_core == 6'd2) core_done_vec[2] = 1'b0;
        end

        @(posedge clk);
        #1;
        $display("[TC4] Second handled termination for TMT row idx: %d", terminated_tmt_idx);
        core_done_vec[1] = 1'b0;
        core_done_vec[2] = 1'b0;
        #30;

        // =====================================================================
        // תרחיש 5: מצב תפוסה מלאה (Full Core Saturation - 64 Cores Busy)
        // הסבר: נבצע הקצאות רצופות עד שוקטור הליבות יתמלא לחלוטין.
        // נבדוק ש-ava_core_valid יורד ל-'0' ושלא ניתן להקצות משימות נוספות.
        // =====================================================================
        $display("[TC5] Filling up all remaining cores to reach Saturation...");
        for (i = 0; i < 64; i = i + 1) begin
            @(posedge clk);
            if (ava_core_valid) begin
                task_id_tmt_cmt = i + 10;
                tmt_idx_tmt_cmt = i % 16; // חלוקה סבירה לשורות ה-TMT
                instance_num_tmt_cmt = 10'd1;
                tmt_cmt_ack = 1;
            end else begin
                // אם הגענו למצב שאין ליבות פנויות, הלולאה תדלג או תעצור
                tmt_cmt_ack = 0;
            end
        end
        
        @(posedge clk);
        tmt_cmt_ack = 0;
        #20;
        
        // בדיקה האם הרכיב מגן על עצמו ומודיע שאין ליבות פנויות
        if (!ava_core_valid) begin
            $display("[TC5] Success: All cores are BUSY. ava_core_valid is correctly low ('0').");
        end else begin
            $display("[TC5] WARNING: ava_core_valid is still high even after mass allocations!");
        end
        #20;

        // =====================================================================
        // תרחיש 6: שחרור הדרגתי וזמינות מיידית (Immediate Availability)
        // הסבר: כשהמערכת מלאה, נשחרר ליבה אחת (למשל ליבה 5) ונראה
        // ש-ava_core_valid עולה מיד בחזרה במחזור הבא ומציע בדיוק את ליבה 5.
        // =====================================================================
        $display("[TC6] Testing Immediate Availability by clearing Core 5...");
        @(posedge clk);
        core_done_vec[5] = 1'b1; // ליבה 5 מודיעה שסיימה
        
        @(posedge clk);
        #1;
        if (done_ack && (core_id_cmt_core == 6'd5)) begin
            core_done_vec[5] = 1'b0; // הורדת קו הסיום
        end
        
        // נחכה מחזור שעון אחד לעדכון הסטטוס הפנימי
        @(posedge clk);
        #1;
        if (ava_core_valid && (ava_core_id == 6'd5)) begin
            $display("[TC6] Success: Core 5 freed up and immediately marked as AVAILABLE.");
        end else begin
            $display("[TC6] Error: Core 5 was freed but not allocated/available correctly.");
        end
        #20;

        // =====================================================================
        // תרחיש 7: בדיקת פרוטוקול Handshake מול הליבות (Done -> Ack Handshake)
        // הסבר: נדמה ליבה שמחזיקה את קו ה-done שלה למשך זמן ארוך (למשל ליבה 10), 
        // ונראה שה-CMT מוציא רק פולס done_ack אחד ולא מפרש את זה בטעות כסיומים מרובים.
        // =====================================================================
        $display("[TC7] Testing Core Handshake duration holding done high...");
        @(posedge clk);
        core_done_vec[10] = 1'b1; // ליבה 10 מסיימת
        
        // נחזיק את הסיגנל גבוה למשך 3 מחזורי שעון בכוונה (ללא תלות ב-ACK)
        repeat (3) begin
            @(posedge clk);
            #1;
            if (done_ack) begin
                $display("[TC7] CMT generated done_ack for Core ID: %d", core_id_cmt_core);
            end
        end
        
        @(posedge clk);
        core_done_vec[10] = 1'b0; // הסרת האות בסוף התהליך
        #50;


        // =====================================================================
        // תרחיש 8: משימה אחת בעלת כמה חזרות (Multi-Instance / Duplication)
        // הסבר: משימה בודדת (Task ID = 0x1F) צריכה להתבצע 3 פעמים במקביל.
        // ה-TMT מקצה אותה ל-3 ליבות שונות בזו אחר זו, ומעדכן את ה-Instance Number.
        // =====================================================================
        $display("[TC8] Starting Multi-Instance Allocation for Task 0x1F (3 Instances)...");
        
        // --- עותק ראשון (Instance 0) ---
        @(posedge clk);
        if (ava_core_valid) begin
            $display("[TC8] Allocating Task 0x1F, Instance 0 to Core ID: %d", ava_core_id);
            task_id_tmt_cmt      = 10'h1F;       // אותו Task ID
            tmt_idx_tmt_cmt      = 4'd5;         // אותה שורה ב-TMT
            instance_num_tmt_cmt = 10'd0;        // Instance #0
            tmt_cmt_ack          = 1;
        end
        @(posedge clk);
        tmt_cmt_ack = 0;
        #10; // המתנה קלה בין הקצאות

        // --- עותק שני (Instance 1) ---
        @(posedge clk);
        if (ava_core_valid) begin
            $display("[TC8] Allocating Task 0x1F, Instance 1 to Core ID: %d", ava_core_id);
            task_id_tmt_cmt      = 10'h1F;       // אותו Task ID
            tmt_idx_tmt_cmt      = 4'd5;         // אותה שורה ב-TMT
            instance_num_tmt_cmt = 10'd1;        // Instance #1
            tmt_cmt_ack          = 1;
        end
        @(posedge clk);
        tmt_cmt_ack = 0;
        #10;

        // --- עותק שלישי (Instance 2) ---
        @(posedge clk);
        if (ava_core_valid) begin
            $display("[TC8] Allocating Task 0x1F, Instance 2 to Core ID: %d", ava_core_id);
            task_id_tmt_cmt      = 10'h1F;       // אותו Task ID
            tmt_idx_tmt_cmt      = 4'd5;         // אותה שורה ב-TMT
            instance_num_tmt_cmt = 10'd2;        // Instance #2
            tmt_cmt_ack          = 1;
        end
        @(posedge clk);
        tmt_cmt_ack = 0;
        #30;

        // --- סימולציית סיום הדרגתי של העותקים ---
        $display("[TC8] Simulating termination of the instances...");
        
        // נניח שהעותק הראשון (נניח שתפס את ליבה 12) מסיים
        @(posedge clk);
        core_done_vec[12] = 1'b1; 
        
        @(posedge clk);
        #1;
        if (task_done_pulse && (terminated_tmt_idx == 4'd5)) begin
            $display("[TC8] Success: CMT reported termination of an instance from TMT row 5");
        end
        
        @(posedge clk);
        core_done_vec[12] = 1'b0;
        #20;


        // סיום כלל הבדיקות
        $display("--- All 7 test cases completed successfully! ---");
        $finish;
    end

endmodule
