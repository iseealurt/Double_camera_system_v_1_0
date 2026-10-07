module sgm#(
    parameter   IMG_WIDTH       =   640     ,
    parameter   IMG_HEIGHT      =   480     ,
    parameter   MAX_MATCH_DEPTH =   40      ,
    parameter   CENSUS_WIDTH    =   24      ,
    parameter   DISPARITU_WIDTH =   8       
)(
    input   wire                            clk                 ,
    input   wire                            rst_n               ,

    input   wire                            per_cmr1_vsync      ,
    input   wire                            per_cmr1_ff_empty   ,
    input   wire                            per_cmr1_ff_full    ,
    input   wire    [CENSUS_WIDTH-1:0]      per_cmr1_census     ,
    output  wire                            per_cmr1_ff_rd_en   ,

    input   wire                            per_cmr2_vsync      ,
    input   wire                            per_cmr2_href       ,
    input   wire    [CENSUS_WIDTH-1:0]      per_cmr2_census     ,

    output  wire                            disparity_vsync     ,
    output  wire                            disparity_href      ,
    output  wire    [DISPARITU_WIDTH-1:0]   disparity
);
    //plan: 由于时序问题，只使用一个方向的代价聚合（从左到右）
    //用三段式状态机控制算法和除错：
    /*
        状态                                     跳转条件                                               跳转后的状态
        IDLE                        cmr_1_vsync和cmr_2_vsync均有效                                  FRAME_PROCESSING
        FRAME_PROCESSING            cmr_1_vsync和cmr_2_vsync均无效                                      IDLE
        FRAME_PROCESSING            缓冲cmr_1的census序列的FIFO溢出                                    FIFO_OVERFLOW
        FRAME_PROCESSING            一帧的半全局匹配完成后FIFO内仍有数据残留                             FIFO_DATA_LEFT
        FRAME_PROCESSING            一帧的半全局匹配完成后，cmr1或者cmr2的行计数器数值不正确                CMR_RCNT_ERROR
        FRAME_PROCESSING            一帧的半全局匹配中，在一行结束后cmr1或者cmr2的列计数器数值不正确        CMR_CCNT_ERROR

        所有错误状态                  cmr_1_vsync和cmr_2_vsync均无效                                  IDLE （仿真时写入log中，上板时写入错误FIFO里）
    */
    //控制信号定义和行为
    assign per_cmr1_ff_rd_en = !per_cmr1_ff_empty && per_cmr2_href;
    //延迟13+1个周期输出
    reg [13:0] cmr_2_vsync_dly , cmr_2_href_dly;
    always@(posedge clk) begin
        if(!rst_n) begin
            cmr_2_vsync_dly <= 14'd0;
            cmr_2_href_dly <= 14'd0;
        end
        else begin
            cmr_2_vsync_dly <= {cmr_2_vsync_dly[12:0],per_cmr2_vsync};
            cmr_2_href_dly <= {cmr_2_href_dly[12:0],per_cmr2_href};
        end
    end

    // 状态机状态定义
    localparam  IDLE                = 3'b000;
    localparam  FRAME_PROCESSING    = 3'b001;
    localparam  FIFO_OVERFLOW       = 3'b010;
    localparam  FIFO_DATA_LEFT      = 3'b011;
    localparam  CMR_RCNT_ERROR      = 3'b100;
    localparam  CMR_CCNT_ERROR      = 3'b101;

    reg [2:0]   state;
    reg [2:0]   next_state;

    // 状态寄存器（时序逻辑）
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    // ==================== 行列计数器及错误检测 ====================
    reg [9:0]   cmr2_row_cnt;
    reg [9:0]   cmr2_col_cnt;

    wire        cmr2_vsync_posedge;
    wire        cmr2_vsync_negedge;
    wire        cmr2_href_posedge;
    wire        cmr2_href_negedge;

    assign cmr2_vsync_posedge = per_cmr2_vsync && !cmr_2_vsync_dly[0];
    assign cmr2_vsync_negedge = !per_cmr2_vsync && cmr_2_vsync_dly[0];
    assign cmr2_href_posedge  = per_cmr2_href && !cmr_2_href_dly[0];
    assign cmr2_href_negedge  = !per_cmr2_href && cmr_2_href_dly[0];

    // cmr2行计数器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmr2_row_cnt <= 10'd0;
        end
        else begin
            if (cmr2_vsync_posedge) begin
                cmr2_row_cnt <= 10'd0;
            end
            else if (cmr2_href_negedge && state == FRAME_PROCESSING) begin
                cmr2_row_cnt <= cmr2_row_cnt + 1'b1;
            end
        end
    end

    // cmr2列计数器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmr2_col_cnt <= 10'd0;
        end
        else begin
            if (cmr2_href_negedge || cmr2_vsync_posedge) begin
                cmr2_col_cnt <= 10'd0;
            end
            else if (per_cmr2_href && cmr_2_href_dly[0] && state == FRAME_PROCESSING) begin
                cmr2_col_cnt <= cmr2_col_cnt + 1'b1;
            end
        end
    end

    // 错误检测标志
    reg row_cnt_error_flag;
    reg col_cnt_error_flag;

    // 行列计数错误检测
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            row_cnt_error_flag <= 1'b0;
            col_cnt_error_flag <= 1'b0;
        end
        else begin
            if (state == IDLE) begin
                row_cnt_error_flag <= 1'b0;
                col_cnt_error_flag <= 1'b0;
            end
            else if (state == FRAME_PROCESSING) begin
                // 一帧结束时检查行计数器（应等于IMG_HEIGHT）
                if (cmr2_vsync_negedge) begin
                    if (cmr2_row_cnt != IMG_HEIGHT) begin
                        row_cnt_error_flag <= 1'b1;
                    end
                end
                // 每行结束时检查列计数器（应等于IMG_WIDTH）
                if (cmr2_href_negedge) begin
                    if (cmr2_col_cnt != IMG_WIDTH) begin
                        col_cnt_error_flag <= 1'b1;
                    end
                end
            end
        end
    end

    // ==================== 状态机输出逻辑与错误处理 ====================
    reg [31:0]  error_cnt;
    reg [255:0] error_msg;

    // 仿真时错误log输出
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            error_cnt <= 32'd0;
        end
        else begin
            case (state)
                IDLE: begin
                    error_cnt <= 32'd0;
                end
                
                FIFO_OVERFLOW: begin
                    if (error_cnt == 0) begin
                        $display("@ %0t, [SGM ERROR] FIFO overflow detected!", $time);
                        error_cnt <= error_cnt + 1'b1;
                    end
                end
                
                FIFO_DATA_LEFT: begin
                    if (error_cnt == 0) begin
                        $display("@ %0t, [SGM ERROR] Frame end but FIFO still has data left!", $time);
                        error_cnt <= error_cnt + 1'b1;
                    end
                end
                
                CMR_RCNT_ERROR: begin
                    if (error_cnt == 0) begin
                        $display("@ %0t, [SGM ERROR] Row counter error! expected: %0d, actual: %0d", 
                            $time, IMG_HEIGHT, cmr2_row_cnt);
                        error_cnt <= error_cnt + 1'b1;
                    end
                end
                
                CMR_CCNT_ERROR: begin
                    if (error_cnt == 0) begin
                        $display("@ %0t, [SGM ERROR] Column counter error! row: %0d, expected: %0d, actual: %0d", 
                            $time, cmr2_row_cnt, IMG_WIDTH, cmr2_col_cnt);
                        error_cnt <= error_cnt + 1'b1;
                    end
                end
            endcase
        end
    end

    // ==================== 流水线使能信号链 ====================
    // 总共有13+1=14级延迟，使用cmr_2_href_dly[1]到cmr_2_href_dly[13]
    // 第1级：cmr_2_href_dly[1] - 窗口移位
    // 第2级：cmr_2_href_dly[2] - XOR运算
    // 第3级：cmr_2_href_dly[3] - LUT6 popcount
    // 第4级：cmr_2_href_dly[4] - 第一层加法
    // 第5级：cmr_2_href_dly[5] - 第二层加法
    // 第6-13级：代价聚合与WTA
    // 输出：cmr_2_href_dly[13], cmr_2_vsync_dly[13]

    // 算法运行全局使能
    wire pipeline_en;
    assign pipeline_en = (state == FRAME_PROCESSING);

    // ==================== 修正后的次态跳转逻辑 ====================
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (per_cmr1_vsync && per_cmr2_vsync) begin
                    next_state = FRAME_PROCESSING;
                    $display("@ %0t, [SGM] Frame processing start", $time);
                end
            end

            FRAME_PROCESSING: begin
                if (per_cmr1_ff_full) begin
                    next_state = FIFO_OVERFLOW;
                end
                else if (row_cnt_error_flag) begin
                    next_state = CMR_RCNT_ERROR;
                end
                else if (col_cnt_error_flag) begin
                    next_state = CMR_CCNT_ERROR;
                end
                else if (!per_cmr1_vsync && !per_cmr2_vsync) begin
                    if (!per_cmr1_ff_empty) begin
                        next_state = FIFO_DATA_LEFT;
                    end
                    else begin
                        next_state = IDLE;
                        $display("@ %0t, [SGM] Frame processing complete successfully", $time);
                    end
                end
            end
            
            FIFO_OVERFLOW, FIFO_DATA_LEFT, CMR_RCNT_ERROR, CMR_CCNT_ERROR: begin
                if (!per_cmr1_vsync && !per_cmr2_vsync) begin
                    next_state = IDLE;
                    $display("@ %0t, [SGM] Error state cleared, returning to IDLE", $time);
                end
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end
    
    //第一级流水线：cmr1的匹配窗口
    reg     [CENSUS_WIDTH-1:0]  cmr1_sgm_window[MAX_MATCH_DEPTH-1:0];
    integer  window_cnt;
    always@(posedge clk) begin
        if(!rst_n) begin
            for(window_cnt=0;window_cnt<MAX_MATCH_DEPTH;window_cnt=window_cnt+1) begin
                cmr1_sgm_window[window_cnt] <= {CENSUS_WIDTH{1'b0}};
            end
        end
        else begin
            if(cmr_2_href_dly[1]) begin
                 cmr1_sgm_window[0] <= per_cmr1_census;
                for(window_cnt=1;window_cnt<MAX_MATCH_DEPTH;window_cnt=window_cnt+1) begin
                    cmr1_sgm_window[window_cnt] <=  cmr1_sgm_window[window_cnt-1];
                end
            end       
        end
    end

    //第二级流水线：对匹配窗口内的结果进行异或运算
    reg     [CENSUS_WIDTH-1:0]  per_cmr2_census_dly; // FIFO输出延迟1个周期
    reg     [CENSUS_WIDTH-1:0]  sgm_xor_sequence[MAX_MATCH_DEPTH-1:0];
    always@(posedge clk) begin
        if(!rst_n) begin
            per_cmr2_census_dly <= {CENSUS_WIDTH{1'b0}};
            for(window_cnt=0;window_cnt<MAX_MATCH_DEPTH;window_cnt=window_cnt+1) begin
                sgm_xor_sequence[window_cnt] <= {CENSUS_WIDTH{1'b0}};
            end
        end
        else begin
            if(cmr_2_href_dly[2]) begin
                per_cmr2_census_dly <= per_cmr2_census;
                for(window_cnt=0;window_cnt<MAX_MATCH_DEPTH;window_cnt=window_cnt+1) begin
                    sgm_xor_sequence[window_cnt] <= cmr1_sgm_window[window_cnt] ^ per_cmr2_census_dly;
                end
            end
        end
    end

    //PG2L50H使用LUT6，所以使用两级流水线来进行popcount来得到hamming距离
    //第三级流水线，初次进行6位的popcount
    localparam POPCOUNT_REG_NUM = CENSUS_WIDTH / 6 * MAX_MATCH_DEPTH; 
    localparam GROUP_PER_DISP = CENSUS_WIDTH / 6;
    reg     [2:0] popcount_s1[POPCOUNT_REG_NUM-1:0];
    integer i, j;
    always @(posedge clk) begin
        if(!rst_n) begin
            for(i = 0; i < POPCOUNT_REG_NUM; i = i + 1) begin
                popcount_s1[i] <= 3'd0;
            end
        end
        else begin
            if(cmr_2_href_dly[3]) begin
                for(i = 0; i < MAX_MATCH_DEPTH; i = i + 1) begin
                    for(j = 0; j < GROUP_PER_DISP; j = j + 1) begin
                        // 取6bit
                        case (sgm_xor_sequence[i][j*6 +: 6])
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
    //第四和第五级流水线，进行最后的popcount得到hamming距离
    // 中间寄存（第一层加法）
    localparam HAMMING_WIDTH = $clog2(CENSUS_WIDTH + 1);
    reg [HAMMING_WIDTH-1:0] sum_stage1[MAX_MATCH_DEPTH-1:0][(GROUP_PER_DISP/2)-1:0];

    // 第一层：两两相加
    always @(posedge clk) begin
        if(!rst_n) begin
            for(i = 0; i < MAX_MATCH_DEPTH; i = i + 1)
                for(j = 0; j < GROUP_PER_DISP/2; j = j + 1)
                    sum_stage1[i][j] <= 0;
        end
        else begin
            if(cmr_2_href_dly[4]) begin
                for(i = 0; i < MAX_MATCH_DEPTH; i = i + 1) begin
                    for(j = 0; j < GROUP_PER_DISP/2; j = j + 1) begin
                        sum_stage1[i][j] <= 
                            popcount_s1[i*GROUP_PER_DISP + 2*j] +
                            popcount_s1[i*GROUP_PER_DISP + 2*j + 1];
                    end
                end
            end 
        end
    end

    reg [HAMMING_WIDTH-1:0] hamming_dist[MAX_MATCH_DEPTH-1:0];
    // 第二层：最终累加
    always @(posedge clk) begin
        if(!rst_n) begin
            for(i = 0; i < MAX_MATCH_DEPTH; i = i + 1)
                hamming_dist[i] <= 0;
        end
        else begin
            if(cmr_2_href_dly[5]) begin
                for(i = 0; i < MAX_MATCH_DEPTH; i = i + 1) begin
                    hamming_dist[i] <= 0;
                    for(j = 0; j < GROUP_PER_DISP/2; j = j + 1) begin
                        hamming_dist[i] <= hamming_dist[i] + sum_stage1[i][j];
                    end
                end
            end            
        end
    end
    localparam COST_WIDTH = HAMMING_WIDTH;
    reg [COST_WIDTH-1:0] Lr_prev [MAX_MATCH_DEPTH-1:0];
    reg [COST_WIDTH-1:0] Lr_curr [MAX_MATCH_DEPTH-1:0];
    parameter P1 = 2;
    parameter P2 = 8;
    //接下来使用WTA策略来确定视差，并以VGA时序输出视差图发送到写入模块，重新写回DDR3中以进行读取。注意这里的写入和读取可能也需要三重缓冲，具体看实时性的要求和资源利用率
    
    localparam DISP_WIDTH = $clog2(MAX_MATCH_DEPTH);
    reg [COST_WIDTH-1:0] cost_s0 [MAX_MATCH_DEPTH-1:0];
    reg [DISP_WIDTH-1:0] disp_s0 [MAX_MATCH_DEPTH-1:0];
    reg [COST_WIDTH-1:0] min_prev;
    reg [COST_WIDTH-1:0] l1, l2, l3, l4;
    reg [COST_WIDTH-1:0] min_val;
    integer d, k;
    wire line_start_dly_5;

    assign line_start_dly_5 = cmr_2_href_dly[4] && !cmr_2_href_dly[5];
    //stage 6
    always @(posedge clk) begin
        if(!rst_n) begin
            for(d=0; d<MAX_MATCH_DEPTH; d=d+1)
                Lr_prev[d] <= 0;
        end
        else if(line_start_dly_5) begin
            for(d=0; d<MAX_MATCH_DEPTH; d=d+1)
                    Lr_prev[d] <= 0;
            end
        else if(cmr_2_href_dly[6]) begin
            // 计算 min_k Lr_prev[k]
            for(k=1; k<MAX_MATCH_DEPTH; k=k+1) begin
                if(Lr_prev[k] < min_prev)
                    min_prev <= Lr_prev[k];
            end
            for(d=0; d<MAX_MATCH_DEPTH; d=d+1) begin
                // 各项候选   
                l1 <= Lr_prev[d];
                if(d > 0)
                    l2 <= Lr_prev[d-1] + P1;
                else
                    l2 <= {COST_WIDTH{1'b1}};
                if(d < MAX_MATCH_DEPTH-1)
                    l3 <= Lr_prev[d+1] + P1;
                else
                    l3 <= {COST_WIDTH{1'b1}};
                l4 <= min_prev + P2;
                // 取最小               
                min_val <= l1;
                if(l2 < min_val) min_val <= l2;
                if(l3 < min_val) min_val <= l3;
                if(l4 < min_val) min_val <= l4;
                // 更新
                Lr_curr[d] <= hamming_dist[d] + min_val - min_prev;
            end
            // 更新上一状态
            for(d=0; d<MAX_MATCH_DEPTH; d=d+1)
                Lr_prev[d] <= Lr_curr[d];
        end
    end
    //stage 7
    always @(posedge clk) begin
        if(cmr_2_href_dly[7]) begin
            for(i=0;i<MAX_MATCH_DEPTH;i=i+1) begin
                cost_s0[i] <= Lr_curr[i];
                disp_s0[i] <= i;
            end
        end    
    end

    //stage 8
    localparam S1_NUM = MAX_MATCH_DEPTH/2;
    reg [COST_WIDTH-1:0] cost_s1 [S1_NUM-1:0];
    reg [DISP_WIDTH-1:0] disp_s1 [S1_NUM-1:0];
    always @(posedge clk) begin
        if((cmr_2_href_dly[8])) begin
            for(j=0;j<S1_NUM;j=j+1) begin
                if(cost_s0[2*j] <= cost_s0[2*j+1]) begin
                    cost_s1[j] <= cost_s0[2*j];
                    disp_s1[j] <= disp_s0[2*j];
                end
                else begin
                    cost_s1[j] <= cost_s0[2*j+1];
                    disp_s1[j] <= disp_s0[2*j+1];
                end
            end
        end
    end

    //stage 9
    localparam S2_NUM = S1_NUM/2;

    reg [COST_WIDTH-1:0] cost_s2 [S2_NUM-1:0];
    reg [DISP_WIDTH-1:0] disp_s2 [S2_NUM-1:0];

    always @(posedge clk) begin
        if(cmr_2_href_dly[9]) begin
            for(j=0;j<S2_NUM;j=j+1) begin
                if(cost_s1[2*j] <= cost_s1[2*j+1]) begin
                    cost_s2[j] <= cost_s1[2*j];
                    disp_s2[j] <= disp_s1[2*j];
                end
                else begin
                    cost_s2[j] <= cost_s1[2*j+1];
                    disp_s2[j] <= disp_s1[2*j+1];
                end
            end
        end
    end
    //stage 10 - cmr_2_href_dly[10]
    localparam S3_NUM = S2_NUM/2;

    reg [COST_WIDTH-1:0] cost_s3 [S3_NUM-1:0];
    reg [DISP_WIDTH-1:0] disp_s3 [S3_NUM-1:0];

    always @(posedge clk) begin
        if(cmr_2_href_dly[10]) begin
            for(j=0;j<S3_NUM;j=j+1) begin
                if(cost_s2[2*j] <= cost_s2[2*j+1]) begin
                    cost_s3[j] <= cost_s2[2*j];
                    disp_s3[j] <= disp_s2[2*j];
                end
                else begin
                    cost_s3[j] <= cost_s2[2*j+1];
                    disp_s3[j] <= disp_s2[2*j+1];
                end
            end
        end
    end

    //stage 11 - cmr_2_href_dly[11]
    localparam S4_NUM = 3;

    reg [COST_WIDTH-1:0] cost_s4 [S4_NUM-1:0];
    reg [DISP_WIDTH-1:0] disp_s4 [S4_NUM-1:0];

    always @(posedge clk) begin
        if(cmr_2_href_dly[11]) begin
            // 0 vs 1
            if(cost_s3[0] <= cost_s3[1]) begin
                cost_s4[0] <= cost_s3[0];
                disp_s4[0] <= disp_s3[0];
            end
            else begin
                cost_s4[0] <= cost_s3[1];
                disp_s4[0] <= disp_s3[1];
            end

            // 2 vs 3
            if(cost_s3[2] <= cost_s3[3]) begin
                cost_s4[1] <= cost_s3[2];
                disp_s4[1] <= disp_s3[2];
            end
            else begin
                cost_s4[1] <= cost_s3[3];
                disp_s4[1] <= disp_s3[3];
            end

            // 剩余节点
            cost_s4[2] <= cost_s3[4];
            disp_s4[2] <= disp_s3[4];
        end
    end
    //stage 12 - cmr_2_href_dly[12]
    localparam S5_NUM = 2;

    reg [COST_WIDTH-1:0] cost_s5 [S5_NUM-1:0];
    reg [DISP_WIDTH-1:0] disp_s5 [S5_NUM-1:0];

    always @(posedge clk) begin
        if(cmr_2_href_dly[12]) begin
            if(cost_s4[0] <= cost_s4[1]) begin
                cost_s5[0] <= cost_s4[0];
                disp_s5[0] <= disp_s4[0];
            end
            else begin
                cost_s5[0] <= cost_s4[1];
                disp_s5[0] <= disp_s4[1];
            end

            cost_s5[1] <= cost_s4[2];
            disp_s5[1] <= disp_s4[2];
        end
    end

    reg [COST_WIDTH-1:0] cost_final;
    reg [DISP_WIDTH-1:0] disp_final;
    //stage 13 - cmr_2_href_dly[13]
    always @(posedge clk) begin
        if(cmr_2_href_dly[13]) begin
            if(cost_s5[0] <= cost_s5[1]) begin
                cost_final <= cost_s5[0];
                disp_final <= disp_s5[0];
            end
            else begin
                cost_final <= cost_s5[1];
                disp_final <= disp_s5[1];
            end
        end
    end

    assign disparity = disp_final;
    assign disparity_vsync = cmr_2_vsync_dly[13];
    assign disparity_href = cmr_2_href_dly[13];

endmodule