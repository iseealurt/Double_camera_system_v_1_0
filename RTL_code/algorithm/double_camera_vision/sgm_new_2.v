//cmr1 为左摄像头输入，cmr2为右摄像头输入，本模块计算左视差图
//输入：两个摄像头的census序列，要求 vsync_fifo 不为空时，
//输出：
//  a. int8格式的视差，范围为0 ~ 47 
module sgm_new_2#(
    parameter   IMG_WIDTH       =   640     ,
    parameter   IMG_HEIGHT      =   480     ,
    parameter   MAX_MATCH_DEPTH =   48      ,
    parameter   CENSUS_WIDTH    =   24      ,  
    parameter   DISPARITY_WIDTH =   8       ,
    parameter   CONFIDENCE_WIDTH=   8       ,
    parameter   CONFIDENCE_THRE =   1       ,
    parameter   SGM_P1          =   0       ,
    parameter   SGM_P2          =   0       ,
    parameter   SGM_LR_WIDTH    =   12      ,
    parameter   SGM_INVALID_COST=   24      
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

    output  reg                            disparity_vsync          ,
    output  reg                            disparity_href           ,
    output  reg    [DISPARITY_WIDTH-1:0]   disparity
);
    localparam DELAY_CHAIN_VALUE = 15;
    wire sgm_vsync;
    reg [DELAY_CHAIN_VALUE-1:0] vsync_delay_chain;
    always@(posedge sgm_clk) begin
        if(!rst_n) begin
            vsync_delay_chain <= {DELAY_CHAIN_VALUE{1'b0}};
        end
        else begin
            vsync_delay_chain <= {vsync_delay_chain[DELAY_CHAIN_VALUE-2:0],sgm_vsync};
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
                    cmr_census_fifo_rd_en <= col_cnt == IMG_WIDTH - 1 ? 1'b0 : 1'b1; //读满 640个像素后强制停止读取至少一个周期，方便观察波形
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
    reg [CENSUS_WIDTH-1:0]  xor_window[MAX_MATCH_DEPTH-1:0];
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
    reg [CENSUS_WIDTH-1:0] xor_outcome[MAX_MATCH_DEPTH-1:0];
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
    localparam HAMMING_WIDTH = $clog2(CENSUS_WIDTH + 1); // 5bit
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

    // Stage 5-6 : 代价聚合
    reg [SGM_LR_WIDTH-1:0] Lr1_curr_comb[MAX_MATCH_DEPTH-1:0];
    reg [SGM_LR_WIDTH-1:0] Lr1_curr_reg[MAX_MATCH_DEPTH-1:0];
    reg [SGM_LR_WIDTH-1:0] Lr1_prev[MAX_MATCH_DEPTH-1:0];
    reg [SGM_LR_WIDTH-1:0] Lr1_prev_dly[MAX_MATCH_DEPTH-1:0];
    reg [SGM_LR_WIDTH-1:0] Lr1_prev_min_temp[MAX_MATCH_DEPTH/6-1:0];
    reg [SGM_LR_WIDTH-1:0] Lr1_prev_min_temp_comb[MAX_MATCH_DEPTH/6-1:0];
    reg [SGM_LR_WIDTH-1:0] Lr1_prev_min_comb;

    reg [SGM_LR_WIDTH-1:0] Lr3_curr_comb[MAX_MATCH_DEPTH-1:0];
    reg [SGM_LR_WIDTH-1:0] Lr3_curr_reg[MAX_MATCH_DEPTH-1:0];
    reg [SGM_LR_WIDTH-1:0] Lr3_prev[MAX_MATCH_DEPTH-1:0];
    reg [SGM_LR_WIDTH-1:0] Lr3_prev_dly[MAX_MATCH_DEPTH-1:0];
    reg [SGM_LR_WIDTH-1:0] Lr3_prev_min_temp[MAX_MATCH_DEPTH/6-1:0];
    reg [SGM_LR_WIDTH-1:0] Lr3_prev_min_temp_comb[MAX_MATCH_DEPTH/6-1:0];
    reg [SGM_LR_WIDTH-1:0] Lr3_prev_min_comb;

    reg [SGM_LR_WIDTH-1:0] Lr_sum[MAX_MATCH_DEPTH-1:0];
    reg [COL_CNT_WIDTH-1:0] Lr_col_cnt;
    reg [ROW_CNT_WIDTH-1:0] Lr_row_cnt;

    generate
        genvar d_cnt;

        begin: Lr_row_col_cnt
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
                        Lr_row_cnt <= Lr_col_cnt == IMG_WIDTH - 1'b1 ? Lr_row_cnt + 1'b1 : Lr_row_cnt;
                    end
                end
            end
        end

        begin: Lr1_aggregation  
            reg [COL_CNT_WIDTH-1:0] Lr1_col_cnt;
            always@(posedge sgm_clk) begin
                if(!rst_n) begin
                    Lr1_col_cnt <= {COL_CNT_WIDTH{1'b0}};
                end
                else begin
                    if(pipeline_dly_chain[2]) begin
                        Lr1_col_cnt <= Lr1_col_cnt == IMG_WIDTH - 1'b1 ? {COL_CNT_WIDTH{1'b0}} : Lr1_col_cnt + 1'b1;
                    end
                    else begin
                        Lr1_col_cnt <= {COL_CNT_WIDTH{1'b0}};
                    end
                end
            end

            for(d_cnt = 0; d_cnt < MAX_MATCH_DEPTH ; d_cnt = d_cnt + 1) begin
                wire [9:0] sgm_lr1_a_addr , sgm_lr1_b_addr;
                wire [11:0] sgm_lr1_a_data ,sgm_lr1_b_data;
                // Stage 5: sgm核心算法
                always@(posedge sgm_clk) begin
                if(!rst_n) begin
                    Lr1_prev[d_cnt] <= SGM_INVALID_COST;
                    Lr1_prev_dly[d_cnt] <= SGM_INVALID_COST;
                end
                else begin
                        if(pipeline_dly_chain[3]) begin
                            Lr1_prev[d_cnt] <= sgm_lr1_b_data;
                        end

                        if(pipeline_dly_chain[4]) begin
                            Lr1_prev_dly[d_cnt] <= Lr1_prev[d_cnt];
                        end
                    end
                end

                reg [SGM_LR_WIDTH-1:0] R[3:0],Rmin;
                always@(*) begin : Lr1_curr_comb_logic
                    Lr1_curr_comb[d_cnt] = SGM_INVALID_COST;
                    R[0] = Lr1_prev_dly[d_cnt] - Lr1_prev_min_comb;
                    if(d_cnt == 0 ) begin
                        R[1] = SGM_INVALID_COST;
                    end
                    else begin
                        R[1] = Lr1_prev_dly[d_cnt-1] - Lr1_prev_min_comb + SGM_P1;
                    end
                    if(d_cnt == MAX_MATCH_DEPTH-1) begin
                        R[2] = SGM_INVALID_COST;
                    end
                    else begin
                        R[2] = Lr1_prev_dly[d_cnt+1] - Lr1_prev_min_comb + SGM_P1;
                    end
                    R[3] = SGM_P2;

                    Rmin = SGM_INVALID_COST;
                    for(i = 0 ; i < 4 ; i=i+1) begin
                        Rmin = R[i] < Rmin ? R[i] : Rmin;
                    end
                    Lr1_curr_comb[d_cnt] = Rmin + hamming_dist[d_cnt]; // 每行第1个像素不需要迭代数据
                end

                always@(posedge sgm_clk) begin : Lr1_curr_sequ_logic
                    if(!rst_n) begin
                        Lr1_curr_reg[d_cnt] <= SGM_INVALID_COST;
                    end
                    else begin
                        if((Lr_row_cnt == 0) || (pipeline_dly_chain[4] && !pipeline_dly_chain[5])) begin
                            Lr1_curr_reg[d_cnt] <= hamming_dist[d_cnt];
                        end
                        else if(pipeline_dly_chain[5]) begin
                            Lr1_curr_reg[d_cnt] <= Lr1_curr_comb[d_cnt];
                        end
                    end
                end

                wire sgm_lr1_ram_rst;
                assign sgm_lr1_ram_rst = (!rst_n) || (vsync_delay_chain[5] && !vsync_delay_chain[6]);
                assign sgm_lr1_a_addr = Lr_col_cnt;
                assign sgm_lr1_b_addr = Lr1_col_cnt == 0  ? 0 : Lr1_col_cnt - 1'b1 ;
                // Stage 6 : Lr1_prev赋值
                sgm_lr2_ram sgm_lr1_ram_inst (
                    .a_addr(sgm_lr1_a_addr),            // input [9:0]
                    .a_wr_data(Lr1_curr_reg[d_cnt]),    // input [11:0]
                    .a_rd_data(),                       // output [11:0]
                    .a_wr_en(pipeline_dly_chain[6]),    // input
                    .a_clk(sgm_clk),                    // input
                    .a_rst(sgm_lr1_ram_rst),            // input
                    .b_addr(sgm_lr1_b_addr),            // input [9:0]
                    .b_wr_data(),                       // input [11:0]
                    .b_rd_data(sgm_lr1_b_data),         // output [11:0]
                    .b_wr_en(1'b0),                     // input
                    .b_clk(sgm_clk),                    // input
                    .b_rst(sgm_lr1_ram_rst)             // input
                );
            end

            always@(*) begin
                for(i=0;i<MAX_MATCH_DEPTH/6 ;i=i+1) begin
                    Lr1_prev_min_temp_comb[i] = SGM_INVALID_COST;
                    for(j=0;j<6;j=j+1) begin
                        if(Lr1_prev[i*6+j] < Lr1_prev_min_temp_comb[i]) begin
                            Lr1_prev_min_temp_comb[i] = Lr1_prev[i*6+j];
                        end
                    end
                end
            end

            always@(posedge sgm_clk) begin
                for(i=0;i<MAX_MATCH_DEPTH/6 ;i=i+1) begin
                    if(pipeline_dly_chain[4]) begin
                        Lr1_prev_min_temp[i] <= Lr1_prev_min_temp_comb[i];
                    end
                end
            end

            always@(*) begin
                Lr1_prev_min_comb = SGM_INVALID_COST;
                for(i=0;i<MAX_MATCH_DEPTH/6 ;i=i+1) begin
                    if(Lr1_prev_min_temp[i] < Lr1_prev_min_comb) begin
                        Lr1_prev_min_comb = Lr1_prev_min_temp[i];
                    end
                end
            end
        end
        
        begin: Lr3_aggregation  
            reg [COL_CNT_WIDTH-1:0] Lr3_col_cnt;
            always@(posedge sgm_clk) begin
                if(!rst_n) begin
                    Lr3_col_cnt <= {COL_CNT_WIDTH{1'b0}};
                end
                else begin
                    if(pipeline_dly_chain[2]) begin
                        Lr3_col_cnt <= Lr3_col_cnt == IMG_WIDTH - 1'b1 ? {COL_CNT_WIDTH{1'b0}} : Lr3_col_cnt + 1'b1;
                    end
                    else begin
                        Lr3_col_cnt <= {COL_CNT_WIDTH{1'b0}};
                    end
                end
            end

            for(d_cnt = 0; d_cnt < MAX_MATCH_DEPTH ; d_cnt = d_cnt + 1) begin
                wire [9:0] sgm_lr3_a_addr , sgm_lr3_b_addr;
                wire [11:0] sgm_lr3_a_data ,sgm_lr3_b_data;
                // Stage 5: sgm核心算法
                always@(posedge sgm_clk) begin
                if(!rst_n) begin
                    Lr3_prev[d_cnt] <= SGM_INVALID_COST;
                    Lr3_prev_dly[d_cnt] <= SGM_INVALID_COST;
                end
                else begin
                        if(pipeline_dly_chain[3]) begin
                            Lr3_prev[d_cnt] <= sgm_lr3_b_data;
                        end

                        if(pipeline_dly_chain[4]) begin
                            Lr3_prev_dly[d_cnt] <= Lr3_prev[d_cnt];
                        end
                    end
                end

                reg [SGM_LR_WIDTH-1:0] R[3:0],Rmin;
                always@(*) begin : Lr3_curr_comb_logic
                    Lr3_curr_comb[d_cnt] = SGM_INVALID_COST;
                    R[0] = Lr3_prev_dly[d_cnt] - Lr3_prev_min_comb;
                    if(d_cnt == 0 ) begin
                        R[1] = SGM_INVALID_COST;
                    end
                    else begin
                        R[1] = Lr3_prev_dly[d_cnt-1] - Lr3_prev_min_comb + SGM_P1;
                    end
                    if(d_cnt == MAX_MATCH_DEPTH-1) begin
                        R[2] = SGM_INVALID_COST;
                    end
                    else begin
                        R[2] = Lr3_prev_dly[d_cnt+1] - Lr3_prev_min_comb + SGM_P1;
                    end
                    R[3] = SGM_P2;

                    Rmin = SGM_INVALID_COST;
                    for(i = 0 ; i < 4 ; i=i+1) begin
                        Rmin = R[i] < Rmin ? R[i] : Rmin;
                    end
                    Lr3_curr_comb[d_cnt] = Rmin + hamming_dist[d_cnt]; // 每行第1个像素不需要迭代数据
                end

                always@(posedge sgm_clk) begin : Lr3_curr_sequ_logic
                    if(!rst_n) begin
                        Lr3_curr_reg[d_cnt] <= SGM_INVALID_COST;
                    end
                    else begin
                        if((Lr_row_cnt == 0) || (!pipeline_dly_chain[4] && pipeline_dly_chain[5])) begin
                            Lr3_curr_reg[d_cnt] <= hamming_dist[d_cnt];
                        end
                        else if(pipeline_dly_chain[5]) begin
                            Lr3_curr_reg[d_cnt] <= Lr3_curr_comb[d_cnt];
                        end
                    end
                end

                wire sgm_lr3_ram_rst;
                assign sgm_lr3_ram_rst = (!rst_n) || (vsync_delay_chain[5] && !vsync_delay_chain[6]);
                assign sgm_lr3_a_addr = Lr_col_cnt;
                assign sgm_lr3_b_addr = Lr3_col_cnt < IMG_WIDTH - 1'b1  ? Lr3_col_cnt + 1'b1 : IMG_WIDTH - 1'b1 ;
                // Stage 6 : Lr3_prev赋值
                sgm_lr2_ram sgm_lr3_ram_inst (
                    .a_addr(sgm_lr3_a_addr),            // input [9:0]
                    .a_wr_data(Lr3_curr_reg[d_cnt]),    // input [11:0]
                    .a_rd_data(),                       // output [11:0]
                    .a_wr_en(pipeline_dly_chain[6]),    // input
                    .a_clk(sgm_clk),                    // input
                    .a_rst(sgm_lr3_ram_rst),            // input
                    .b_addr(sgm_lr3_b_addr),            // input [9:0]
                    .b_wr_data(),                       // input [11:0]
                    .b_rd_data(sgm_lr3_b_data),         // output [11:0]
                    .b_wr_en(1'b0),                     // input
                    .b_clk(sgm_clk),                    // input
                    .b_rst(sgm_lr3_ram_rst)             // input
                );
            end
            always@(*) begin
                for(i=0;i<MAX_MATCH_DEPTH/6 ;i=i+1) begin
                    Lr3_prev_min_temp_comb[i] = SGM_INVALID_COST;
                    for(j=0;j<6;j=j+1) begin
                        if(Lr3_prev[i*6+j] < Lr3_prev_min_temp_comb[i]) begin
                            Lr3_prev_min_temp_comb[i] = Lr3_prev[i*6+j];
                        end
                    end
                end
            end

            always@(posedge sgm_clk) begin
                for(i=0;i<MAX_MATCH_DEPTH/6 ;i=i+1) begin
                    if(pipeline_dly_chain[4]) begin
                        Lr3_prev_min_temp[i] <= Lr3_prev_min_temp_comb[i];
                    end
                end
            end

            always@(*) begin
                Lr3_prev_min_comb = SGM_INVALID_COST;
                for(i=0;i<MAX_MATCH_DEPTH/6 ;i=i+1) begin
                    if(Lr3_prev_min_temp[i] < Lr3_prev_min_comb) begin
                        Lr3_prev_min_comb = Lr3_prev_min_temp[i];
                    end
                end
            end
        end

        // Stage 6: 代价值统合
        begin: cost_sum
            for(d_cnt = 0 ; d_cnt < MAX_MATCH_DEPTH ; d_cnt = d_cnt +1) begin
                always@(posedge sgm_clk) begin
                    if(!rst_n) begin
                        Lr_sum[d_cnt] <= SGM_INVALID_COST;
                    end
                    else begin
                        if(pipeline_dly_chain[6]) begin
                            //Lr_sum[d_cnt] <= Lr0_curr_reg[d_cnt];
                            //Lr_sum[d_cnt] <= Lr1_curr_reg[d_cnt];
                            //Lr_sum[d_cnt] <= Lr2_curr_reg[d_cnt];
                            //Lr_sum[d_cnt] <= Lr3_curr_reg[d_cnt];
                            Lr_sum[d_cnt] <= Lr1_curr_reg[d_cnt] + Lr3_curr_reg[d_cnt];
                        end  
                    end
                end
            end
        end
    endgenerate
    localparam WTA_DELAY_VAL = 6;
    localparam LR_SUM_DLY_WIDTH = MAX_MATCH_DEPTH*SGM_LR_WIDTH;
    reg     [LR_SUM_DLY_WIDTH-1:0] Lr_sum_dly[WTA_DELAY_VAL-1:0];

    always @(posedge sgm_clk) begin
        if(!rst_n) begin
            for(i=0;i<WTA_DELAY_VAL;i=i+1) begin
                Lr_sum_dly[i] <= {LR_SUM_DLY_WIDTH{1'b0}};
            end
        end
        else begin
            for (i=0; i < MAX_MATCH_DEPTH; i=i+1) begin
                if(pipeline_dly_chain[7]) begin
                    Lr_sum_dly[0][i*SGM_LR_WIDTH+:SGM_LR_WIDTH] <= Lr_sum[i];
                end
            end
            for(i=1;i< WTA_DELAY_VAL ;i=i+1) begin
                if(pipeline_dly_chain[i+7]) begin
                    Lr_sum_dly[i] <=  Lr_sum_dly[i-1];
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
        // stage 7 ~ 12: 6级比较树实现WTA策略
        begin : WTA_compare_tree
            // stage 7 : 第一级比较树
            genvar tree_cnt0;
            reg [SGM_LR_WIDTH-1:0] Lr_min_compare_tree_temp0[MAX_MATCH_DEPTH/2-1:0]; // 24*12 = 288 D-triggers
            reg [SGM_LR_WIDTH-1:0] Lr_second_min_compare_tree_temp0[MAX_MATCH_DEPTH/2-1:0];
            reg [DISPARITY_WIDTH-1:0] best_d_temp0[MAX_MATCH_DEPTH/2-1:0];
            for(tree_cnt0=0; tree_cnt0<MAX_MATCH_DEPTH/2; tree_cnt0=tree_cnt0+1) begin
                always @(posedge sgm_clk) begin :  Lr_min_compare_tree_stg1
                    if(!rst_n) begin
                        Lr_min_compare_tree_temp0[tree_cnt0] <= {SGM_LR_WIDTH{1'B1}};
                        Lr_second_min_compare_tree_temp0[tree_cnt0] <= {SGM_LR_WIDTH{1'B1}};
                        best_d_temp0[tree_cnt0] <= {DISPARITY_WIDTH{1'b0}};
                    end
                    else begin
                        if(pipeline_dly_chain[7]) begin
                            Lr_min_compare_tree_temp0[tree_cnt0] <= Lr_sum[2*tree_cnt0] <= Lr_sum[2*tree_cnt0+1] ? Lr_sum[2*tree_cnt0] : Lr_sum[2*tree_cnt0+1];
                            Lr_second_min_compare_tree_temp0[tree_cnt0] <= Lr_sum[2*tree_cnt0] <= Lr_sum[2*tree_cnt0+1] ? Lr_sum[2*tree_cnt0+1] : Lr_sum[2*tree_cnt0];
                            best_d_temp0[tree_cnt0] <= Lr_sum[2*tree_cnt0] <= Lr_sum[2*tree_cnt0+1] ? 2*tree_cnt0 : 2*tree_cnt0+1;
                        end
                    end
                end  
            end

            // stage 8 : 第二级比较树
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
                always @(posedge sgm_clk) begin :  Lr_min_compare_tree_stg2
                    if(!rst_n) begin
                        Lr_min_compare_tree_temp1[tree_cnt1] <= {SGM_LR_WIDTH{1'B1}};
                        Lr_second_min_compare_tree_temp1[tree_cnt1] <= {SGM_LR_WIDTH{1'B1}};
                        best_d_temp1[tree_cnt1] <= {DISPARITY_WIDTH{1'b0}};
                    end
                    else begin
                        if(pipeline_dly_chain[8]) begin
                            Lr_min_compare_tree_temp1[tree_cnt1] <= Lr_min_compare_tree_temp0[2*tree_cnt1] <= Lr_min_compare_tree_temp0[2*tree_cnt1+1] ? Lr_min_compare_tree_temp0[2*tree_cnt1] : Lr_min_compare_tree_temp0[2*tree_cnt1+1];
                            Lr_second_min_compare_tree_temp1[tree_cnt1] <= stg6_max_lr <= stg6_min_2nd ? stg6_max_lr : stg6_min_2nd;
                            best_d_temp1[tree_cnt1] <= Lr_min_compare_tree_temp0[2*tree_cnt1] <= Lr_min_compare_tree_temp0[2*tree_cnt1+1] ? best_d_temp0[2*tree_cnt1] : best_d_temp0[2*tree_cnt1+1];
                        end
                    end
                end  
            end

            // stage 9 : 第三级比较树
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
                always @(posedge sgm_clk) begin :  Lr_min_compare_tree_stg3
                    if(!rst_n) begin
                        Lr_min_compare_tree_temp2[tree_cnt2] <= {SGM_LR_WIDTH{1'B1}};
                        Lr_second_min_compare_tree_temp2[tree_cnt2] <= {SGM_LR_WIDTH{1'B1}};
                        best_d_temp2[tree_cnt2] <= {DISPARITY_WIDTH{1'b0}};
                    end
                    else begin
                        if(pipeline_dly_chain[9]) begin
                            Lr_min_compare_tree_temp2[tree_cnt2] <= Lr_min_compare_tree_temp1[2*tree_cnt2] <= Lr_min_compare_tree_temp1[2*tree_cnt2+1] ? Lr_min_compare_tree_temp1[2*tree_cnt2] : Lr_min_compare_tree_temp1[2*tree_cnt2+1];
                            Lr_second_min_compare_tree_temp2[tree_cnt2] <= stg7_max_lr <= stg7_min_2nd ? stg7_max_lr : stg7_min_2nd;
                            best_d_temp2[tree_cnt2] <= Lr_min_compare_tree_temp1[2*tree_cnt2] <= Lr_min_compare_tree_temp1[2*tree_cnt2+1] ? best_d_temp1[2*tree_cnt2] : best_d_temp1[2*tree_cnt2+1];
                        end
                    end
                end  
            end

            // stage 10 : 第四级比较树
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
                always @(posedge sgm_clk) begin :  Lr_min_compare_tree_stg4
                    if(!rst_n) begin
                        Lr_min_compare_tree_temp3[tree_cnt3] <= {SGM_LR_WIDTH{1'B1}};
                        Lr_second_min_compare_tree_temp3[tree_cnt3] <= {SGM_LR_WIDTH{1'B1}};
                        best_d_temp3[tree_cnt3] <= {DISPARITY_WIDTH{1'b0}};
                    end
                    else begin
                        if(pipeline_dly_chain[10]) begin
                            Lr_min_compare_tree_temp3[tree_cnt3] <= Lr_min_compare_tree_temp2[2*tree_cnt3] <= Lr_min_compare_tree_temp2[2*tree_cnt3+1] ? Lr_min_compare_tree_temp2[2*tree_cnt3] : Lr_min_compare_tree_temp2[2*tree_cnt3+1];
                            Lr_second_min_compare_tree_temp3[tree_cnt3] <= stg8_max_lr <= stg8_min_2nd ? stg8_max_lr : stg8_min_2nd;
                            best_d_temp3[tree_cnt3] <= Lr_min_compare_tree_temp2[2*tree_cnt3] <= Lr_min_compare_tree_temp2[2*tree_cnt3+1] ? best_d_temp2[2*tree_cnt3] : best_d_temp2[2*tree_cnt3+1];
                        end
                    end
                end  
            end

            // stage 11 : 第五级比较树
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
            always @(posedge sgm_clk) begin :  Lr_min_compare_tree_stg5
                if(!rst_n) begin
                    Lr_min_compare_tree_temp4[0] <= {SGM_LR_WIDTH{1'B1}};
                    Lr_min_compare_tree_temp4[1] <= {SGM_LR_WIDTH{1'B1}};
                    Lr_second_min_compare_tree_temp4[0] <= {SGM_LR_WIDTH{1'B1}};
                    Lr_second_min_compare_tree_temp4[1] <= {SGM_LR_WIDTH{1'B1}};
                    best_d_temp4[0] <= {DISPARITY_WIDTH{1'b0}};
                    best_d_temp4[1] <= {DISPARITY_WIDTH{1'b0}};
                end
                else begin
                    if(pipeline_dly_chain[11]) begin
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
            // stage 12: 第六级比较树，合并 temp4[0] 和 temp4[1] 得到全局最小和第二小
            wire [SGM_LR_WIDTH-1:0] stg10_max_lr;
            wire [SGM_LR_WIDTH-1:0] stg10_min_2nd;
            assign stg10_max_lr = Lr_min_compare_tree_temp4[0] <= Lr_min_compare_tree_temp4[1] ?
                Lr_min_compare_tree_temp4[1] : Lr_min_compare_tree_temp4[0];
            assign stg10_min_2nd = Lr_second_min_compare_tree_temp4[0] <= Lr_second_min_compare_tree_temp4[1] ?
                Lr_second_min_compare_tree_temp4[0] : Lr_second_min_compare_tree_temp4[1];
            always @(posedge sgm_clk) begin :  Lr_min_compare_tree_stg6
                if(!rst_n) begin
                    Lr_min <= {SGM_LR_WIDTH{1'B1}};
                    Lr_second_min <= {SGM_LR_WIDTH{1'B1}};
                    best_disparity <= {DISPARITY_WIDTH{1'b0}};
                end
                else begin
                    if(pipeline_dly_chain[12]) begin
                        Lr_min <= Lr_min_compare_tree_temp4[0] <= Lr_min_compare_tree_temp4[1] ? Lr_min_compare_tree_temp4[0] : Lr_min_compare_tree_temp4[1];
                        Lr_second_min <= stg10_max_lr <= stg10_min_2nd ? stg10_max_lr : stg10_min_2nd;
                        best_disparity <= Lr_min_compare_tree_temp4[0] <= Lr_min_compare_tree_temp4[1] ? best_d_temp4[0] : best_d_temp4[1];
                    end
                end
            end  
            // stage 13: 置信度计算
            always @(posedge sgm_clk) begin
                if(!rst_n) begin
                    best_disparity_dly <= {DISPARITY_WIDTH{1'b0}};
                    confidence_reg <= {CONFIDENCE_WIDTH{1'b0}};
                end
                else begin
                    if(pipeline_dly_chain[13]) begin
                        best_disparity_dly <= best_disparity;
                        confidence_reg <= Lr_second_min - Lr_min;
                    end
                end
            end
        end
    endgenerate

    reg [SGM_LR_WIDTH-1:0] Cd,Cd_plus_1,Cd_minus_1;

    always @(posedge sgm_clk) begin
        if(!rst_n) begin
            Cd <= {SGM_LR_WIDTH{1'b0}};
            Cd_plus_1 <= {SGM_LR_WIDTH{1'b0}};
            Cd_minus_1 <= {SGM_LR_WIDTH{1'b0}};
        end
        else begin
            if(pipeline_dly_chain[13]) begin
                Cd <= Lr_min;
                if(best_disparity == 0) begin
                    Cd_plus_1 <= {SGM_LR_WIDTH{1'b0}};
                    Cd_minus_1 <= {SGM_LR_WIDTH{1'b0}};
                end
                else if(best_disparity == MAX_MATCH_DEPTH-1) begin
                    Cd_plus_1 <= {SGM_LR_WIDTH{1'b0}};
                    Cd_minus_1 <= {SGM_LR_WIDTH{1'b0}};
                end
                else begin
                    Cd_plus_1 <= Lr_sum_dly[WTA_DELAY_VAL-1][(best_disparity+1'b1)*SGM_LR_WIDTH+:SGM_LR_WIDTH];
                    Cd_minus_1 <= Lr_sum_dly[WTA_DELAY_VAL-1][(best_disparity-1'b1)*SGM_LR_WIDTH+:SGM_LR_WIDTH];
                end
            end
        end
    end

    reg signed [1:0] subpixel_bias;
    reg     [CONFIDENCE_WIDTH-1:0] confidence_reg_dly;
    always @(posedge sgm_clk) begin
        if(!rst_n) begin
            subpixel_bias <= 2'sd0;
            confidence_reg_dly <= {CONFIDENCE_WIDTH{1'b0}};
        end
        else begin
            if(pipeline_dly_chain[14]) begin
                confidence_reg_dly <= confidence_reg;
                if(best_disparity_dly == 0 || best_disparity_dly == MAX_MATCH_DEPTH-1) begin
                    subpixel_bias <= 2'sd0;
                end
                else begin
                    if(Cd_plus_1 < Cd_minus_1) begin
                        subpixel_bias <= 2'sd1;
                    end
                    else if(Cd_minus_1 < Cd_plus_1) begin
                        subpixel_bias <= -2'sd1;
                    end
                    else begin
                        subpixel_bias <= 2'sd0;
                    end
                end
            end
        end
    end

    always @(posedge sgm_clk) begin
        disparity_vsync <= vsync_delay_chain[14];
        disparity_href <= pipeline_dly_chain[14];
        disparity[DISPARITY_WIDTH-1] <= confidence_reg_dly >= CONFIDENCE_THRE ? 1'b0 : 1'b1;
        disparity[DISPARITY_WIDTH-2:0] <= (subpixel_bias == 2'sd1) ? ({best_disparity_dly, 1'b0} + 1'b1) :
                                            (subpixel_bias == -2'sd1) ? ({best_disparity_dly, 1'b0} - 1'b1) :
                                            {best_disparity_dly, 1'b0};
    end
    
endmodule