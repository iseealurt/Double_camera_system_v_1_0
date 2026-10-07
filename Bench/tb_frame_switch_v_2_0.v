`timescale 1ns/1ps

module tb_frame_switch_v_2_0;

    //=============================================================================
    // Parameters
    //=============================================================================
    localparam  AXI_ADDR_WIDTH  = 28;
    localparam  AXI_ID_WIDTH    = 4;
    localparam  AXI_LEN_WIDTH   = 4;
    localparam  DDR_DQ_WIDTH    = 32;
    localparam  PIX_DATA_WIDTH  = 16;
    localparam  FRAME_WIDTH     = 640;
    localparam  FRAME_HEIGHT    = 480;
    localparam  RD_USER_VAL     = 2;

    localparam  TOTAL_BUFS      = RD_USER_VAL + 2;
    localparam  BUFFER_SIZE     = FRAME_WIDTH * FRAME_HEIGHT * PIX_DATA_WIDTH / DDR_DQ_WIDTH;
    localparam  PTR_WIDTH       = $clog2(TOTAL_BUFS);

    localparam  CLK_PERIOD      = 10;
    localparam  AXI_BURST_LEN   = 4'd15;
    localparam  DDR_WORDS_PER_BURST = (AXI_BURST_LEN + 1) * (256 / DDR_DQ_WIDTH);
    localparam  BYTES_PER_DDR_WORD  = DDR_DQ_WIDTH / 8;

    // Simulation speed-up: divide delays by this factor
    localparam  SIM_TIME_SCALE  = 1000;
    localparam  DELAY_33MS      = 33000000 / SIM_TIME_SCALE;
    localparam  DELAY_10MS      = 10000000 / SIM_TIME_SCALE;
    localparam  DELAY_20MS      = 20000000 / SIM_TIME_SCALE;
    localparam  DELAY_30MS      = 30000000 / SIM_TIME_SCALE;
    localparam  DELAY_40MS      = 40000000 / SIM_TIME_SCALE;

    // Completion address offset from buffer base (in bytes)
    localparam  COMPLETE_ADDR_OFFSET = (BUFFER_SIZE - DDR_WORDS_PER_BURST) * BYTES_PER_DDR_WORD;

    //=============================================================================
    // Clock & Reset
    //=============================================================================
    reg clk;
    reg rst_n;

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    //=============================================================================
    // DUT Signals
    //=============================================================================
    reg  [AXI_ADDR_WIDTH-1:0]              wr_user_awaddr;
    reg                                     wr_user_awvalid;
    wire                                    wr_user_awready;
    reg  [AXI_ID_WIDTH-1:0]                wr_user_awid;
    reg  [AXI_LEN_WIDTH-1:0]               wr_user_awlen;

    reg  [RD_USER_VAL*AXI_ADDR_WIDTH-1:0]  rd_user_araddr;
    reg  [RD_USER_VAL-1:0]                 rd_user_arvalid;
    wire [RD_USER_VAL-1:0]                 rd_user_arready;
    reg  [RD_USER_VAL*AXI_ID_WIDTH-1:0]    rd_user_arid;
    reg  [RD_USER_VAL*AXI_LEN_WIDTH-1:0]   rd_user_arlen;

    wire [AXI_ADDR_WIDTH-1:0]              write_buffer_offset;
    wire [RD_USER_VAL*AXI_ADDR_WIDTH-1:0]  read_buffer_offset;

    wire [AXI_ID_WIDTH-1:0]                wr_user_id = 4'd0;
    wire [RD_USER_VAL*AXI_ID_WIDTH-1:0]    rd_user_id = {4'd1, 4'd0};

    //=============================================================================
    // DUT Instantiation
    //=============================================================================
    frame_switch_v_2_0 #(
        .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH   (AXI_ID_WIDTH),
        .AXI_LEN_WIDTH  (AXI_LEN_WIDTH),
        .DDR_DQ_WIDTH   (DDR_DQ_WIDTH),
        .PIX_DATA_WIDTH (PIX_DATA_WIDTH),
        .FRAME_WIDTH    (FRAME_WIDTH),
        .FRAME_HEIGHT   (FRAME_HEIGHT),
        .RD_USER_VAL    (RD_USER_VAL)
    ) dut (
        .clk                        (clk),
        .rst_n                      (rst_n),
        .wr_user_id                 (wr_user_id),
        .rd_user_id                 (rd_user_id),
        .wr_user_awaddr             (wr_user_awaddr),
        .wr_user_awvalid            (wr_user_awvalid),
        .wr_user_awready            (wr_user_awready),
        .wr_user_awid               (wr_user_awid),
        .wr_user_awlen              (wr_user_awlen),
        .rd_user_araddr             (rd_user_araddr),
        .rd_user_arvalid            (rd_user_arvalid),
        .rd_user_arready            (rd_user_arready),
        .rd_user_arid               (rd_user_arid),
        .rd_user_arlen              (rd_user_arlen),
        .write_buffer_offset        (write_buffer_offset),
        .read_buffer_offset         (read_buffer_offset)
    );

    // Force awready/arready always ready (DUT treats these as inputs)
    assign wr_user_awready = 1'b1;
    assign rd_user_arready[0] = 1'b1;
    assign rd_user_arready[1] = 1'b1;

    // Hierarchical references to DUT internal signals (not exposed as ports)
    wire                                    wr_user_finish_flag_pose  = dut.wr_user_finish_flag_pose;
    wire                                    wr_full_flag              = dut.wr_full;
    wire [PTR_WIDTH-1:0]                    wr_ptr_out                = dut.wr_ptr;
    wire [RD_USER_VAL-1:0]                  rd_user_finish_flag_pose;
    wire [RD_USER_VAL-1:0]                  rd_empty_flag;
    wire [RD_USER_VAL*PTR_WIDTH-1:0]        rd_ptr_out;

    assign rd_user_finish_flag_pose[0] = dut.rd_user_finish_flag_pose[0];
    assign rd_user_finish_flag_pose[1] = dut.rd_user_finish_flag_pose[1];
    assign rd_empty_flag[0] = dut.rd_data_empty[0];
    assign rd_empty_flag[1] = dut.rd_data_empty[1];
    assign rd_ptr_out[0*PTR_WIDTH+:PTR_WIDTH] = dut.rd_ptr[0];
    assign rd_ptr_out[1*PTR_WIDTH+:PTR_WIDTH] = dut.rd_ptr[1];

    //=============================================================================
    // Test Control
    //=============================================================================
    integer total_tests;
    integer pass_count;
    integer fail_count;
    integer scenario_id;
    reg [255:0] scenario_name;

    initial begin
        total_tests = 0;
        pass_count  = 0;
        fail_count  = 0;
        scenario_id = 0;

        // Initialize DUT inputs
        rst_n               = 1'b0;
        wr_user_awaddr      = {AXI_ADDR_WIDTH{1'b0}};
        wr_user_awvalid     = 1'b0;
        wr_user_awid        = wr_user_id;
        wr_user_awlen       = AXI_BURST_LEN;
        rd_user_araddr      = {RD_USER_VAL*AXI_ADDR_WIDTH{1'b0}};
        rd_user_arvalid     = {RD_USER_VAL{1'b0}};
        rd_user_arid        = {4'd1, 4'd0};
        rd_user_arlen       = {AXI_BURST_LEN, AXI_BURST_LEN};

        // Wait for reset
        #(CLK_PERIOD * 10);
        rst_n = 1'b1;
        #(CLK_PERIOD * 5);

        //=============================================================================
        // Run all test scenarios
        //=============================================================================
        scenario_1();
        scenario_2();
        scenario_3();
        scenario_4();
        scenario_5();
        scenario_6();
        scenario_7();
        scenario_8();
        scenario_9();
        scenario_10();
        scenario_11();
        scenario_12();
        scenario_13();
        scenario_14();
        scenario_15();
        scenario_16();
        scenario_17();

        //=============================================================================
        // Summary Report
        //=============================================================================
        #(CLK_PERIOD * 10);
        $display("========================================");
        $display("  Frame Switch v2.0 Test Complete");
        $display("========================================");
        $display("  Total Tests : %0d", total_tests);
        $display("  Passed      : %0d", pass_count);
        $display("  Failed      : %0d", fail_count);
        $display("========================================");
        if (fail_count == 0) begin
            $display("  ALL TESTS PASSED");
        end else begin
            $display("  SOME TESTS FAILED");
        end
        $display("========================================");
        $finish;
    end

    //=============================================================================
    // Helper Tasks
    //=============================================================================

    task reset_dut;
        begin
            rst_n = 1'b0;
            wr_user_awvalid = 1'b0;
            rd_user_arvalid = {RD_USER_VAL{1'b0}};
            #(CLK_PERIOD * 5);
            rst_n = 1'b1;
            #(CLK_PERIOD * 5);
        end
    endtask

    task send_aw_transaction;
        input [AXI_ADDR_WIDTH-1:0] addr;
        input [AXI_LEN_WIDTH-1:0]  len;
        begin
            @(posedge clk);
            wr_user_awaddr  = addr;
            wr_user_awlen   = len;
            wr_user_awid    = wr_user_id;
            wr_user_awvalid = 1'b1;
            @(posedge clk);
            while (!wr_user_awready) @(posedge clk);
            wr_user_awvalid = 1'b0;
            wr_user_awaddr  = {AXI_ADDR_WIDTH{1'b0}};
        end
    endtask

    task send_ar_transaction;
        input integer               rd_idx;
        input [AXI_ADDR_WIDTH-1:0]  addr;
        input [AXI_LEN_WIDTH-1:0]   len;
        begin
            @(posedge clk);
            rd_user_araddr[rd_idx*AXI_ADDR_WIDTH+:AXI_ADDR_WIDTH] = addr;
            rd_user_arlen[rd_idx*AXI_LEN_WIDTH+:AXI_LEN_WIDTH]   = len;
            rd_user_arid[rd_idx*AXI_ID_WIDTH+:AXI_ID_WIDTH]      = (rd_idx == 0) ? 4'd0 : 4'd1;
            rd_user_arvalid[rd_idx] = 1'b1;
            @(posedge clk);
            while (!rd_user_arready[rd_idx]) @(posedge clk);
            rd_user_arvalid[rd_idx] = 1'b0;
            rd_user_araddr[rd_idx*AXI_ADDR_WIDTH+:AXI_ADDR_WIDTH] = {AXI_ADDR_WIDTH{1'b0}};
        end
    endtask

    task send_wr_addr_set;
        input [AXI_LEN_WIDTH-1:0] first_len;
        input [AXI_LEN_WIDTH-1:0] mid_len;
        input [AXI_LEN_WIDTH-1:0] last_len;
        begin
            // Burst 1: start of buffer (no finish)
            send_aw_transaction(write_buffer_offset, first_len);
            #(DELAY_33MS);
            // Burst 2: completion address (triggers finish)
            send_aw_transaction(write_buffer_offset + COMPLETE_ADDR_OFFSET, mid_len);
            #(DELAY_33MS);
            // Burst 3: beyond buffer
            send_aw_transaction(write_buffer_offset + BUFFER_SIZE * BYTES_PER_DDR_WORD, last_len);
        end
    endtask

    task send_rd_addr_set;
        input integer              rd_idx;
        input [AXI_LEN_WIDTH-1:0]  first_len;
        input [AXI_LEN_WIDTH-1:0]  mid_len;
        input [AXI_LEN_WIDTH-1:0]  last_len;
        begin
            // Burst 1: start of buffer (no finish)
            send_ar_transaction(rd_idx, read_buffer_offset[rd_idx*AXI_ADDR_WIDTH+:AXI_ADDR_WIDTH], first_len);
            #(DELAY_33MS);
            // Burst 2: completion address (triggers finish)
            send_ar_transaction(rd_idx, read_buffer_offset[rd_idx*AXI_ADDR_WIDTH+:AXI_ADDR_WIDTH] + COMPLETE_ADDR_OFFSET, mid_len);
            #(DELAY_33MS);
            // Burst 3: beyond buffer
            send_ar_transaction(rd_idx, read_buffer_offset[rd_idx*AXI_ADDR_WIDTH+:AXI_ADDR_WIDTH] + BUFFER_SIZE * BYTES_PER_DDR_WORD, last_len);
        end
    endtask

    task check_wr_finish;
        input expected;
        input [255:0] msg;
        begin
            total_tests = total_tests + 1;
            #(CLK_PERIOD);
            if (wr_user_finish_flag_pose === expected) begin
                pass_count = pass_count + 1;
                $display("  [PASS] %s: wr_finish=%b (expected %b)", msg, wr_user_finish_flag_pose, expected);
            end else begin
                fail_count = fail_count + 1;
                $display("  [FAIL] %s: wr_finish=%b (expected %b)", msg, wr_user_finish_flag_pose, expected);
            end
        end
    endtask

    task check_rd_finish;
        input integer rd_idx;
        input expected;
        input [255:0] msg;
        begin
            total_tests = total_tests + 1;
            #(CLK_PERIOD);
            if (rd_user_finish_flag_pose[rd_idx] === expected) begin
                pass_count = pass_count + 1;
                $display("  [PASS] %s: rd[%0d]_finish=%b (expected %b)", msg, rd_idx, rd_user_finish_flag_pose[rd_idx], expected);
            end else begin
                fail_count = fail_count + 1;
                $display("  [FAIL] %s: rd[%0d]_finish=%b (expected %b)", msg, rd_idx, rd_user_finish_flag_pose[rd_idx], expected);
            end
        end
    endtask

    task check_wr_full;
        input expected;
        input [255:0] msg;
        begin
            total_tests = total_tests + 1;
            #(CLK_PERIOD);
            if (wr_full_flag === expected) begin
                pass_count = pass_count + 1;
                $display("  [PASS] %s: wr_full=%b (expected %b)", msg, wr_full_flag, expected);
            end else begin
                fail_count = fail_count + 1;
                $display("  [FAIL] %s: wr_full=%b (expected %b)", msg, wr_full_flag, expected);
            end
        end
    endtask

    task check_rd_empty;
        input integer rd_idx;
        input expected;
        input [255:0] msg;
        begin
            total_tests = total_tests + 1;
            #(CLK_PERIOD);
            if (rd_empty_flag[rd_idx] === expected) begin
                pass_count = pass_count + 1;
                $display("  [PASS] %s: rd[%0d]_empty=%b (expected %b)", msg, rd_idx, rd_empty_flag[rd_idx], expected);
            end else begin
                fail_count = fail_count + 1;
                $display("  [FAIL] %s: rd[%0d]_empty=%b (expected %b)", msg, rd_idx, rd_empty_flag[rd_idx], expected);
            end
        end
    endtask

    task check_wr_ptr;
        input [PTR_WIDTH-1:0] expected;
        input [255:0] msg;
        begin
            total_tests = total_tests + 1;
            #(CLK_PERIOD);
            if (wr_ptr_out === expected) begin
                pass_count = pass_count + 1;
                $display("  [PASS] %s: wr_ptr=%0d (expected %0d)", msg, wr_ptr_out, expected);
            end else begin
                fail_count = fail_count + 1;
                $display("  [FAIL] %s: wr_ptr=%0d (expected %0d)", msg, wr_ptr_out, expected);
            end
        end
    endtask

    task check_rd_ptr;
        input integer rd_idx;
        input [PTR_WIDTH-1:0] expected;
        input [255:0] msg;
        begin
            total_tests = total_tests + 1;
            #(CLK_PERIOD);
            if (rd_ptr_out[rd_idx*PTR_WIDTH+:PTR_WIDTH] === expected) begin
                pass_count = pass_count + 1;
                $display("  [PASS] %s: rd[%0d]_ptr=%0d (expected %0d)", msg, rd_idx, rd_ptr_out[rd_idx*PTR_WIDTH+:PTR_WIDTH], expected);
            end else begin
                fail_count = fail_count + 1;
                $display("  [FAIL] %s: rd[%0d]_ptr=%0d (expected %0d)", msg, rd_idx, rd_ptr_out[rd_idx*PTR_WIDTH+:PTR_WIDTH], expected);
            end
        end
    endtask

    task wait_wr_full;
        begin
            while (!wr_full_flag) begin
                send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            end
        end
    endtask

    task wait_rd_empty;
        input integer rd_idx;
        begin
            while (!rd_empty_flag[rd_idx]) begin
                send_rd_addr_set(rd_idx, AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            end
        end
    endtask

    task wait_rd_empty_both;
        begin
            while (!rd_empty_flag[0] || !rd_empty_flag[1]) begin
                if (!rd_empty_flag[0])
                    send_rd_addr_set(0, AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
                if (!rd_empty_flag[1])
                    send_rd_addr_set(1, AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            end
        end
    endtask

    function integer rand_range;
        input integer min_val;
        input integer max_val;
        begin
            rand_range = min_val + {$random} % (max_val - min_val + 1);
        end
    endfunction

    //=============================================================================
    // Scenario 1: WR端单次完成写入
    // 复位dut, 输入3个axi地址事务，其中中间一次为WR端写入完成时访问的地址
    //=============================================================================
    task scenario_1;
        begin
            scenario_id = 1;
            $display("");
            $display("========================================");
            $display("  Scenario %0d: WR Single Write Complete", scenario_id);
            $display("========================================");

            reset_dut();

            check_wr_finish(0, "S1.0: after reset");

            send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);

            check_wr_finish(0, "S1.1: after burst1 (no finish)");
            #(DELAY_33MS);
            check_wr_finish(0, "S1.2: after burst2 delay");
            #(CLK_PERIOD);
            check_wr_finish(1, "S1.3: after burst2 (finish triggered)");
            check_wr_ptr(1, "S1.4: wr_ptr incremented to 1");
            check_wr_full(0, "S1.5: not full yet");
            #(DELAY_33MS);
            check_wr_finish(1, "S1.6: after burst3 (finishes again on new buffer)");
            check_wr_ptr(2, "S1.7: wr_ptr incremented to 2");

            $display("  [DONE] Scenario %0d complete", scenario_id);
        end
    endtask

    //=============================================================================
    // Scenario 2: WR端连续写入
    // 复位dut, 每隔33ms 输入3个axi地址事务，中间一次为WR端写入完成时访问的地址, 持续三次
    //=============================================================================
    task scenario_2;
        begin
            integer i;
            scenario_id = 2;
            $display("");
            $display("========================================");
            $display("  Scenario %0d: WR Continuous Write (3x)", scenario_id);
            $display("========================================");

            reset_dut();

            for (i = 0; i < 3; i = i + 1) begin
                send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
                check_wr_finish(1, $sformatf("S2.%0d: wr_finish after burst2 (iter %0d)", i*3+1, i));
                check_wr_ptr(i+1, $sformatf("S2.%0d: wr_ptr=%0d after iter %0d", i*3+2, i+1, i));
            end

            check_wr_full(0, "S2.final: not full after 3 completes");

            $display("  [DONE] Scenario %0d complete", scenario_id);
        end
    endtask

    //=============================================================================
    // Scenario 3: WR端连续写写满
    // 复位dut, 每隔33ms 输入3个axi地址事务，中间一次为WR端写入完成时访问的地址,
    // 持续到WR端的wr_full信号有效
    //=============================================================================
    task scenario_3;
        begin
            integer wr_count;
            scenario_id = 3;
            $display("");
            $display("========================================");
            $display("  Scenario %0d: WR Continuous Write Until Full", scenario_id);
            $display("========================================");

            reset_dut();
            wr_count = 0;

            while (!wr_full_flag) begin
                send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
                wr_count = wr_count + 1;
                $display("  S3: write complete %0d (wr_full=%b, wr_ptr=%0d)", wr_count, wr_full_flag, wr_ptr_out);
            end

            check_wr_full(1, $sformatf("S3.final: wr_full asserted after %0d writes", wr_count));

            $display("  [DONE] Scenario %0d: reached full after %0d write completions", scenario_id, wr_count);
        end
    endtask

    //=============================================================================
    // Scenario 4: RD_1端单次完成写入
    // 复位dut, 输入3个axi地址读事务，其中中间一次为RD_1端写入完成时访问的地址
    //=============================================================================
    task scenario_4;
        begin
            scenario_id = 4;
            $display("");
            $display("========================================");
            $display("  Scenario %0d: RD_1 Single Read Complete", scenario_id);
            $display("========================================");

            reset_dut();

            // First need to write data so RD has something to read
            send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            #(DELAY_10MS);

            check_rd_empty(0, 1, "S4.0: rd[0] empty after reset + 1 write");

            send_rd_addr_set(0, AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);

            check_rd_finish(0, 0, "S4.1: after burst1 (no finish)");
            #(DELAY_33MS);
            check_rd_finish(0, 0, "S4.2: delay after burst1");
            #(CLK_PERIOD);
            check_rd_finish(0, 1, "S4.3: after burst2 (finish triggered)");
            check_rd_ptr(0, 1, "S4.4: rd[0]_ptr incremented");

            $display("  [DONE] Scenario %0d complete", scenario_id);
        end
    endtask

    //=============================================================================
    // Scenario 5: RD_1端连续读取
    // 复位dut, 每隔33ms 输入3个axi地址读事务，中间一次为RD_1端读取完成时访问的地址, 持续三次
    //=============================================================================
    task scenario_5;
        begin
            integer i;
            scenario_id = 5;
            $display("");
            $display("========================================");
            $display("  Scenario %0d: RD_1 Continuous Read (3x)", scenario_id);
            $display("========================================");

            reset_dut();

            // Write data first (3 writes to fill 3 buffers for 3 reads)
            for (i = 0; i < 3; i = i + 1) begin
                send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            end
            #(DELAY_10MS);

            check_rd_empty(0, 0, "S5.0: rd[0] not empty after 3 writes");

            for (i = 0; i < 3; i = i + 1) begin
                send_rd_addr_set(0, AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
                check_rd_finish(0, 1, $sformatf("S5.%0d: rd[0] finish (iter %0d)", i*2, i));
                check_rd_ptr(0, i+1, $sformatf("S5.%0d: rd[0]_ptr=%0d", i*2+1, i+1));
            end

            $display("  [DONE] Scenario %0d complete", scenario_id);
        end
    endtask

    //=============================================================================
    // Scenario 6: RD_1端连续读取空
    // 复位dut, 每隔33ms 输入3个axi地址事务(WR)，中间一次为WR端写入完成时访问的地址, 持续三次
    // 完成后，等待10ms, 每隔33ms 输入3个axi地址读事务，中间一次为RD_1端读取完成时访问的地址,
    // 持续到RD_1端的rd_empty信号有效
    //=============================================================================
    task scenario_6;
        begin
            integer i;
            scenario_id = 6;
            $display("");
            $display("========================================");
            $display("  Scenario %0d: RD_1 Continuous Read Until Empty", scenario_id);
            $display("========================================");

            reset_dut();

            // Write 3 times to fill buffers
            for (i = 0; i < 3; i = i + 1) begin
                send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            end
            #(DELAY_10MS);

            check_rd_empty(0, 0, "S6.0: rd[0] not empty after writes");

            // Read until empty
            wait_rd_empty(0);

            check_rd_empty(0, 1, "S6.final: rd[0] empty");

            $display("  [DONE] Scenario %0d complete", scenario_id);
        end
    endtask

    //=============================================================================
    // Scenario 7: RD_2端单次完成写入
    // 复位dut, 输入3个axi地址读事务，其中中间一次为RD_2端写入完成时访问的地址
    //=============================================================================
    task scenario_7;
        begin
            scenario_id = 7;
            $display("");
            $display("========================================");
            $display("  Scenario %0d: RD_2 Single Read Complete", scenario_id);
            $display("========================================");

            reset_dut();

            send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            #(DELAY_10MS);

            check_rd_empty(1, 1, "S7.0: rd[1] status after 1 write");

            send_rd_addr_set(1, AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);

            check_rd_finish(1, 0, "S7.1: after burst1 (no finish)");
            #(DELAY_33MS);
            check_rd_finish(1, 0, "S7.2: delay after burst1");
            #(CLK_PERIOD);
            check_rd_finish(1, 1, "S7.3: after burst2 (finish triggered)");
            check_rd_ptr(1, 1, "S7.4: rd[1]_ptr incremented");

            $display("  [DONE] Scenario %0d complete", scenario_id);
        end
    endtask

    //=============================================================================
    // Scenario 8: RD_2端连续读取
    // 复位dut, 每隔33ms 输入3个axi地址读事务，中间一次为RD_2端读取完成时访问的地址, 持续三次
    //=============================================================================
    task scenario_8;
        begin
            integer i;
            scenario_id = 8;
            $display("");
            $display("========================================");
            $display("  Scenario %0d: RD_2 Continuous Read (3x)", scenario_id);
            $display("========================================");

            reset_dut();

            for (i = 0; i < 3; i = i + 1) begin
                send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            end
            #(DELAY_10MS);

            for (i = 0; i < 3; i = i + 1) begin
                send_rd_addr_set(1, AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
                check_rd_finish(1, 1, $sformatf("S8.%0d: rd[1] finish (iter %0d)", i*2, i));
                check_rd_ptr(1, i+1, $sformatf("S8.%0d: rd[1]_ptr=%0d", i*2+1, i+1));
            end

            $display("  [DONE] Scenario %0d complete", scenario_id);
        end
    endtask

    //=============================================================================
    // Scenario 9: RD_2端连续读取空
    // 复位dut, 每隔33ms 输入3个axi地址事务(WR), 持续三次
    // 完成后等待10ms, 每隔33ms 输入3个axi地址读事务(RD_2), 持续到rd_empty
    //=============================================================================
    task scenario_9;
        begin
            integer i;
            scenario_id = 9;
            $display("");
            $display("========================================");
            $display("  Scenario %0d: RD_2 Continuous Read Until Empty", scenario_id);
            $display("========================================");

            reset_dut();

            for (i = 0; i < 3; i = i + 1) begin
                send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            end
            #(DELAY_10MS);

            check_rd_empty(1, 0, "S9.0: rd[1] not empty after writes");

            wait_rd_empty(1);

            check_rd_empty(1, 1, "S9.final: rd[1] empty");

            $display("  [DONE] Scenario %0d complete", scenario_id);
        end
    endtask

    //=============================================================================
    // Scenario 10: RD_1端和RD_2端同时单次读取
    // 复位dut, 每隔33ms 输入3个axi地址事务(WR), 持续三次
    // 完成后等待10ms, RD_1和RD_2端各输入3个axi地址读事务，同时读取完成
    //=============================================================================
    task scenario_10;
        begin
            integer i;
            scenario_id = 10;
            $display("");
            $display("========================================");
            $display("  Scenario %0d: RD_1 + RD_2 Simultaneous Single Read", scenario_id);
            $display("========================================");

            reset_dut();

            for (i = 0; i < 3; i = i + 1) begin
                send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            end
            #(DELAY_10MS);

            // Send RD_1 address set
            send_rd_addr_set(0, AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);

            check_rd_finish(0, 1, "S10.1: rd[0] finish after burst2");
            check_rd_ptr(0, 1, "S10.2: rd[0]_ptr=1");

            // Send RD_2 address set
            send_rd_addr_set(1, AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);

            check_rd_finish(1, 1, "S10.3: rd[1] finish after burst2");
            check_rd_ptr(1, 1, "S10.4: rd[1]_ptr=1");

            $display("  [DONE] Scenario %0d complete", scenario_id);
        end
    endtask

    //=============================================================================
    // Scenario 11: RD_1端和RD_2端同时连续读取
    // 复位dut, WR连续3次, 等待10ms, RD_1和RD_2同时连续读取3次
    //=============================================================================
    task scenario_11;
        begin
            integer i;
            scenario_id = 11;
            $display("");
            $display("========================================");
            $display("  Scenario %0d: RD_1 + RD_2 Simultaneous Continuous Read", scenario_id);
            $display("========================================");

            reset_dut();

            for (i = 0; i < 3; i = i + 1) begin
                send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            end
            #(DELAY_10MS);

            for (i = 0; i < 3; i = i + 1) begin
                send_rd_addr_set(0, AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
                send_rd_addr_set(1, AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
                check_rd_finish(0, 1, $sformatf("S11.%0d: rd[0] finish iter %0d", i*3, i));
                check_rd_finish(1, 1, $sformatf("S11.%0d: rd[1] finish iter %0d", i*3+1, i));
                check_rd_ptr(0, i+1, $sformatf("S11.%0d: rd[0]_ptr=%0d", i*3+2, i+1));
                check_rd_ptr(1, i+1, $sformatf("S11.%0d: rd[1]_ptr=%0d", i*3+3, i+1));
            end

            $display("  [DONE] Scenario %0d complete", scenario_id);
        end
    endtask

    //=============================================================================
    // Scenario 12: RD_1端和RD_2端同时连续读取空
    // 复位dut, WR连续3次, 等待10ms, RD_1和RD_2同时连续读取直到空
    //=============================================================================
    task scenario_12;
        begin
            integer i;
            scenario_id = 12;
            $display("");
            $display("========================================");
            $display("  Scenario %0d: RD_1 + RD_2 Simultaneous Read Until Empty", scenario_id);
            $display("========================================");

            reset_dut();

            // Need more writes for both RD users to read
            for (i = 0; i < 6; i = i + 1) begin
                send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            end
            #(DELAY_10MS);

            wait_rd_empty_both();

            check_rd_empty(0, 1, "S12.final: rd[0] empty");
            check_rd_empty(1, 1, "S12.final: rd[1] empty");

            $display("  [DONE] Scenario %0d complete", scenario_id);
        end
    endtask

    //=============================================================================
    // Scenario 13: WR端完成写入一次，RD_1端完成读取一次
    // 复位dut
    // 13.1: 先WR完成，后RD_1完成
    // 13.2: 先RD_1完成，后WR完成
    //=============================================================================
    task scenario_13;
        begin
            scenario_id = 13;
            $display("");
            $display("========================================");
            $display("  Scenario %0d: WR Complete + RD_1 Complete", scenario_id);
            $display("========================================");

            // 13.1: WR first, then RD_1
            $display("  --- Sub-scenario 13.1: WR -> RD_1 ---");
            reset_dut();

            send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            check_wr_finish(1, "S13.1.1: wr_finish after burst2");
            check_wr_ptr(1, "S13.1.2: wr_ptr=1");

            send_rd_addr_set(0, AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            check_rd_finish(0, 1, "S13.1.3: rd[0] finish after burst2");
            check_rd_ptr(0, 1, "S13.1.4: rd[0]_ptr=1");

            // 13.2: RD_1 first, then WR
            $display("  --- Sub-scenario 13.2: RD_1 -> WR ---");
            reset_dut();

            // First write data so RD can read
            send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            #(DELAY_10MS);

            send_rd_addr_set(0, AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            check_rd_finish(0, 1, "S13.2.1: rd[0] finish");

            send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            check_wr_finish(1, "S13.2.2: wr_finish");

            $display("  [DONE] Scenario %0d complete", scenario_id);
        end
    endtask

    //=============================================================================
    // Scenario 14: WR端完成写入一次，RD_2端完成读取一次
    // 复位dut
    // 14.1: 先WR完成，后RD_2完成
    // 14.2: 先RD_2完成，后WR完成
    //=============================================================================
    task scenario_14;
        begin
            scenario_id = 14;
            $display("");
            $display("========================================");
            $display("  Scenario %0d: WR Complete + RD_2 Complete", scenario_id);
            $display("========================================");

            // 14.1: WR first, then RD_2
            $display("  --- Sub-scenario 14.1: WR -> RD_2 ---");
            reset_dut();

            send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            check_wr_finish(1, "S14.1.1: wr_finish");
            check_wr_ptr(1, "S14.1.2: wr_ptr=1");

            send_rd_addr_set(1, AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            check_rd_finish(1, 1, "S14.1.3: rd[1] finish");
            check_rd_ptr(1, 1, "S14.1.4: rd[1]_ptr=1");

            // 14.2: RD_2 first, then WR
            $display("  --- Sub-scenario 14.2: RD_2 -> WR ---");
            reset_dut();

            send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            #(DELAY_10MS);

            send_rd_addr_set(1, AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            check_rd_finish(1, 1, "S14.2.1: rd[1] finish");

            send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
            check_wr_finish(1, "S14.2.2: wr_finish");

            $display("  [DONE] Scenario %0d complete", scenario_id);
        end
    endtask

    //=============================================================================
    // Scenario 15: WR端连续写入和RD_1端连续读取
    // 复位dut, WR端间隔随机(30~40ms), 持续三次, 延迟(10~20ms),
    // RD_1端间隔随机(30~40ms), 持续三次
    //=============================================================================
    task scenario_15;
        begin
            integer i;
            integer wr_delay;
            integer rd_delay;
            integer inter_delay;
            scenario_id = 15;
            $display("");
            $display("========================================");
            $display("  Scenario %0d: WR Continuous + RD_1 Continuous (Random)", scenario_id);
            $display("========================================");

            reset_dut();

            // WR: 3 times with random delay 30~40ms
            for (i = 0; i < 3; i = i + 1) begin
                send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
                check_wr_finish(1, $sformatf("S15.%0d: wr_finish iter %0d", i*2, i));
                wr_delay = rand_range(DELAY_30MS, DELAY_40MS);
                $display("  S15: wr delay = %0d ns", wr_delay);
                #(wr_delay);
            end

            // Random inter-delay 10~20ms
            inter_delay = rand_range(DELAY_10MS, DELAY_20MS);
            $display("  S15: inter delay = %0d ns", inter_delay);
            #(inter_delay);

            // RD_1: 3 times with random delay 30~40ms
            for (i = 0; i < 3; i = i + 1) begin
                send_rd_addr_set(0, AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
                check_rd_finish(0, 1, $sformatf("S15.%0d: rd[0] finish iter %0d", i*2+6, i));
                rd_delay = rand_range(DELAY_30MS, DELAY_40MS);
                $display("  S15: rd delay = %0d ns", rd_delay);
                #(rd_delay);
            end

            $display("  [DONE] Scenario %0d complete", scenario_id);
        end
    endtask

    //=============================================================================
    // Scenario 16: WR端连续写入和RD_2端连续读取
    // 同Scenario 15，但使用RD_2
    //=============================================================================
    task scenario_16;
        begin
            integer i;
            integer wr_delay;
            integer rd_delay;
            integer inter_delay;
            scenario_id = 16;
            $display("");
            $display("========================================");
            $display("  Scenario %0d: WR Continuous + RD_2 Continuous (Random)", scenario_id);
            $display("========================================");

            reset_dut();

            for (i = 0; i < 3; i = i + 1) begin
                send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
                check_wr_finish(1, $sformatf("S16.%0d: wr_finish iter %0d", i*2, i));
                wr_delay = rand_range(DELAY_30MS, DELAY_40MS);
                #(wr_delay);
            end

            inter_delay = rand_range(DELAY_10MS, DELAY_20MS);
            #(inter_delay);

            for (i = 0; i < 3; i = i + 1) begin
                send_rd_addr_set(1, AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
                check_rd_finish(1, 1, $sformatf("S16.%0d: rd[1] finish iter %0d", i*2+6, i));
                rd_delay = rand_range(DELAY_30MS, DELAY_40MS);
                #(rd_delay);
            end

            $display("  [DONE] Scenario %0d complete", scenario_id);
        end
    endtask

    //=============================================================================
    // Scenario 17: WR端连续写入和RD_1端连续读取满/空
    // 复位dut, WR连续写入直到wr_full, 延迟10~20ms, RD_1连续读取直到rd_empty
    //=============================================================================
    task scenario_17;
        begin
            integer inter_delay;
            integer wr_count;
            integer rd_count;
            scenario_id = 17;
            $display("");
            $display("========================================");
            $display("  Scenario %0d: WR Fill + RD_1 Drain", scenario_id);
            $display("========================================");

            reset_dut();
            wr_count = 0;

            // WR until full
            while (!wr_full_flag) begin
                send_wr_addr_set(AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
                wr_count = wr_count + 1;
                $display("  S17: write complete %0d (wr_full=%b)", wr_count, wr_full_flag);
            end

            check_wr_full(1, $sformatf("S17.1: wr_full after %0d writes", wr_count));

            // Random inter-delay 10~20ms
            inter_delay = rand_range(DELAY_10MS, DELAY_20MS);
            #(inter_delay);

            // RD until empty
            rd_count = 0;
            while (!rd_empty_flag[0]) begin
                send_rd_addr_set(0, AXI_BURST_LEN, AXI_BURST_LEN, AXI_BURST_LEN);
                rd_count = rd_count + 1;
                $display("  S17: read complete %0d (rd_empty=%b)", rd_count, rd_empty_flag[0]);
            end

            check_rd_empty(0, 1, $sformatf("S17.2: rd[0] empty after %0d reads", rd_count));

            $display("  S17 summary: %0d writes to full, %0d reads to empty", wr_count, rd_count);
            $display("  [DONE] Scenario %0d complete", scenario_id);
        end
    endtask

endmodule
