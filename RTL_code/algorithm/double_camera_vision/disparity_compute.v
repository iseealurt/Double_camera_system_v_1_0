//cmr1 为左摄像头输入，cmr2为右摄像头输入，本模块计算右视差图
//输入：两个摄像头的census序列，要求左目先输入，右目后输入，两摄像头同一行的census序列输入间隔不得少于50个时钟周期，推荐大于60个时钟周期
//输出：
//  a. int8格式的视差，范围为0 ~ 47 or invalid ，当符号位为1时，表示该像素的视差值无效
//  b. int8格式的置信度，范围为0-24
module disparity_compute#(
    parameter   IMG_WIDTH       =   640     ,
    parameter   IMG_HEIGHT      =   480     ,
    parameter   MAX_MATCH_DEPTH =   48      ,
    parameter   CENSUS_WIDTH    =   24      ,  
    parameter   DISPARITY_WIDTH =   8       ,
    parameter   CONFIDENCE_WIDTH=   8       ,
    parameter   CONFIDENCE_THRE =   1       ,
    parameter   SGM_LR_WIDTH    =   12      ,
    parameter   SGM_INVALID_COST=   24      
)(
    input   wire                            clk                 ,
    input   wire                            rst_n               ,

    input   wire                            per_cmr1_vsync      ,
    input   wire                            per_cmr1_href       ,
    input   wire    [CENSUS_WIDTH-1:0]      per_cmr1_census     ,

    input   wire                            per_cmr2_vsync      ,
    input   wire                            per_cmr2_href       ,
    input   wire    [CENSUS_WIDTH-1:0]      per_cmr2_census     ,

    output  wire                            disparity_vsync     ,
    output  wire                            disparity_href      ,
    output  wire    [CONFIDENCE_WIDTH-1:0]  disparty_confidence ,
    output  wire    [DISPARITY_WIDTH-1:0]   disparity
);
    //由于使用右摄像头作为基准匹配左摄像头，因此需要在左摄像头完成一行的census序列输入后，拉高dmax个周期的读取信号，来把数据完全导入到匹配窗口中
    //即有图有效列数:0 ~ WIDTH-Dmax-1
    reg     per_cmr1_href_dly;
    always @(posedge clk) begin
        if(!rst_n) begin
            per_cmr1_href_dly <= 1'b0;
        end
        else begin
            per_cmr1_href_dly <= per_cmr1_href;
        end
    end
    wire    per_cmr1_href_posedge;
    wire    per_cmr1_href_negedge;
    assign per_cmr1_href_negedge =  !per_cmr1_href && per_cmr1_href_dly;
    localparam PRE_RD_CNT_WIDTH = $clog2(MAX_MATCH_DEPTH);
    reg     [PRE_RD_CNT_WIDTH-1:0]  pre_rd_cnt;
    reg                             cmr1_census_fifo_pre_rd_en;

    always @(posedge clk) begin
        if(!rst_n) begin
            cmr1_census_fifo_pre_rd_en <= 1'b0;
            pre_rd_cnt <= {MAX_MATCH_DEPTH{1'b0}};
        end
        else begin
            if (cmr1_census_fifo_pre_rd_en) begin
                cmr1_census_fifo_pre_rd_en <= pre_rd_cnt == MAX_MATCH_DEPTH - 1 ? 1'b0 : 1'b1;
            end
            else if(per_cmr1_href_negedge) begin
                cmr1_census_fifo_pre_rd_en <= 1'b1;
            end

            if(per_cmr1_href_negedge) begin
                pre_rd_cnt <= {MAX_MATCH_DEPTH{1'b0}};
            end
            else if(cmr1_census_fifo_pre_rd_en) begin
                pre_rd_cnt <= pre_rd_cnt == MAX_MATCH_DEPTH - 1 ? MAX_MATCH_DEPTH - 1 : pre_rd_cnt + 1;
            end
        end
    end

    //cmr1 的census序列输入到FIFO中，等待cmr2的href有效时同步输出
    // fifo 行为控制信号
    wire    [CENSUS_WIDTH-1:0]              cmr1_census_fifo_din , cmr1_census_fifo_dout;
    wire                                    cmr1_census_fifo_wr_en , cmr1_census_fifo_rd_en;
    wire                                    cmr1_census_fifo_empty , cmr1_census_fifo_full;
    wire                                    cmr1_census_fifo_rst;

    assign cmr1_census_fifo_rst = !per_cmr1_vsync;
    assign cmr1_census_fifo_wr_en = per_cmr1_href && !cmr1_census_fifo_full;
    assign cmr1_census_fifo_rd_en = (cmr1_census_fifo_pre_rd_en || per_cmr2_href) && !cmr1_census_fifo_empty; 
    assign cmr1_census_fifo_din = per_cmr1_census;
    
    ///////////////////////////////////////
    // 待实例化的FIFO IP 
    // IP 例化要点： 24位位宽，1024深度 ，消耗三个DRK9K，开启输出寄存，下降沿输出，降低时序要求
    sgm_hamming_fifo cmr1_sgm_hamming_fifo (
        .clk            (clk                    ),  // input
        .rst            (!rst_n                 ),  // input
        .wr_en          (cmr1_census_fifo_wr_en ),  // input
        .wr_data        (cmr1_census_fifo_din   ),  // input [23:0]
        .wr_full        (cmr1_census_fifo_full  ),  // output
        .almost_full    (), // output
        .rd_en          (cmr1_census_fifo_rd_en ),  // input
        .rd_data        (cmr1_census_fifo_dout  ),  // output [23:0]
        .rd_empty       (cmr1_census_fifo_empty ),  // output
        .almost_empty   () // output
    );
    ///////////////////////////////////////

    // fifo 的数据传播有延迟，因此需要对cmr2_href打一拍再用于控制，后续算法流水线也有N个周期需要href的控制，所以在这里进行若干周期的延迟
    localparam HREF_MAX_DLY_CYCLE = 24;
    reg [HREF_MAX_DLY_CYCLE-1:0] per_cmr2_href_dly;
    reg [HREF_MAX_DLY_CYCLE-1:0] per_cmr2_vsync_dly;
    always@(posedge clk) begin : cmr2_href_delay
        if(!rst_n) begin
            per_cmr2_href_dly <= {{HREF_MAX_DLY_CYCLE{1'b0}}};
            per_cmr2_vsync_dly <= {{HREF_MAX_DLY_CYCLE{1'b0}}};
        end
        else begin
            per_cmr2_href_dly <= {per_cmr2_href_dly[HREF_MAX_DLY_CYCLE-2:0],per_cmr2_href};
            per_cmr2_vsync_dly <= {per_cmr2_vsync_dly[HREF_MAX_DLY_CYCLE-2:0],per_cmr2_vsync};
        end
    end
    // stage 0: 把cmr1_census_fifo内的数据导入到Hamming distance的计算窗口内
    reg [CENSUS_WIDTH-1:0]  xor_window[MAX_MATCH_DEPTH-1:0];
    integer i;
    always@(posedge clk) begin : xor_window_generate
        if(!rst_n) begin
            for(i=0;i<MAX_MATCH_DEPTH;i=i+1) begin
                xor_window[i] <= {CENSUS_WIDTH{1'b0}};
            end
        end
        else begin
            if(per_cmr2_href_dly[0]) begin
                xor_window[0] <= cmr1_census_fifo_dout;
                for(i=1;i<MAX_MATCH_DEPTH;i=i+1) begin
                    xor_window[i] <= xor_window[i-1];
                end
            end
        end
    end

    //stage 1: 将cmr2的原始数据打两拍，与匹配窗口内的census序列对齐，进行异或运算
    reg [CENSUS_WIDTH-1:0] cmr2_census_dly[1:0];
    always@(posedge clk) begin : cmr2_census_delay
        if(!rst_n) begin
            cmr2_census_dly[0] <= {{CENSUS_WIDTH{1'b0}}};
            cmr2_census_dly[1] <= {{CENSUS_WIDTH{1'b0}}};
        end
        else begin
            if(per_cmr2_href) begin 
                cmr2_census_dly[0] <= per_cmr2_census; 
                //mr2_census_dly[0] <= 24'h00_ffff; 
            end      
            if(per_cmr2_href_dly[0]) begin cmr2_census_dly[1] <= cmr2_census_dly[0]; end
        end
    end

    reg [CENSUS_WIDTH-1:0] xor_outcome[MAX_MATCH_DEPTH-1:0];
    always@(posedge clk) begin : xor_computation
        if(!rst_n) begin
            for(i=0;i<MAX_MATCH_DEPTH;i=i+1) begin
                xor_outcome[i] <= {CENSUS_WIDTH{1'b0}};
            end
        end
        else begin
            if(per_cmr2_href_dly[1]) begin
                for(i=0;i<MAX_MATCH_DEPTH;i=i+1) begin
                    xor_outcome[i] <=  xor_window[i] ^ cmr2_census_dly[1];
                end
            end
        end
    end

    // stage 2: 对24位的census结果进行基于LUT6的第一次popcount
    localparam POPCOUNT_REG_NUM = CENSUS_WIDTH / 6 * MAX_MATCH_DEPTH; 
    localparam GROUP_PER_DISP = CENSUS_WIDTH / 6;
    reg     [2:0] popcount_s1[POPCOUNT_REG_NUM-1:0];
    integer j;
    always @(posedge clk) begin : hamming_popcount_s1
        if(!rst_n) begin
            for(i = 0; i < POPCOUNT_REG_NUM; i = i + 1) begin
                popcount_s1[i] <= 3'd0;
            end
        end
        else begin
            if(per_cmr2_href_dly[2]) begin
                for(i = 0; i < MAX_MATCH_DEPTH; i = i + 1) begin
                    for(j = 0; j < GROUP_PER_DISP; j = j + 1) begin
                        // 取6bit
                        case (xor_outcome[i][j*6 +: 6])
                            6'b000000: popcount_s1[i*GROUP_PER_DISP + j] <= 3'd0;
                            6'b000001,
                            6'b000010,
                            6'b000100,
                            6'b001000,
                            6'b010000,
                            6'b100000: popcount_s1[i*GROUP_PER_DISP + j] <= 3'd1;

                            6'b000011,
                            6'b000101,
                            6'b000110,
                            6'b001001,
                            6'b001010,
                            6'b001100,
                            6'b010001,
                            6'b010010,
                            6'b010100,
                            6'b011000,
                            6'b100001,
                            6'b100010,
                            6'b100100,
                            6'b101000,
                            6'b110000: popcount_s1[i*GROUP_PER_DISP + j] <= 3'd2;

                            6'b000111,
                            6'b001011,
                            6'b001101,
                            6'b001110,
                            6'b010011,
                            6'b010101,
                            6'b010110,
                            6'b011001,
                            6'b011010,
                            6'b011100,
                            6'b100011,
                            6'b100101,
                            6'b100110,
                            6'b101001,
                            6'b101010,
                            6'b101100,
                            6'b110001,
                            6'b110010,
                            6'b110100,
                            6'b111000: popcount_s1[i*GROUP_PER_DISP + j] <= 3'd3;

                            6'b001111,
                            6'b010111,
                            6'b011011,
                            6'b011101,
                            6'b011110,
                            6'b100111,
                            6'b101011,
                            6'b101101,
                            6'b101110,
                            6'b110011,
                            6'b110101,
                            6'b110110,
                            6'b111001,
                            6'b111010,
                            6'b111100: popcount_s1[i*GROUP_PER_DISP + j] <= 3'd4;

                            6'b011111,
                            6'b101111,
                            6'b110111,
                            6'b111011,
                            6'b111101,
                            6'b111110: popcount_s1[i*GROUP_PER_DISP + j] <= 3'd5;

                            6'b111111: popcount_s1[i*GROUP_PER_DISP + j] <= 3'd6;

                            default: popcount_s1[i*GROUP_PER_DISP + j] <= 3'd0;
                        endcase
                    end
                end
            end
        end
    end

    // stage 3 : 初步计算有效代价的掩码；两两相加，进行第二次popcount，  
    // 列计数器和指示有效hamming距离的掩码控制信号的时序输出
    localparam COL_WIDTH = $clog2(IMG_WIDTH);
    reg [COL_WIDTH-1:0] cmr2_col_cnt;
    always@(posedge clk) begin
        if(!rst_n) begin
            cmr2_col_cnt <= {COL_WIDTH{1'b0}};
        end
        else begin
            if(!per_cmr2_href_dly[3] && per_cmr2_href_dly[4]) begin
                cmr2_col_cnt <= {COL_WIDTH{1'b0}};
            end
            else if(per_cmr2_href_dly[3]) begin
                cmr2_col_cnt <= cmr2_col_cnt + 1'b1;
                if(cmr2_col_cnt >= IMG_WIDTH) begin
                    $display("@ %0t , [ERROR] per_cmr2_href lasted too long for %0d cycles",$time,cmr2_col_cnt + 1);
                    $stop;
                end
            end          
        end
    end
    // 掩码的组合逻辑
    reg hamming_dist_valid_mask_pre[MAX_MATCH_DEPTH-1:0];
    always @(*) begin
        for(i=0; i<MAX_MATCH_DEPTH; i=i+1) begin
            hamming_dist_valid_mask_pre[i] = (cmr2_col_cnt <= IMG_WIDTH - i);
        end
    end

    //两两相加，进行第二次popcount，
    localparam HAMMING_WIDTH = $clog2(CENSUS_WIDTH + 1);
    reg [HAMMING_WIDTH-1:0] popcount_s2[MAX_MATCH_DEPTH-1:0][(GROUP_PER_DISP/2)-1:0];
    always @(posedge clk) begin
        if(!rst_n) begin
            for(i = 0; i < MAX_MATCH_DEPTH; i = i + 1)
                for(j = 0; j < GROUP_PER_DISP/2; j = j + 1)
                    popcount_s2[i][j] <= 0;
        end
        else begin
            if(per_cmr2_href_dly[3]) begin
                for(i = 0; i < MAX_MATCH_DEPTH; i = i + 1) begin
                    for(j = 0; j < GROUP_PER_DISP/2; j = j + 1) begin
                        popcount_s2[i][j] <= popcount_s1[i*GROUP_PER_DISP + 2*j] + popcount_s1[i*GROUP_PER_DISP + 2*j + 1];
                    end
                end
            end 
        end
    end

    // stage 4 : 两两相加，得到hamming_dist
    reg [HAMMING_WIDTH-1:0] hamming_dist[MAX_MATCH_DEPTH-1:0];
    reg [HAMMING_WIDTH-1:0] hamming_dist_comb[MAX_MATCH_DEPTH-1:0];

    always @(*) begin : hamming_dist_compute_comb
        for(i=0;i<MAX_MATCH_DEPTH;i=i+1) begin
            hamming_dist_comb[i] = hamming_dist_valid_mask_pre[i] ? popcount_s2[i][0] + popcount_s2[i][1] : SGM_INVALID_COST;
        end
    end

    // ============================================================
    // Cost test mode
    //   0 : 使用真实 hamming_dist_comb
    //   1 : 固定 d0
    //   2 : 阶跃 d0
    //   3 : 动态 d0 = col % MAX_MATCH_DEPTH
    // ============================================================

    localparam integer COST_TEST_MODE = 0;

    localparam integer TEST_D0        = 20;

    localparam integer TEST_D0_LEFT   = 10;
    localparam integer TEST_D0_RIGHT  = 30;
    localparam integer TEST_STEP_X    = 320;

    localparam [HAMMING_WIDTH-1:0] TEST_COST_LOW  = {HAMMING_WIDTH{1'b0}};
    localparam [HAMMING_WIDTH-1:0] TEST_COST_HIGH = SGM_INVALID_COST;

    reg [DISPARITY_WIDTH-1:0] test_d0;

    always @(*) begin
        case(COST_TEST_MODE)
            1: begin
                test_d0 = TEST_D0;
            end

            2: begin
                if(cmr2_col_cnt < TEST_STEP_X) begin
                    test_d0 = TEST_D0_LEFT;
                end
                else begin
                    test_d0 = TEST_D0_RIGHT;
                end
            end

            3: begin
                test_d0 = cmr2_col_cnt % MAX_MATCH_DEPTH;
            end

            default: begin
                test_d0 = TEST_D0;
            end
        endcase
    end

    always @(posedge clk) begin : hamming_dist_compute
        if(!rst_n) begin
            for(i = 0; i < MAX_MATCH_DEPTH; i = i + 1) begin
                hamming_dist[i] <= {HAMMING_WIDTH{1'b1}};
            end
        end
        else begin
            if(per_cmr2_href_dly[4]) begin
                for(i = 0; i < MAX_MATCH_DEPTH; i = i + 1) begin
                    if(COST_TEST_MODE != 0) begin
                        hamming_dist[i] <= (i == test_d0) ? TEST_COST_LOW : TEST_COST_HIGH;
                    end
                    else begin
                        hamming_dist[i] <= hamming_dist_comb[MAX_MATCH_DEPTH-1-i];
                    end
                end
            end
        end
    end

    reg     [DISPARITY_WIDTH-1:0] best_disparity,best_disparity_dly;
    reg     [SGM_LR_WIDTH-1:0] Lr_min;
    reg     [SGM_LR_WIDTH-1:0] Lr_second_min;
    reg     [CONFIDENCE_WIDTH-1:0] confidence_reg;
    // 代价聚合
    generate
        // stage 5 ~ 10: 6级比较树实现WTA策略
        begin : WTA_compare_tree
            // stage 5 : 第一级比较树
            genvar tree_cnt0;
            reg [SGM_LR_WIDTH-1:0] Lr_min_compare_tree_temp0[MAX_MATCH_DEPTH/2-1:0]; // 24*12 = 288 D-triggers
            reg [SGM_LR_WIDTH-1:0] Lr_second_min_compare_tree_temp0[MAX_MATCH_DEPTH/2-1:0];
            reg [DISPARITY_WIDTH-1:0] best_d_temp0[MAX_MATCH_DEPTH/2-1:0];
            for(tree_cnt0=0; tree_cnt0<MAX_MATCH_DEPTH/2; tree_cnt0=tree_cnt0+1) begin
                always @(posedge clk) begin :  Lr_min_compare_tree_stg1
                    if(!rst_n) begin
                        Lr_min_compare_tree_temp0[tree_cnt0] <= {SGM_LR_WIDTH{1'B1}};
                        Lr_second_min_compare_tree_temp0[tree_cnt0] <= {SGM_LR_WIDTH{1'B1}};
                        best_d_temp0[tree_cnt0] <= {DISPARITY_WIDTH{1'b0}};
                    end
                    else begin
                        if(per_cmr2_href_dly[5]) begin
                            Lr_min_compare_tree_temp0[tree_cnt0] <= hamming_dist[2*tree_cnt0] <= hamming_dist[2*tree_cnt0+1] ? hamming_dist[2*tree_cnt0] : hamming_dist[2*tree_cnt0+1];
                            Lr_second_min_compare_tree_temp0[tree_cnt0] <= hamming_dist[2*tree_cnt0] <= hamming_dist[2*tree_cnt0+1] ? hamming_dist[2*tree_cnt0+1] : hamming_dist[2*tree_cnt0];
                            best_d_temp0[tree_cnt0] <= hamming_dist[2*tree_cnt0] <= hamming_dist[2*tree_cnt0+1] ? 2*tree_cnt0 : 2*tree_cnt0+1;
                        end
                    end
                end  
            end

            // stage 6 : 第二级比较树
            genvar tree_cnt1;
            reg [SGM_LR_WIDTH-1:0] Lr_min_compare_tree_temp1[MAX_MATCH_DEPTH/4-1:0]; // 12*12 = 144 D-triggers
            reg [SGM_LR_WIDTH-1:0] Lr_second_min_compare_tree_temp1[MAX_MATCH_DEPTH/4-1:0];
            reg [DISPARITY_WIDTH-1:0] best_d_temp1[MAX_MATCH_DEPTH/4-1:0];
            for(tree_cnt1=0; tree_cnt1<MAX_MATCH_DEPTH/4; tree_cnt1=tree_cnt1+1) begin
                wire [SGM_LR_WIDTH-1:0] stg6_max_lr;
                wire [SGM_LR_WIDTH-1:0] stg6_min_2nd;
                assign stg6_max_lr = Lr_min_compare_tree_temp0[2*tree_cnt1] <= Lr_min_compare_tree_temp0[2*tree_cnt1+1] ?
                    Lr_min_compare_tree_temp0[2*tree_cnt1+1] : Lr_min_compare_tree_temp0[2*tree_cnt1];
                assign stg6_min_2nd = Lr_second_min_compare_tree_temp0[2*tree_cnt1] <= Lr_second_min_compare_tree_temp0[2*tree_cnt1+1] ?
                    Lr_second_min_compare_tree_temp0[2*tree_cnt1] : Lr_second_min_compare_tree_temp0[2*tree_cnt1+1];
                always @(posedge clk) begin :  Lr_min_compare_tree_stg2
                    if(!rst_n) begin
                        Lr_min_compare_tree_temp1[tree_cnt1] <= {SGM_LR_WIDTH{1'B1}};
                        Lr_second_min_compare_tree_temp1[tree_cnt1] <= {SGM_LR_WIDTH{1'B1}};
                        best_d_temp1[tree_cnt1] <= {DISPARITY_WIDTH{1'b0}};
                    end
                    else begin
                        if(per_cmr2_href_dly[6]) begin
                            Lr_min_compare_tree_temp1[tree_cnt1] <= Lr_min_compare_tree_temp0[2*tree_cnt1] <= Lr_min_compare_tree_temp0[2*tree_cnt1+1] ? Lr_min_compare_tree_temp0[2*tree_cnt1] : Lr_min_compare_tree_temp0[2*tree_cnt1+1];
                            Lr_second_min_compare_tree_temp1[tree_cnt1] <= stg6_max_lr <= stg6_min_2nd ? stg6_max_lr : stg6_min_2nd;
                            best_d_temp1[tree_cnt1] <= Lr_min_compare_tree_temp0[2*tree_cnt1] <= Lr_min_compare_tree_temp0[2*tree_cnt1+1] ? best_d_temp0[2*tree_cnt1] : best_d_temp0[2*tree_cnt1+1];
                        end
                    end
                end  
            end

            // stage 7 : 第三级比较树
            genvar tree_cnt2;
            reg [SGM_LR_WIDTH-1:0] Lr_min_compare_tree_temp2[MAX_MATCH_DEPTH/8-1:0]; // 6*12 = 72 D-triggers
            reg [SGM_LR_WIDTH-1:0] Lr_second_min_compare_tree_temp2[MAX_MATCH_DEPTH/8-1:0];
            reg [DISPARITY_WIDTH-1:0] best_d_temp2[MAX_MATCH_DEPTH/8-1:0];
            for(tree_cnt2=0; tree_cnt2<MAX_MATCH_DEPTH/8; tree_cnt2=tree_cnt2+1) begin
                wire [SGM_LR_WIDTH-1:0] stg7_max_lr;
                wire [SGM_LR_WIDTH-1:0] stg7_min_2nd;
                assign stg7_max_lr = Lr_min_compare_tree_temp1[2*tree_cnt2] <= Lr_min_compare_tree_temp1[2*tree_cnt2+1] ?
                    Lr_min_compare_tree_temp1[2*tree_cnt2+1] : Lr_min_compare_tree_temp1[2*tree_cnt2];
                assign stg7_min_2nd = Lr_second_min_compare_tree_temp1[2*tree_cnt2] <= Lr_second_min_compare_tree_temp1[2*tree_cnt2+1] ?
                    Lr_second_min_compare_tree_temp1[2*tree_cnt2] : Lr_second_min_compare_tree_temp1[2*tree_cnt2+1];
                always @(posedge clk) begin :  Lr_min_compare_tree_stg3
                    if(!rst_n) begin
                        Lr_min_compare_tree_temp2[tree_cnt2] <= {SGM_LR_WIDTH{1'B1}};
                        Lr_second_min_compare_tree_temp2[tree_cnt2] <= {SGM_LR_WIDTH{1'B1}};
                        best_d_temp2[tree_cnt2] <= {DISPARITY_WIDTH{1'b0}};
                    end
                    else begin
                        if(per_cmr2_href_dly[7]) begin
                            Lr_min_compare_tree_temp2[tree_cnt2] <= Lr_min_compare_tree_temp1[2*tree_cnt2] <= Lr_min_compare_tree_temp1[2*tree_cnt2+1] ? Lr_min_compare_tree_temp1[2*tree_cnt2] : Lr_min_compare_tree_temp1[2*tree_cnt2+1];
                            Lr_second_min_compare_tree_temp2[tree_cnt2] <= stg7_max_lr <= stg7_min_2nd ? stg7_max_lr : stg7_min_2nd;
                            best_d_temp2[tree_cnt2] <= Lr_min_compare_tree_temp1[2*tree_cnt2] <= Lr_min_compare_tree_temp1[2*tree_cnt2+1] ? best_d_temp1[2*tree_cnt2] : best_d_temp1[2*tree_cnt2+1];
                        end
                    end
                end  
            end

            // stage 8 : 第四级比较树
            genvar tree_cnt3;
            reg [SGM_LR_WIDTH-1:0] Lr_min_compare_tree_temp3[MAX_MATCH_DEPTH/16-1:0]; // 3*12 = 36 D-triggers
            reg [SGM_LR_WIDTH-1:0] Lr_second_min_compare_tree_temp3[MAX_MATCH_DEPTH/16-1:0];
            reg [DISPARITY_WIDTH-1:0] best_d_temp3[MAX_MATCH_DEPTH/16-1:0];
            for(tree_cnt3=0; tree_cnt3<MAX_MATCH_DEPTH/16; tree_cnt3=tree_cnt3+1) begin
                wire [SGM_LR_WIDTH-1:0] stg8_max_lr;
                wire [SGM_LR_WIDTH-1:0] stg8_min_2nd;
                assign stg8_max_lr = Lr_min_compare_tree_temp2[2*tree_cnt3] <= Lr_min_compare_tree_temp2[2*tree_cnt3+1] ?
                    Lr_min_compare_tree_temp2[2*tree_cnt3+1] : Lr_min_compare_tree_temp2[2*tree_cnt3];
                assign stg8_min_2nd = Lr_second_min_compare_tree_temp2[2*tree_cnt3] <= Lr_second_min_compare_tree_temp2[2*tree_cnt3+1] ?
                    Lr_second_min_compare_tree_temp2[2*tree_cnt3] : Lr_second_min_compare_tree_temp2[2*tree_cnt3+1];
                always @(posedge clk) begin :  Lr_min_compare_tree_stg4
                    if(!rst_n) begin
                        Lr_min_compare_tree_temp3[tree_cnt3] <= {SGM_LR_WIDTH{1'B1}};
                        Lr_second_min_compare_tree_temp3[tree_cnt3] <= {SGM_LR_WIDTH{1'B1}};
                        best_d_temp3[tree_cnt3] <= {DISPARITY_WIDTH{1'b0}};
                    end
                    else begin
                        if(per_cmr2_href_dly[8]) begin
                            Lr_min_compare_tree_temp3[tree_cnt3] <= Lr_min_compare_tree_temp2[2*tree_cnt3] <= Lr_min_compare_tree_temp2[2*tree_cnt3+1] ? Lr_min_compare_tree_temp2[2*tree_cnt3] : Lr_min_compare_tree_temp2[2*tree_cnt3+1];
                            Lr_second_min_compare_tree_temp3[tree_cnt3] <= stg8_max_lr <= stg8_min_2nd ? stg8_max_lr : stg8_min_2nd;
                            best_d_temp3[tree_cnt3] <= Lr_min_compare_tree_temp2[2*tree_cnt3] <= Lr_min_compare_tree_temp2[2*tree_cnt3+1] ? best_d_temp2[2*tree_cnt3] : best_d_temp2[2*tree_cnt3+1];
                        end
                    end
                end  
            end

            // stage 9 : 第五级比较树
            reg [SGM_LR_WIDTH-1:0] Lr_min_compare_tree_temp4[MAX_MATCH_DEPTH/16-2:0]; // 2*12 = 24 D-triggers
            reg [SGM_LR_WIDTH-1:0] Lr_second_min_compare_tree_temp4[MAX_MATCH_DEPTH/16-2:0];
            reg [DISPARITY_WIDTH-1:0] best_d_temp4[MAX_MATCH_DEPTH/16-2:0];
            wire [SGM_LR_WIDTH-1:0] stg9_max_lr;
            wire [SGM_LR_WIDTH-1:0] stg9_min_2nd;
            assign stg9_max_lr = Lr_min_compare_tree_temp3[0] <= Lr_min_compare_tree_temp3[1] ?
                Lr_min_compare_tree_temp3[1] : Lr_min_compare_tree_temp3[0];
            assign stg9_min_2nd = Lr_second_min_compare_tree_temp3[0] <= Lr_second_min_compare_tree_temp3[1] ?
                Lr_second_min_compare_tree_temp3[0] : Lr_second_min_compare_tree_temp3[1];
            integer tree_cnt4;
            always @(posedge clk) begin :  Lr_min_compare_tree_stg5
                if(!rst_n) begin
                    Lr_min_compare_tree_temp4[0] <= {SGM_LR_WIDTH{1'B1}};
                    Lr_min_compare_tree_temp4[1] <= {SGM_LR_WIDTH{1'B1}};
                    Lr_second_min_compare_tree_temp4[0] <= {SGM_LR_WIDTH{1'B1}};
                    Lr_second_min_compare_tree_temp4[1] <= {SGM_LR_WIDTH{1'B1}};
                    best_d_temp4[0] <= {DISPARITY_WIDTH{1'b0}};
                    best_d_temp4[1] <= {DISPARITY_WIDTH{1'b0}};
                end
                else begin
                    if(per_cmr2_href_dly[9]) begin
                        Lr_min_compare_tree_temp4[0] <= 
                            Lr_min_compare_tree_temp3[0] <= Lr_min_compare_tree_temp3[1] ?
                            Lr_min_compare_tree_temp3[0] : Lr_min_compare_tree_temp3[1];
                        Lr_second_min_compare_tree_temp4[0] <= stg9_max_lr <= stg9_min_2nd ? stg9_max_lr : stg9_min_2nd;
                        best_d_temp4[0] <= 
                            Lr_min_compare_tree_temp3[0] <= Lr_min_compare_tree_temp3[1] ?
                            best_d_temp3[0] : best_d_temp3[1];
                        Lr_min_compare_tree_temp4[1] <= Lr_min_compare_tree_temp3[2];
                        Lr_second_min_compare_tree_temp4[1] <= Lr_second_min_compare_tree_temp3[2];
                        best_d_temp4[1] <= best_d_temp3[2];
                    end
                end
            end  
            // stage 10: 第六级比较树，合并 temp4[0] 和 temp4[1] 得到全局最小和第二小
            wire [SGM_LR_WIDTH-1:0] stg10_max_lr;
            wire [SGM_LR_WIDTH-1:0] stg10_min_2nd;
            assign stg10_max_lr = Lr_min_compare_tree_temp4[0] <= Lr_min_compare_tree_temp4[1] ?
                Lr_min_compare_tree_temp4[1] : Lr_min_compare_tree_temp4[0];
            assign stg10_min_2nd = Lr_second_min_compare_tree_temp4[0] <= Lr_second_min_compare_tree_temp4[1] ?
                Lr_second_min_compare_tree_temp4[0] : Lr_second_min_compare_tree_temp4[1];
            always @(posedge clk) begin :  Lr_min_compare_tree_stg6
                if(!rst_n) begin
                    Lr_min <= {SGM_LR_WIDTH{1'B1}};
                    Lr_second_min <= {SGM_LR_WIDTH{1'B1}};
                    best_disparity <= {DISPARITY_WIDTH{1'b0}};
                end
                else begin
                    if(per_cmr2_href_dly[10]) begin
                        Lr_min <= Lr_min_compare_tree_temp4[0] <= Lr_min_compare_tree_temp4[1] ? Lr_min_compare_tree_temp4[0] : Lr_min_compare_tree_temp4[1];
                        Lr_second_min <= stg10_max_lr <= stg10_min_2nd ? stg10_max_lr : stg10_min_2nd;
                        best_disparity <= Lr_min_compare_tree_temp4[0] <= Lr_min_compare_tree_temp4[1] ? best_d_temp4[0] : best_d_temp4[1];
                    end
                end
            end  
            // stage 11: 置信度计算
            always @(posedge clk) begin
                if(!rst_n) begin
                    best_disparity_dly <= {DISPARITY_WIDTH{1'b0}};
                    confidence_reg <= {CONFIDENCE_WIDTH{1'b0}};
                end
                else begin
                    if(per_cmr2_href_dly[11]) begin
                        best_disparity_dly <= best_disparity;
                        confidence_reg <= Lr_second_min - Lr_min;
                    end
                end
            end
        end
    endgenerate
    assign disparity_vsync = per_cmr2_vsync_dly[11];
    assign disparity_href = per_cmr2_href_dly[11];
    assign disparity[DISPARITY_WIDTH-1] = confidence_reg >= CONFIDENCE_THRE ? 1'b0 : 1'b1;
    assign disparity[DISPARITY_WIDTH-2:0] = best_disparity_dly[DISPARITY_WIDTH-2:0];
    assign disparty_confidence = confidence_reg;
endmodule