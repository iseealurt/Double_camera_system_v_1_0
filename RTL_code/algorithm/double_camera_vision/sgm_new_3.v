//cmr1 为左摄像头输入，cmr2为右摄像头输入，本模块计算左视差图
//输入：两个摄像头的census序列，要求 vsync_fifo 不为空时，
//输出：
//  a. int16格式的视差，范围为0 ~ 191 
module sgm_new_3#(
    parameter   IMG_WIDTH           =   640     ,
    parameter   IMG_HEIGHT          =   480     ,
    parameter   MAX_MATCH_DEPTH     =   32      ,
    parameter   CENSUS_WIDTH        =   24      ,  
    parameter   DISPARITY_WIDTH     =   16      ,
    parameter   CONFIDENCE_WIDTH    =   8       ,
    parameter   CONFIDENCE_THRE     =   1       ,
    parameter   SGM_P1              =   0       ,
    parameter   SGM_P2              =   0       ,
    parameter   SGM_LR_WIDTH        =   6       ,
    parameter   SGM_INVALID_COST    =   48      
)(
    input   wire                            sgm_clk                 ,
    input   wire                            rst_n                   ,

    input   wire                            cmr_vsync_fifo_empty    ,
    input   wire                            cmr1_line_fifo_empty    ,
    input   wire    [CENSUS_WIDTH-1:0]      cmr1_census             ,

    input   wire                            cmr2_line_fifo_empty    ,
    input   wire    [CENSUS_WIDTH-1:0]      cmr2_census             ,

    output  reg                             cmr_vsync_fifo_rd_en    ,
    output  reg                             cmr_census_fifo_rd_en   ,

    output  reg                             disparity_vsync         ,
    output  reg                             disparity_hsync         ,
    output  reg                             disparity_href          ,
    output  reg    [DISPARITY_WIDTH-1:0]    disparity
);
    localparam DELAY_CHAIN_VALUE = 12;
    wire sgm_vsync;
    wire sgm_hsync;

    reg [DELAY_CHAIN_VALUE-1:0] vsync_delay_chain;
    reg [DELAY_CHAIN_VALUE-1:0] hsync_delay_chain;

    always@(posedge sgm_clk) begin
        if(!rst_n) begin
            vsync_delay_chain <= {DELAY_CHAIN_VALUE{1'b0}};
            hsync_delay_chain <= {DELAY_CHAIN_VALUE{1'b0}};
        end
        else begin
            vsync_delay_chain <= {vsync_delay_chain[DELAY_CHAIN_VALUE-2:0],sgm_vsync};
            hsync_delay_chain <= {hsync_delay_chain[DELAY_CHAIN_VALUE-2:0],sgm_hsync};
        end
    end

    // row counter and col counter
    localparam ROW_CNT_WIDTH = $clog2(IMG_HEIGHT); 
    localparam COL_CNT_WIDTH = $clog2(IMG_WIDTH);

    reg [ROW_CNT_WIDTH-1:0] row_cnt;
    reg [COL_CNT_WIDTH-1:0] col_cnt;

    always @(posedge sgm_clk) begin
        if(!rst_n) begin
            row_cnt <= 0;
            col_cnt <= 0;
        end
        else begin
            if(cmr_census_fifo_rd_en) begin
                col_cnt <= col_cnt == IMG_WIDTH - 1 ? 0 : col_cnt + 1'b1;
            end
            else begin
                col_cnt <= 0;
            end

            if(cmr_vsync_fifo_rd_en) begin
                row_cnt <= 0;
            end
            else begin
                if(col_cnt == IMG_WIDTH - 1) begin
                    row_cnt <= row_cnt + 1'b1;
                end 

                if(row_cnt >= IMG_HEIGHT) $display("@ %0t , [ERROR][SGM] row_cnt overflowed @ %0d",$time,row_cnt);
            end
        end
    end 

    // SGM control state machine
    localparam STATE_VALUE = 4;
    localparam IDLE = 4'b0001;
    localparam FRAME_START = 4'b0010;
    localparam FRAME_BUSY = 4'b0100;
    localparam FRAME_END = 4'b1000;

    reg [STATE_VALUE-1:0] curr_state;
    reg [STATE_VALUE-1:0] next_state;

    always@(*) begin
        next_state = curr_state;
        case(curr_state) 
            IDLE:begin
                if(!cmr_vsync_fifo_empty) begin
                    next_state = FRAME_START;
                end
            end
            FRAME_START:begin
                if(cmr_vsync_fifo_rd_en) begin 
                    next_state = FRAME_BUSY;
                end
            end
            FRAME_BUSY:begin
                if(col_cnt == IMG_WIDTH - 1 && row_cnt == IMG_HEIGHT - 1) begin //算法的行计数器达到规定值
                    next_state = FRAME_END;
                end
            end
            FRAME_END:begin
                if(!vsync_delay_chain[DELAY_CHAIN_VALUE-2] && vsync_delay_chain[DELAY_CHAIN_VALUE-1]) begin // 数据flush完成
                    next_state = IDLE;
                end
            end
            default:begin
                next_state = IDLE;
            end
        endcase
    end

    always@(posedge sgm_clk) begin
        if(!rst_n) begin
            curr_state <= IDLE;
        end
        else begin
            curr_state <= next_state;
        end
    end

    assign sgm_vsync = curr_state == FRAME_BUSY;
    assign sgm_hsync = sgm_vsync && col_cnt == IMG_WIDTH - 1;
    
    localparam LR_NUM = 4;
    localparam LR_NUM_CNT_WIDTH = $clog2(LR_NUM);

    reg [LR_NUM_CNT_WIDTH-1:0] lr_num_cnt;

    always@(posedge sgm_clk) begin
        if(!rst_n) begin
            lr_num_cnt <= {LR_NUM_CNT_WIDTH{1'b0}};
        end
        else begin
            if(curr_state == FRAME_BUSY) begin
                lr_num_cnt <= lr_num_cnt == LR_NUM - 1'b1 ? {LR_NUM_CNT_WIDTH{1'b0}} : lr_num_cnt + 1'b1;
            end
        end
    end

    wire cmr_census_fifo_rd_rdy;
    
    assign cmr_census_fifo_rd_rdy = lr_num_cnt == LR_NUM - 1'b1;

    always@(posedge sgm_clk) begin
        if(!rst_n) begin
            cmr_vsync_fifo_rd_en <= 1'b0;
            cmr_census_fifo_rd_en <= 1'b0;
        end
        else begin
            if(curr_state == FRAME_START) begin
                cmr_vsync_fifo_rd_en <= 1'b1;
            end
            else begin
                cmr_vsync_fifo_rd_en <= 1'b0;
            end

            if(curr_state == FRAME_BUSY) begin
                if(!cmr1_line_fifo_empty && !cmr2_line_fifo_empty) begin
                    cmr_census_fifo_rd_en <= col_cnt == IMG_WIDTH - 1 ? 1'b0 : cmr_census_fifo_rd_rdy; //读满 640个像素后强制停止读取至少一个周期，方便观察波形
                end
                else begin
                    cmr_census_fifo_rd_en <= 1'b0;
                end
            end
            else begin
                cmr_census_fifo_rd_en <= 1'b0;
            end
        end
    end

    // Pipeline's driver signal
    reg [DELAY_CHAIN_VALUE-1:0] pipeline_dly_chain;
    always @(posedge sgm_clk) begin
        if(!rst_n) begin
            pipeline_dly_chain <= 0;
        end
        else begin
            pipeline_dly_chain <= {pipeline_dly_chain[DELAY_CHAIN_VALUE-2:0],cmr_census_fifo_rd_en};
        end
    end

    // Stage 0 : read data , transmit it to the xor window , register the cmr2's census data
    reg [CENSUS_WIDTH-1:0]  xor_window[MAX_MATCH_DEPTH-1:0]; // 96 * 24 = 2304 FF
    reg [CENSUS_WIDTH-1:0]  cmr1_census_reg; 
    integer i;
    always@(posedge sgm_clk) begin : xor_window_generate
        if(!rst_n) begin
            cmr1_census_reg <= {CENSUS_WIDTH{1'b0}};
            for(i=0;i<MAX_MATCH_DEPTH;i=i+1) begin
                xor_window[i] <= {CENSUS_WIDTH{1'b0}};
            end
        end
        else begin
            if(pipeline_dly_chain[0]) begin
                cmr1_census_reg <= cmr1_census;
                xor_window[0] <= cmr2_census;
                for(i=1;i<MAX_MATCH_DEPTH;i=i+1) begin
                    xor_window[i] <= xor_window[i-1];
                end
            end
        end
    end

    // Stage 1 : xor_outcome
    reg [CENSUS_WIDTH-1:0] xor_outcome[MAX_MATCH_DEPTH-1:0]; // 2304 FF
    always@(posedge sgm_clk) begin : xor_computation
        if(!rst_n) begin
            for(i=0;i<MAX_MATCH_DEPTH;i=i+1) begin
                xor_outcome[i] <= {CENSUS_WIDTH{1'b0}};
            end
        end
        else begin
            if(pipeline_dly_chain[1]) begin
                for(i=0;i<MAX_MATCH_DEPTH;i=i+1) begin
                    xor_outcome[i] <=  xor_window[i] ^ cmr1_census_reg;
                end
            end
        end
    end

    // stage 2: 对24位的census结果进行基于LUT6的第一次popcount
    localparam POPCOUNT_REG_NUM = CENSUS_WIDTH / 6 * MAX_MATCH_DEPTH; 
    localparam GROUP_PER_DISP = CENSUS_WIDTH / 6;
    reg     [2:0] popcount_s1[POPCOUNT_REG_NUM-1:0];
    integer j;
    always @(posedge sgm_clk) begin : hamming_popcount_s1
        if(!rst_n) begin
            for(i = 0; i < POPCOUNT_REG_NUM; i = i + 1) begin
                popcount_s1[i] <= 3'd0;
            end
        end
        else begin
            if(pipeline_dly_chain[2]) begin
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

    // Stage 3 : popcount第二级(两两相加) + 左视差掩码生成
    // 左视差图掩码约束: col_cnt >= d 时视差d有效，否则填充SGM_INVALID_COST
    localparam HAMMING_WIDTH = $clog2(CENSUS_WIDTH); // 5bit
    reg [HAMMING_WIDTH-1:0] popcount_s2[MAX_MATCH_DEPTH-1:0][(GROUP_PER_DISP/2)-1:0];
    reg [COL_CNT_WIDTH-1:0] hamming_valid_mask_col_cnt;

    always@(posedge sgm_clk) begin
        if(!rst_n) begin
            hamming_valid_mask_col_cnt <= 0;
        end
        else begin
            if(pipeline_dly_chain[4]) begin
                hamming_valid_mask_col_cnt <= hamming_valid_mask_col_cnt + 1'b1;
                if(hamming_valid_mask_col_cnt >= IMG_WIDTH) $display("@ %0t , [ERROR] hamming_valid_mask_col_cnt overflowed @ %0d !",$time,hamming_valid_mask_col_cnt);
            end
            else begin
                hamming_valid_mask_col_cnt <= 0;
            end
        end
    end
    // 每个视差独立的有效掩码（组合逻辑）
    reg hamming_dist_valid_mask[MAX_MATCH_DEPTH-1:0];
    always @(*) begin
        for(i=0; i<MAX_MATCH_DEPTH; i=i+1) begin
            hamming_dist_valid_mask[i] = (hamming_valid_mask_col_cnt >= i);
        end
    end

    always @(posedge sgm_clk) begin
        if(!rst_n) begin
            for(i=0;i<MAX_MATCH_DEPTH;i=i+1)
                for(j=0;j<GROUP_PER_DISP/2;j=j+1)
                    popcount_s2[i][j] <= 0;
        end
        else begin
            if(pipeline_dly_chain[3]) begin
                for(i=0;i<MAX_MATCH_DEPTH;i=i+1) begin
                    for(j=0;j<GROUP_PER_DISP/2;j=j+1) begin
                        popcount_s2[i][j] <= popcount_s1[i*GROUP_PER_DISP + 2*j]
                                           + popcount_s1[i*GROUP_PER_DISP + 2*j + 1];
                    end
                end
            end
        end
    end

    // Stage 4 : 最终汉明距离计算（带掩码）
    reg [HAMMING_WIDTH-1:0] hamming_dist[MAX_MATCH_DEPTH-1:0];
    always @(posedge sgm_clk) begin : hamming_dist_compute
        if(!rst_n) begin
            for(i=0;i<MAX_MATCH_DEPTH;i=i+1)
                hamming_dist[i] <= SGM_INVALID_COST;
        end
        else begin
            if(pipeline_dly_chain[4]) begin
                for(i=0;i<MAX_MATCH_DEPTH;i=i+1) begin
                    hamming_dist[i] <= hamming_dist_valid_mask[i]
                                     ? popcount_s2[i][0] + popcount_s2[i][1]
                                     : SGM_INVALID_COST;
                end
            end
        end
    end

    // stage 5-8 4方向代价聚合的脉动计算
    reg [LR_NUM_CNT_WIDTH:0] lr_aggregation_cnt;

    always @(posedge sgm_clk) begin : lr_aggregation_cnt_update
        if(!rst_n) begin
           lr_aggregation_cnt <= {LR_NUM_CNT_WIDTH{1'b1}} + 1'b1;
        end
        else begin
            if(pipeline_dly_chain[5]) begin
                lr_aggregation_cnt <= {LR_NUM_CNT_WIDTH{1'b0}};
            end
            else begin
                lr_aggregation_cnt <= lr_aggregation_cnt == {LR_NUM_CNT_WIDTH{1'b1}} + 1'b1 ? {LR_NUM_CNT_WIDTH{1'b1}} + 1'b1: lr_aggregation_cnt + 1'b1;
            end
        end
    end

    wire lr_aggregation_en;
    wire [LR_NUM-1:0] lr_aggregation_flag;
    
    assign lr_aggregation_en = lr_aggregation_cnt != {LR_NUM_CNT_WIDTH{1'b1}} + 1'b1;
    reg [LR_NUM-1:0] lr_aggregation_flag_dly[3:0];
    reg [COL_CNT_WIDTH-1:0] Lr_col_cnt;
    reg [ROW_CNT_WIDTH-1:0] Lr_row_cnt;

    localparam LR_MAX_VAL = SGM_P2 * 2;
    localparam LR_WIDTH = $clog2(LR_MAX_VAL) + 1;

    wire [LR_WIDTH-1:0] Lr_curr[MAX_MATCH_DEPTH-1:0];

    wire [LR_WIDTH-1:0] Lr0_curr[MAX_MATCH_DEPTH-1:0];
    reg [LR_WIDTH-1:0] Lr0_prev[MAX_MATCH_DEPTH-1:0];
    wire [LR_WIDTH-1:0] Lr0_prev_min;

    wire [LR_WIDTH-1:0] Lr1_curr[MAX_MATCH_DEPTH-1:0];
    reg [LR_WIDTH-1:0] Lr1_prev[MAX_MATCH_DEPTH-1:0];
    wire [LR_WIDTH-1:0] Lr1_prev_min;

    wire [LR_WIDTH-1:0] Lr2_curr[MAX_MATCH_DEPTH-1:0];
    reg [LR_WIDTH-1:0] Lr2_prev[MAX_MATCH_DEPTH-1:0];
    wire [LR_WIDTH-1:0] Lr2_prev_min;

    wire [LR_WIDTH-1:0] Lr3_curr[MAX_MATCH_DEPTH-1:0];
    reg [LR_WIDTH-1:0] Lr3_prev[MAX_MATCH_DEPTH-1:0];
    wire [LR_WIDTH-1:0] Lr3_prev_min;

    reg [LR_WIDTH-1:0] Lr_sum[MAX_MATCH_DEPTH-1:0];

    genvar lr_i , d_i;
    generate 
        begin : lr_aggregation_flag_update
            for(lr_i = 0 ; lr_i < LR_NUM ; lr_i = lr_i + 1'b1) begin
                assign lr_aggregation_flag[lr_i] = lr_aggregation_en && lr_aggregation_cnt == lr_i; // 计数器指示当前代价聚合方向
            end
            always @(posedge sgm_clk) begin
                if(!rst_n) begin
                    lr_aggregation_flag_dly[0] <= 0;
                    lr_aggregation_flag_dly[1] <= 0;
                end
                else begin
                    lr_aggregation_flag_dly[0] <= lr_aggregation_flag;
                    lr_aggregation_flag_dly[1] <= lr_aggregation_flag_dly[0];
                    lr_aggregation_flag_dly[2] <= lr_aggregation_flag_dly[1];
                    lr_aggregation_flag_dly[3] <= lr_aggregation_flag_dly[2];
                end
            end
        end
        begin : lr_aggreagaion_cnt_update
            always @(posedge sgm_clk) begin
                if(!rst_n) begin
                    Lr_col_cnt <= {COL_CNT_WIDTH{1'b0}};
                end
                else begin
                    if(pipeline_dly_chain[6]) begin
                        Lr_col_cnt <= Lr_col_cnt == IMG_WIDTH - 1'b1 ? {COL_CNT_WIDTH{1'b0}} : Lr_col_cnt + 1'b1;
                    end
                    else begin
                        Lr_col_cnt <= {COL_CNT_WIDTH{1'b0}};
                    end
                end

                if(!rst_n) begin
                    Lr_row_cnt <= {ROW_CNT_WIDTH{1'b0}};
                end
                else begin
                    if(vsync_delay_chain[5] && !vsync_delay_chain[6]) begin
                        Lr_row_cnt <= {ROW_CNT_WIDTH{1'b0}};
                    end
                    else begin
                        if(pipeline_dly_chain[6]) begin
                            Lr_row_cnt <= Lr_col_cnt == IMG_WIDTH - 1'b1 ? Lr_row_cnt + 1'b1 : Lr_row_cnt;
                        end
                    end
                end
            end
        end
        begin : lr0_aggregation_ram_ctrl
            // stage 4N + 3 : ram读出

            // stage 4M + 7 : ram写入
        end
        begin : lr1_aggregation_ram_ctrl
            // stage 4N + 4 : ram读出

            // stage 4M + 8 : ram写入
        end
        begin : lr2_aggregation_ram_ctrl
            // stage 4N + 5 : ram读出

            // stage 4M + 8 : ram写入
        end
        begin : lr3_aggregation_ram_ctrl
            // stage 4N + 6 : ram读出

            // stage 4M + 9 : ram写入   
        end
        begin : lr_aggregation
            reg [2:0] lr_aggregation_en_dly;

            always @(posedge sgm_clk) begin
                if(!rst_n) begin
                    lr_aggregation_en_dly <= 3'd0;
                end
                else begin
                    lr_aggregation_en_dly <= {lr_aggregation_en_dly[1:0],lr_aggregation_en};
                end
            end

            reg [LR_WIDTH-1:0] Lr_curr_comb[MAX_MATCH_DEPTH-1:0]; 

            for(d_i = 0 ; d_i < MAX_MATCH_DEPTH ; d_i = d_i + 1) begin
                // stage 5 : R 计算 & Hamming 距离寄存
                reg [LR_WIDTH-1:0] R_comb[3:0]; 
                reg [LR_WIDTH-1:0] R_regi[3:0];

                always @(*) begin
                    case(lr_aggregation_flag) 
                        4'b0001: begin 
                            R_comb[0] = Lr0_prev[d_i] - Lr0_prev_min;
                            if(d_i == 0) begin
                                R_comb[1] = SGM_INVALID_COST;
                            end
                            else begin
                                R_comb[1] = Lr0_prev[d_i-1] - Lr0_prev_min + SGM_P1;
                            end
                            if(d_i == MAX_MATCH_DEPTH-1) begin
                                R_comb[2] = SGM_INVALID_COST;
                            end
                            else begin
                                R_comb[2] = Lr0_prev[d_i+1] - Lr0_prev_min + SGM_P1;
                            end
                            R_comb[3] = SGM_P2;
                        end
                        4'b0010: begin 
                            R_comb[0] = Lr1_prev[d_i] - Lr1_prev_min;
                            if(d_i == 0) begin
                                R_comb[1] = SGM_INVALID_COST;
                            end
                            else begin
                                R_comb[1] = Lr1_prev[d_i-1] - Lr1_prev_min + SGM_P1;
                            end
                            if(d_i == MAX_MATCH_DEPTH-1) begin
                                R_comb[2] = SGM_INVALID_COST;
                            end
                            else begin
                                R_comb[2] = Lr1_prev[d_i+1] - Lr1_prev_min + SGM_P1;
                            end
                            R_comb[3] = SGM_P2;
                        end
                        4'b0100: begin 
                            R_comb[0] = Lr2_prev[d_i] - Lr2_prev_min;
                            if(d_i == 0) begin
                                R_comb[1] = SGM_INVALID_COST;
                            end
                            else begin
                                R_comb[1] = Lr2_prev[d_i-1] - Lr2_prev_min + SGM_P1;
                            end
                            if(d_i == MAX_MATCH_DEPTH-1) begin
                                R_comb[2] = SGM_INVALID_COST;
                            end
                            else begin
                                R_comb[2] = Lr2_prev[d_i+1] - Lr2_prev_min + SGM_P1;
                            end
                            R_comb[3] = SGM_P2;
                        end
                        4'b1000: begin 
                            R_comb[0] = Lr3_prev[d_i] - Lr3_prev_min;
                            if(d_i == 0) begin
                                R_comb[1] = SGM_INVALID_COST;
                            end
                            else begin
                                R_comb[1] = Lr3_prev[d_i-1] - Lr3_prev_min + SGM_P1;
                            end
                            if(d_i == MAX_MATCH_DEPTH-1) begin
                                R_comb[2] = SGM_INVALID_COST;
                            end
                            else begin
                                R_comb[2] = Lr3_prev[d_i+1] - Lr3_prev_min + SGM_P1;
                            end
                            R_comb[3] = SGM_P2;
                        end
                        default: begin 
                            R_comb[0] = SGM_INVALID_COST;
                            R_comb[1] = SGM_INVALID_COST;
                            R_comb[2] = SGM_INVALID_COST;
                            R_comb[3] = SGM_INVALID_COST;
                        end
                    endcase
                end

                reg [HAMMING_WIDTH-1:0] hamming_dist_dly;

                always @(posedge sgm_clk) begin
                    if(!rst_n) begin
                        R_regi[0] <= SGM_INVALID_COST;
                        R_regi[1] <= SGM_INVALID_COST;
                        R_regi[2] <= SGM_INVALID_COST;
                        R_regi[3] <= SGM_INVALID_COST;
                        hamming_dist_dly <= SGM_INVALID_COST; // max hamming dist
                    end
                    else begin
                        if(lr_aggregation_en) begin
                            R_regi[0] <= R_comb[0];
                            R_regi[1] <= R_comb[1];
                            R_regi[2] <= R_comb[2];
                            R_regi[3] <= R_comb[3];
                        end
                        if(pipeline_dly_chain[5]) begin
                            hamming_dist_dly <= hamming_dist[d_i];
                        end
                    end
                end

                // stage 6 : Lr_curr 计算
                reg [LR_WIDTH-1:0] R_min_comb;
                reg [LR_WIDTH-1:0] Lr_curr_comb;
                reg [LR_WIDTH-1:0] Lr_curr_regi;

                always @(*) begin
                    R_min_comb = SGM_INVALID_COST;
                    Lr_curr_comb = SGM_INVALID_COST;
                    for(i=0;i<LR_NUM;i=i+1) begin
                        R_min_comb = R_regi[i] < R_min_comb ? R_regi[i] : R_min_comb;
                    end
                    Lr_curr_comb = hamming_dist_dly[d_i] + R_min_comb;
                end

                always @(posedge sgm_clk) begin
                    if(!rst_n) begin
                        Lr_curr_regi <= SGM_INVALID_COST;
                    end
                    else begin
                        if(lr_aggregation_en_dly[0]) begin
                            Lr_curr_regi <= Lr_curr_comb;
                        end
                    end
                end
                assign Lr0_curr[d_i] = lr_aggregation_flag_dly[1][0] ? Lr_curr_regi : 0;
                assign Lr1_curr[d_i] = lr_aggregation_flag_dly[1][1] ? Lr_curr_regi : 0;
                assign Lr2_curr[d_i] = lr_aggregation_flag_dly[1][2] ? Lr_curr_regi : 0;
                assign Lr3_curr[d_i] = lr_aggregation_flag_dly[1][3] ? Lr_curr_regi : 0;
                assign Lr_curr[d_i] = Lr_curr_regi;
            end
            if (MAX_MATCH_DEPTH == 32) begin : Lr_prev_min_compare_tree
                integer LrCmpI,LrCmpJ;
                // stage 7 : 比较树第一级
                reg [LR_WIDTH-1:0] Lr_prev_min_temp_comb[6:0];
                always @(*) begin
                    for(LrCmpI = 0 ; LrCmpI < 6 ; LrCmpI = LrCmpI + 1) begin
                        Lr_prev_min_temp_comb[LrCmpI] = SGM_INVALID_COST;
                        for(LrCmpJ = 0 ; LrCmpJ < (MAX_MATCH_DEPTH - 2) / 6 ; LrCmpJ = LrCmpJ + 1) begin
                            Lr_prev_min_temp_comb[LrCmpI] = Lr_curr[LrCmpI*5+LrCmpJ] < Lr_prev_min_temp_comb[LrCmpI] ? Lr_curr[LrCmpI*6+LrCmpJ] : Lr_prev_min_temp_comb[LrCmpI];
                        end
                    end
                    Lr_prev_min_temp_comb[6] = Lr_curr[31] < Lr_curr[30] ? Lr_curr[31] : Lr_curr[30];
                end

                reg [LR_WIDTH-1:0] Lr_prev_min_temp_regi[7:0];
                always @(posedge sgm_clk) begin
                    if(!rst_n) begin
                        for(LrCmpI = 0 ; LrCmpI < 7 ; LrCmpI = LrCmpI + 1) begin
                            Lr_prev_min_temp_regi[LrCmpI] <= SGM_INVALID_COST;
                        end
                    end
                    else begin
                        for(LrCmpI = 0 ; LrCmpI < 7 ; LrCmpI = LrCmpI + 1) begin
                            if(lr_aggregation_en_dly[1]) begin
                                Lr_prev_min_temp_regi[LrCmpI] <= Lr_prev_min_temp_comb[LrCmpI];
                            end
                        end
                    end
                end

                // stage 8 : 比较树第二级
                reg [LR_WIDTH-1:0] Lr_prev_min_comb;
                reg [LR_WIDTH-1:0] Lr_prev_min_regi;
                always @(*) begin
                    Lr_prev_min_comb = SGM_INVALID_COST;
                    for(LrCmpI = 0 ; LrCmpI < 7 ; LrCmpI = LrCmpI + 1) begin
                        Lr_prev_min_comb = Lr_prev_min_temp_regi[LrCmpI] < Lr_prev_min_comb ? Lr_prev_min_temp_regi[LrCmpI] : Lr_prev_min_comb;
                    end
                end

                always @(posedge sgm_clk) begin
                    if(!rst_n) begin
                        Lr_prev_min_regi <= SGM_INVALID_COST;
                    end
                    else begin
                        if(lr_aggregation_en_dly[2]) begin
                            Lr_prev_min_regi <= Lr_prev_min_comb;
                        end
                    end
                end
                assign Lr0_prev_min = lr_aggregation_flag_dly[3][0] ? Lr_prev_min_regi : 0;
                assign Lr1_prev_min = lr_aggregation_flag_dly[3][1] ? Lr_prev_min_regi : 0;
                assign Lr2_prev_min = lr_aggregation_flag_dly[3][2] ? Lr_prev_min_regi : 0;
                assign Lr3_prev_min = lr_aggregation_flag_dly[3][3] ? Lr_prev_min_regi : 0;
            end
            else begin
                // invalid parameter
            end    
        end
    endgenerate
endmodule