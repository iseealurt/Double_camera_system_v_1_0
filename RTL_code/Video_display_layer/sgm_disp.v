module sgm_disp#(
    parameter 	H_SYNC    		=   12'd44  	,		// 行同步
				H_BACK    		=   12'd148 	,		// 行时序后沿
				H_LEFT    		=   12'd0   	,		// 行时序左边框（通常为0）
				H_VALID   		=   12'd1920	,		// 行有效数据
				H_RIGHT   		=   12'd0   	,		// 行时序右边框（通常为0）
				H_FRONT   		=   12'd88  	,		// 行时序前沿
				H_TOTAL   		=   12'd2200	,		// 行扫描周期

				V_SYNC    		=   12'd5   	,		// 场同步
				V_BACK    		=   12'd36  	,		// 场时序后沿
				V_TOP     		=   12'd0   	,		// 场时序上边框（通常为0）
				V_VALID   		=   12'd1080	,		// 场有效数据
				V_BOTTOM  		=   12'd0   	,		// 场时序下边框（通常为0）
				V_FRONT   		=   12'd4   	,		// 场时序前沿
				V_TOTAL   		=   12'd1125	,		// 场扫描周期

    parameter   IMG_WIDTH       =   10'd640     ,
    parameter   IMG_HEIGHT      =   10'd480     ,
    parameter   SGM_DISP_AXI_ID =   4'd8        ,
    parameter   DISP_H_OFFSET   =   160         ,
    parameter   DISP_V_OFFSET   =   562         ,
    parameter 	DDR_DQ_WIDTH	=	32			,
	parameter	PIX_DWIDTH		=	8			,
	parameter	DISP_WIDTH		=	8			,
	parameter	AXI_ADDR_WIDTH	=	28			,
	parameter	AXI_DATA_WIDTH	=	256			,
	parameter	AXI_ID_WIDTH	=	4			,
	parameter	AXI_LEN_WIDTH	=	4			,
    parameter   PIX_FIFO_WR_THRE=   9'd25       ,
    parameter   SYNC_SIG_RATE   =   10
)(
    //reset signal will be valid when @ 1'b0
    input   wire                            rst_n               ,

    //Pixel clock domain
    input   wire                            pix_clk             ,
    input   wire                            vsync_in            ,
    input   wire                            hsync_in            ,
    input   wire                            de_in               ,
    input   wire    [DISP_WIDTH-1:0]        r_chn_in            ,
    input   wire    [DISP_WIDTH-1:0]        g_chn_in            ,
    input   wire    [DISP_WIDTH-1:0]        b_chn_in            ,

    output   reg                            vsync_out           ,
    output   reg                            hsync_out           ,
    output   reg                            de_out              ,
    output   reg    [DISP_WIDTH-1:0]        r_chn_out           ,
    output   reg    [DISP_WIDTH-1:0]        g_chn_out           ,
    output   reg    [DISP_WIDTH-1:0]        b_chn_out           ,

    //AXI clock domain
    input   wire                            axi_clk             ,
    input 	wire 	[AXI_ADDR_WIDTH-1:0]	rd_buf_offset	    ,
	output 	reg 	[AXI_ID_WIDTH-1:0]		axi_ar_id			,
	output 	reg 	[AXI_LEN_WIDTH-1:0]		axi_ar_len			,
	output 	reg 	[AXI_ADDR_WIDTH-1:0]	axi_araddr			,
	output 	reg 							axi_araddr_valid	,
	input 	wire 							axi_araddr_ready	,

    input   wire                            axi_rvalid          ,
    input   wire                            axi_rlast           ,
    input   wire    [AXI_DATA_WIDTH-1:0]    axi_rdata           ,
    input   wire    [AXI_ID_WIDTH-1:0]      axi_rid             
);
    localparam DLY_VALUE = 4;

    reg [DLY_VALUE-1:0] vsync_in_dly;
    reg [DLY_VALUE-1:0] hsync_in_dly;
    reg [DLY_VALUE-1:0] de_in_dly;
    reg [DISP_WIDTH-1:0] r_chn_in_dly[DLY_VALUE-1:0];
    reg [DISP_WIDTH-1:0] g_chn_in_dly[DLY_VALUE-1:0];
    reg [DISP_WIDTH-1:0] b_chn_in_dly[DLY_VALUE-1:0];
    // VESA信号延迟链
    integer i;
    always @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            vsync_in_dly <= {DLY_VALUE{1'b0}};
            hsync_in_dly <= {DLY_VALUE{1'b0}};
            de_in_dly <= {DLY_VALUE{1'b0}};
            for (i = 0; i < DLY_VALUE; i = i + 1) begin
                r_chn_in_dly[i] <= {DISP_WIDTH{1'b0}};
                g_chn_in_dly[i] <= {DISP_WIDTH{1'b0}};
                b_chn_in_dly[i] <= {DISP_WIDTH{1'b0}};
            end
        end else begin
            // 移位寄存器延迟链
            vsync_in_dly <= {vsync_in_dly[DLY_VALUE-2:0], vsync_in};
            hsync_in_dly <= {hsync_in_dly[DLY_VALUE-2:0], hsync_in};
            de_in_dly <= {de_in_dly[DLY_VALUE-2:0], de_in};
            for (i = 0; i < DLY_VALUE; i = i + 1) begin
                if (i == 0) begin
                    r_chn_in_dly[i] <= r_chn_in;
                    g_chn_in_dly[i] <= g_chn_in;
                    b_chn_in_dly[i] <= b_chn_in;
                end else begin
                    r_chn_in_dly[i] <= r_chn_in_dly[i-1];
                    g_chn_in_dly[i] <= g_chn_in_dly[i-1];
                    b_chn_in_dly[i] <= b_chn_in_dly[i-1];
                end
            end
        end
    end

    // FIFO for data transfer @ CDC situation
    wire                            disp_pix_fifo_wr_en;
    wire   [AXI_DATA_WIDTH-1:0]     disp_pix_fifo_wr_data;
    wire   [8:0]                    disp_pix_fifo_wr_wl;

    reg                             disp_pix_fifo_rd_en;
    wire   [AXI_DATA_WIDTH-1:0]     disp_pix_fifo_rd_data;
    wire                            disp_pix_fifo_rd_empty;

    wire                            disp_pix_fifo_wr_flag;

    assign disp_pix_fifo_wr_flag = disp_pix_fifo_wr_wl <= PIX_FIFO_WR_THRE;

    drm_fifo_256b_8d u_disp_pix_fifo (
        .wr_clk                 (axi_clk                    ),
        .wr_rst                 (!rst_n                     ),
        .wr_en                  (disp_pix_fifo_wr_en        ),
        .wr_data                (disp_pix_fifo_wr_data      ),
        .wr_full                (                           ),
        .wr_water_level         (disp_pix_fifo_wr_wl        ),
        .almost_full            (                           ),
        .rd_clk                 (pix_clk                    ),
        .rd_rst                 (!rst_n                     ),
        .rd_en                  (disp_pix_fifo_rd_en        ),
        .rd_data                (disp_pix_fifo_rd_data      ),
        .rd_empty               (disp_pix_fifo_rd_empty     ),
        .almost_empty           (                           )
    );

    wire   frame_req_end_flag;

    assign disp_pix_fifo_wr_en = axi_rvalid && axi_rid == SGM_DISP_AXI_ID;
    assign disp_pix_fifo_wr_data = axi_rdata;

    wire   disp_pix_fifo_wr_end_flag;
    assign disp_pix_fifo_wr_end_flag = axi_rlast && axi_rid == SGM_DISP_AXI_ID;

    localparam FSM_CNT      = 5         ;
    localparam IDLE         = 5'b00001  ;
    localparam FRAME_BUSY   = 5'b00010  ;
    localparam REQ_ADDR_RDY = 5'b00100  ;
    localparam REQ_ADDR_END = 5'b01000  ;
    localparam FRAME_END    = 5'b10000  ;

    reg     [FSM_CNT-1:0]   axi_curr_state;
    reg     [FSM_CNT-1:0]   axi_next_state;

    // 状态转移时序逻辑
    always @(posedge axi_clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_curr_state <= IDLE;
        end else begin
            axi_curr_state <= axi_next_state;
        end
    end
    
    wire vsync_axi_synced;

    signal_sync # (
        .SIG_RATE(SYNC_SIG_RATE)
    )
    signal_sync_inst (
        .sys_clk    (axi_clk            ),
        .rst_n      (rst_n              ),
        .signal_clk (pix_clk            ),
        .sig_unsync (vsync_in           ),
        .sig_synced (vsync_axi_synced   )
    );

    // 次态组合逻辑
    always @(*) begin
        axi_next_state = axi_curr_state;
        case(axi_curr_state) 
            IDLE: begin
                if (vsync_axi_synced) begin
                    axi_next_state = FRAME_BUSY;
                end else begin
                    axi_next_state = IDLE;
                end
            end
            FRAME_BUSY: begin
                if(disp_pix_fifo_wr_flag) begin
                    axi_next_state = REQ_ADDR_RDY;
                end
            end
            REQ_ADDR_RDY: begin
                if (axi_araddr_ready && axi_araddr_valid) begin
                    axi_next_state = REQ_ADDR_END;
                end else begin
                    axi_next_state = REQ_ADDR_RDY;
                end
            end
            REQ_ADDR_END: begin
                // 检查是否完成一帧数据的地址请求
                if (disp_pix_fifo_wr_end_flag && !frame_req_end_flag) begin
                    axi_next_state = FRAME_BUSY;
                end 
                else if(disp_pix_fifo_wr_end_flag && frame_req_end_flag) begin
                    axi_next_state = FRAME_END;
                end
            end
            FRAME_END: begin
                axi_next_state = IDLE;
            end
            default: begin
                axi_next_state = IDLE;
            end
        endcase
    end
    
    localparam SINGLE_LINE_REQ_VALUE = IMG_WIDTH * PIX_DWIDTH / AXI_DATA_WIDTH;

    function integer fn_get_burst_len;
        input integer value;
        reg found;
        integer i;
        begin
            fn_get_burst_len = 1;
            found = 1'b0;
            for (i = {AXI_LEN_WIDTH{1'b1}}+1'b1; i >= 1; i = i - 1) begin
                if (!found && (value % i == 0)) begin
                    fn_get_burst_len = i;
                    found = 1'b1;
                end
            end
        end
    endfunction

    localparam SINGLE_BURST_LEN = fn_get_burst_len(SINGLE_LINE_REQ_VALUE);
    localparam TOTAL_BURST_CNT_VALUE = SINGLE_LINE_REQ_VALUE / SINGLE_BURST_LEN * IMG_HEIGHT;
    localparam TOTAL_BURST_CNT_WIDTH = $clog2(TOTAL_BURST_CNT_VALUE);
    reg     [TOTAL_BURST_CNT_WIDTH-1:0] total_busrt_cnt;
    always @(posedge axi_clk) begin
        if(!rst_n) begin
            total_busrt_cnt <= {TOTAL_BURST_CNT_WIDTH{1'b0}};
        end
        else begin
            if(axi_curr_state == IDLE) begin
                total_busrt_cnt <= {TOTAL_BURST_CNT_WIDTH{1'b0}};
            end
            else if(axi_curr_state == REQ_ADDR_RDY) begin
                if(axi_araddr_valid && axi_araddr_ready) begin
                    total_busrt_cnt <= total_busrt_cnt + 1'b1;
                end
            end
        end
    end

    assign frame_req_end_flag = disp_pix_fifo_wr_end_flag && total_busrt_cnt == TOTAL_BURST_CNT_VALUE;

    localparam AXI_ADDR_STEP_VAL = SINGLE_BURST_LEN * AXI_DATA_WIDTH / DDR_DQ_WIDTH;
    // axi ar channel
    always @(posedge axi_clk or negedge rst_n) begin
        if (!rst_n) begin
            axi_ar_id       <= {AXI_ID_WIDTH{1'b0}};
            axi_ar_len      <= {AXI_LEN_WIDTH{1'b0}};
            axi_araddr      <= {AXI_ADDR_WIDTH{1'b0}};
            axi_araddr_valid<= 1'b0;
        end else begin
            if(axi_araddr_ready && axi_araddr_valid) begin
                axi_ar_id        <= {AXI_ID_WIDTH{1'b0}};
                axi_ar_len       <= {AXI_LEN_WIDTH{1'b0}};
                axi_araddr       <= {AXI_ADDR_WIDTH{1'b0}};
                axi_araddr_valid <= 1'b0;
            end
            else begin
                case (axi_curr_state)
                    REQ_ADDR_RDY: begin
                        axi_araddr       <= total_busrt_cnt*AXI_ADDR_STEP_VAL + rd_buf_offset;
                        axi_ar_id        <= SGM_DISP_AXI_ID;
                        axi_ar_len       <= SINGLE_BURST_LEN - 1'b1;  // AXI burst length = len + 1
                        axi_araddr_valid <= 1'b1;
                    end
                    default: begin
                        axi_ar_id        <= {AXI_ID_WIDTH{1'b0}};
                        axi_ar_len       <= {AXI_LEN_WIDTH{1'b0}};
                        axi_araddr       <= {AXI_ADDR_WIDTH{1'b0}};
                        axi_araddr_valid <= 1'b0;
                    end
                endcase
            end
        end
    end

    // pixel clock damain
    localparam COL_CNT_WIDTH = $clog2(H_VALID);
    reg [COL_CNT_WIDTH-1:0] col_cnt;
    always @(posedge pix_clk ) begin
        if(!rst_n) begin
            col_cnt <= {COL_CNT_WIDTH{1'b0}};
        end
        else begin
            if(de_in) begin
                col_cnt <= col_cnt + 1'b1;
            end
            else begin
                col_cnt <= {COL_CNT_WIDTH{1'b0}};
            end
        end
    end

    localparam ROW_CNT_WIDTH = $clog2(V_VALID);
    reg [ROW_CNT_WIDTH-1:0] row_cnt;
    always @(posedge pix_clk ) begin
        if(!rst_n) begin
            row_cnt <= {ROW_CNT_WIDTH{1'b0}};
        end
        else begin
            if(!vsync_in_dly[0] && vsync_in) begin
                row_cnt <= {ROW_CNT_WIDTH{1'b0}};
            end
            else if(!de_in && de_in_dly[0]) begin
                row_cnt <= row_cnt + 1'b1;
            end
        end
    end
    
    wire h_disp_valid = col_cnt >=  DISP_H_OFFSET 
								&& col_cnt < DISP_H_OFFSET + IMG_WIDTH;
    wire v_disp_valid = row_cnt >=  DISP_V_OFFSET 
								&& row_cnt < DISP_V_OFFSET + IMG_HEIGHT;

    reg [3:0] h_disp_valid_dly;
    reg [3:0] v_disp_valid_dly;
    always @(posedge pix_clk) begin
        if(!rst_n) begin
            h_disp_valid_dly <= 4'b0000;
            v_disp_valid_dly <= 4'b0000;
        end
        else begin
            h_disp_valid_dly <= {h_disp_valid_dly[2:0], h_disp_valid};
            v_disp_valid_dly <= {v_disp_valid_dly[2:0], v_disp_valid};
        end
    end

    localparam DISP_CNT_VAL = AXI_DATA_WIDTH / PIX_DWIDTH;
    localparam DISP_CNT_WIDTH = $clog2(DISP_CNT_VAL);
    reg disp_pix_fifo_rd_en_dly;
    reg [AXI_DATA_WIDTH-1:0] pix_data_reg;
    always @(posedge pix_clk ) begin
        pix_data_reg <= disp_pix_fifo_rd_en_dly ? disp_pix_fifo_rd_data : pix_data_reg;
        disp_pix_fifo_rd_en_dly <= disp_pix_fifo_rd_en;
        disp_pix_fifo_rd_en <= !disp_pix_fifo_rd_empty && h_disp_valid && v_disp_valid && col_cnt[DISP_CNT_WIDTH-1:0] == {DISP_CNT_WIDTH{1'b0}};
    end

    reg [DISP_CNT_WIDTH-1:0] disp_cnt;

    always @(posedge pix_clk) begin
        if(!rst_n) begin
            disp_cnt <= {DISP_CNT_WIDTH{1'b0}};
        end
        else begin
            if(h_disp_valid_dly[1] && v_disp_valid_dly[1] ) begin
                disp_cnt <= disp_cnt + 1'b1;
            end
            else begin
                disp_cnt <= {DISP_CNT_WIDTH{1'b0}};
            end
        end
    end

    wire [PIX_DWIDTH-1:0] pix_disp_wire;
    reg  [PIX_DWIDTH-1:0] pix_disp;
    assign pix_disp_wire = pix_data_reg[((1 << DISP_CNT_WIDTH)-disp_cnt)*PIX_DWIDTH+:PIX_DWIDTH];

    always @(posedge pix_clk) begin
        if(!rst_n) begin
            pix_disp <= {PIX_DWIDTH{1'b0}};
        end
        else begin
            if(h_disp_valid_dly[2] && v_disp_valid_dly[2]) begin
                pix_disp <= pix_disp_wire;
            end
        end
    end

    // 对输出的图像信号进行时序逻辑赋值
    always @(posedge pix_clk or negedge rst_n) begin
        if (!rst_n) begin
            vsync_out <= 1'b0;
            hsync_out <= 1'b0;
            de_out <= 1'b0;
            r_chn_out <= {DISP_WIDTH{1'b0}};
            g_chn_out <= {DISP_WIDTH{1'b0}};
            b_chn_out <= {DISP_WIDTH{1'b0}};
        end else begin
            vsync_out <= vsync_in_dly[DLY_VALUE-1];
            hsync_out <= hsync_in_dly[DLY_VALUE-1];
            de_out <= de_in_dly[DLY_VALUE-1];
            r_chn_out <= h_disp_valid_dly[3] && v_disp_valid_dly[3] ? (!pix_disp[PIX_DWIDTH-1] ? pix_disp[DISP_WIDTH-1:0] : 8'hff) : r_chn_in_dly[DLY_VALUE-1];
            g_chn_out <= h_disp_valid_dly[3] && v_disp_valid_dly[3] ? (!pix_disp[PIX_DWIDTH-1] ? pix_disp[DISP_WIDTH-1:0] : 8'h00) : g_chn_in_dly[DLY_VALUE-1];
            b_chn_out <= h_disp_valid_dly[3] && v_disp_valid_dly[3] ? (!pix_disp[PIX_DWIDTH-1] ? pix_disp[DISP_WIDTH-1:0] : 8'h00) : b_chn_in_dly[DLY_VALUE-1];
        end
    end

endmodule