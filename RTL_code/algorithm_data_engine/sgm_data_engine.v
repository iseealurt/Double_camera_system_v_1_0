`timescale 1ps/1ps
module sgm_data_engine#(
	parameter 	H_SYNC    		=   12'd3    	,		// 行同步
				H_BACK    		=   12'd0   	,		// 行时序后沿
				H_LEFT    		=   12'd0   	,		// 行时序左边框（通常为0）
				H_VALID   		=   12'd640 	,		// 行有效数据
				H_RIGHT   		=   12'd0   	,		// 行时序右边框（通常为0）
				H_FRONT   		=   12'd3    	,		// 行时序前沿
				H_TOTAL   		=   12'd646 	,		// 行扫描周期

				V_SYNC    		=   12'd5   	,		// 场同步
				V_BACK    		=   12'd10   	,		// 场时序后沿
				V_TOP     		=   12'd0     	,		// 场时序上边框（通常为0）
				V_VALID   		=   12'd480	    ,		// 场有效数据
				V_BOTTOM  		=   12'd0   	,		// 场时序下边框（通常为0）
				V_FRONT   		=   12'd5   	,		// 场时序前沿
				V_TOTAL   		=   12'd500	    ,		// 场扫描周期
	
	parameter 	CMR_1_AXI_ID	=	4'b0001		,
	parameter 	CMR_2_AXI_ID	=	4'b0010		,
	parameter 	DDR_DQ_WIDTH	=	32			,
	parameter	PIX_DWIDTH		=	16			,
	parameter	DISP_WIDTH		=	8			,
	parameter	AXI_ADDR_WIDTH	=	28			,
	parameter	AXI_DATA_WIDTH	=	256			,
	parameter	AXI_R_LEN_BASE	=	4'b0111		,
	parameter	AXI_ID_WIDTH	=	4			,
	parameter	AXI_LEN_WIDTH	=	4			
)(
	input 	wire 							rst_n				,
	input 	wire 							pix_clk				, // 19.38 MHz时钟驱动 远大于 646 * 500 * 60 = 19.38MHz，满足实时性要求
	
	input 	wire 	[7:0]					cmr_1_pix_fifo_wr_wl, //wr端是AXI总线的时钟域
	input 	wire 	[7:0]					cmr_2_pix_fifo_wr_wl,
	
	input 	wire 							camera_1_rd_de		,
	input 	wire 	[AXI_DATA_WIDTH-1:0]	camera_1_rd_data	,
	output 	wire 							camera_1_rd_req		,
	
	input 	wire 							camera_2_rd_de		,
	input 	wire 	[AXI_DATA_WIDTH-1:0]	camera_2_rd_data	,
	output 	wire 							camera_2_rd_req		,
	
	output 	reg 							vsync				,
	output 	reg 							href				,

	output 	reg 	[DISP_WIDTH-1:0]		l_r_chn				,	
	output 	reg 	[DISP_WIDTH-1:0]		l_g_chn				,	
	output 	reg 	[DISP_WIDTH-1:0]		l_b_chn				,	
	
    output 	reg 	[DISP_WIDTH-1:0]		r_r_chn				,	
	output 	reg 	[DISP_WIDTH-1:0]		r_g_chn				,	
	output 	reg 	[DISP_WIDTH-1:0]		r_b_chn				,

	input 	wire 	[AXI_ADDR_WIDTH-1:0]	cmr_1_rd_buf_ofst	,
	input 	wire 	[AXI_ADDR_WIDTH-1:0]	cmr_2_rd_buf_ofst	,

	input 	wire 							axi_clk				,

	output 	reg 	[AXI_ID_WIDTH-1:0]		axi_ar_id			,
	output 	reg 	[AXI_LEN_WIDTH-1:0]		axi_ar_len			,
	output 	reg 	[AXI_ADDR_WIDTH-1:0]	axi_araddr			,
	output 	reg 							axi_araddr_valid	,
	input 	wire 							axi_araddr_ready	,

    input   wire    [AXI_ID_WIDTH-1:0]      axi_rd_id           ,
    input   wire                            axi_rlast          
);
	//	---------------- Display layer ----------------		
	//  Internal Registers 
	reg		[11:0] 		cnt_h;
	reg 	[11:0] 		cnt_v;
	
	always @(posedge pix_clk) begin
		if (!rst_n)
			cnt_h <= 12'd0;
		else if (cnt_h == H_TOTAL - 1)
			cnt_h <= 12'd0;
		else
			cnt_h <= cnt_h + 1;
	end

	//  Vertical Counter 
	always @(posedge pix_clk) begin
		if (!rst_n)
			cnt_v <= 12'd0;
		else if ((cnt_h == H_TOTAL - 1) && (cnt_v == V_TOTAL - 1))
			cnt_v <= 12'd0;
		else if (cnt_h == H_TOTAL - 1)
			cnt_v <= cnt_v + 1;
	end
	
	//  Video valid Area Flags 
	wire 	in_h_valid;
	assign in_h_valid = (cnt_h >= H_SYNC + H_BACK + H_LEFT) &&
					  (cnt_h <  H_SYNC + H_BACK + H_LEFT + H_VALID);

	wire 	in_v_valid;
	assign in_v_valid = (cnt_v >= V_SYNC + V_BACK + V_TOP ) &&
					  (cnt_v <  V_SYNC + V_BACK + V_TOP + V_VALID );
					
	//  Sync Signals 
	
	reg 	in_vsync;
	reg 	in_href;
	reg		[4:0]	in_href_dly;
	reg		[4:0]	in_vsync_dly;
	always @(posedge pix_clk) begin
		if (!rst_n) begin
			in_href <= 1'b0;
			in_vsync <= 1'b0;
			in_href_dly <= 2'b00;
			in_vsync_dly <= 2'b00;
		end
		else begin
			in_href <= in_h_valid && in_v_valid;
			in_vsync <= (cnt_v < V_SYNC) ? 1'b1 : 1'b0;
			in_href_dly <= {in_href_dly[3:0],in_href};
			in_vsync_dly <= {in_vsync_dly[3:0],in_vsync};
		end
	end
	
	reg 			cmr_disp_valid;
	reg 	[2:0]	cmr_disp_valid_dly;
	always @(posedge pix_clk) begin
		if (!rst_n) begin
			cmr_disp_valid <= 1'b0;
			cmr_disp_valid_dly <= 3'b00;
		end
		else begin
			cmr_disp_valid <= in_href;
			cmr_disp_valid_dly <= {cmr_disp_valid_dly[1:0],cmr_disp_valid};
		end
	end
	
	reg 	[3:0]	cmr_rd_cnt;
	reg 	[3:0]	cmr_rd_cnt_dly[1:0];
	always @(posedge pix_clk) begin
		if (!rst_n) begin
			cmr_rd_cnt <= 4'd0;
			cmr_rd_cnt_dly[0] <= 4'd0;
		end
		else begin
			cmr_rd_cnt_dly[0] <= cmr_rd_cnt;
			cmr_rd_cnt_dly[1] <= cmr_rd_cnt_dly[0];
			if(cmr_disp_valid) begin
				cmr_rd_cnt <= cmr_rd_cnt + 4'd1;
			end
			else begin
				cmr_rd_cnt <= 4'd0;
			end	
		end
	end
	
	//注意FIFO必须是预读模式，
	//目前FIFO不是预读模式，所以会有显示不正常的情况，需要进行时序的调整
	assign camera_1_rd_req = cmr_rd_cnt == 4'd0 && camera_1_rd_de && cmr_disp_valid;
	assign camera_2_rd_req = cmr_rd_cnt == 4'd0 && camera_2_rd_de && cmr_disp_valid;
	
	reg 	[AXI_DATA_WIDTH-1:0]	camera_1_rd_data_reg;
	reg 	[AXI_DATA_WIDTH-1:0]	camera_2_rd_data_reg;
	
	always @(posedge pix_clk) begin
		if (!rst_n) begin
			camera_1_rd_data_reg <= 'd0;
			camera_2_rd_data_reg <= 'd0;
		end
		else begin
			camera_1_rd_data_reg <= camera_1_rd_data;
			camera_2_rd_data_reg <= camera_2_rd_data;
		end
	end

    //
	reg 	[PIX_DWIDTH-1:0]	l_pix_disp_pre;
	reg 	[PIX_DWIDTH-1:0]	l_pix_disp;
	reg 	[PIX_DWIDTH-1:0]	r_pix_disp_pre;
	reg 	[PIX_DWIDTH-1:0]	r_pix_disp;

	always @(posedge pix_clk) begin
		if (!rst_n) begin
			l_pix_disp <= 0;
			l_pix_disp_pre <= 0;
            r_pix_disp <= 0;
			r_pix_disp_pre <= 0;
		end
		else begin
			if(cmr_disp_valid_dly[1]) begin
				l_pix_disp_pre <= camera_1_rd_data_reg[cmr_rd_cnt_dly[1]*16+:16];
                r_pix_disp_pre <= camera_2_rd_data_reg[cmr_rd_cnt_dly[1]*16+:16];
			end
			else begin
				l_pix_disp_pre <= 16'hffff;
                r_pix_disp_pre <= 16'hffff;
			end
			l_pix_disp <= l_pix_disp_pre;
            r_pix_disp <= r_pix_disp_pre;
		end
	end
	
	always @(posedge pix_clk) begin
		if (!rst_n) begin
			href <= 1'b0;
			vsync <= 1'b0;
			l_r_chn <= 8'd0;
			l_g_chn <= 8'd0;
			l_b_chn <= 8'd0;
            r_r_chn <= 8'd0;
			r_g_chn <= 8'd0;
			r_b_chn <= 8'd0;
		end
		else begin
			href <= in_href_dly[4];
			vsync <= in_vsync_dly[4];
			l_r_chn <= l_pix_disp[15:11] << 3;
			l_g_chn <= l_pix_disp[10:5 ] << 2;
			l_b_chn <= l_pix_disp[4 :0 ] << 3;
            r_r_chn <= r_pix_disp[15:11] << 3;
			r_g_chn <= r_pix_disp[10:5 ] << 2;
			r_b_chn <= r_pix_disp[4 :0 ] << 3;
		end
	end
	
	
	// ---------------- AXI master layer ----------------
	localparam	CMR_1_REQ_CTN_THRESHOLD = H_VALID * PIX_DWIDTH / AXI_DATA_WIDTH / 2 ;
	localparam	CMR_2_REQ_CTN_THRESHOLD = H_VALID * PIX_DWIDTH / AXI_DATA_WIDTH / 2 ;	
	
	localparam 	IDLE				=	8'b00000001	,	
				FRAME_REQ_RDY		=	8'b00000010	,	
				CMR_1_ADDR_RDY		=	8'b00000100	,	
				CMR_1_ADDR_END		=	8'b00001000	,	
				CMR_2_ADDR_RDY		=	8'b00010000	,	
				CMR_2_ADDR_END		=	8'b00100000	,	
				SINGLE_BURST_END	= 	8'b10000000	,
				FRAME_REQ_END		=	8'b01000000	;
	
	localparam 	FSM_CNT	=	8;
	
	wire 					vsync_axi_synced;
	reg 					vsync_axi_synced_reg;

	reg 	[FSM_CNT-1:0] 	cur_state;
	reg 	[FSM_CNT-1:0] 	nex_state;
	
	wire 					frame_req_end_flag;
	signal_sync#(
		.SIG_RATE					(4'd10						)
	)vsync_axi_sync(
		.sys_clk					(axi_clk					),
		.rst_n						(rst_n						),
		.signal_clk					(pix_clk					),
		.sig_unsync					(in_vsync					),
		.sig_synced					(vsync_axi_synced			)	
	);
	
	always@(posedge axi_clk) begin
		if(!rst_n) begin
			vsync_axi_synced_reg <= 1'b0;
		end
		else begin
			vsync_axi_synced_reg <= vsync_axi_synced;
		end
	end
	
	always@(*) begin
		nex_state = cur_state;
		case(cur_state) 
			IDLE			:begin 
				if(!vsync_axi_synced && vsync_axi_synced_reg) begin
					nex_state = FRAME_REQ_RDY;
				end
			end			
			FRAME_REQ_RDY	:begin 
				if(cmr_1_pix_fifo_wr_wl <= CMR_1_REQ_CTN_THRESHOLD) begin
					nex_state = CMR_1_ADDR_RDY;
				end
                else if(cmr_2_pix_fifo_wr_wl <= CMR_2_REQ_CTN_THRESHOLD) begin
                    nex_state = CMR_2_ADDR_RDY;
                end
			end			
			CMR_1_ADDR_RDY	:begin 
				if(axi_araddr_ready && axi_araddr_valid && axi_ar_id == CMR_1_AXI_ID) begin
					nex_state = CMR_1_ADDR_END;
				end
			end			
			CMR_1_ADDR_END	:begin 
                if(axi_rlast && axi_rd_id == CMR_1_AXI_ID) begin
					nex_state = SINGLE_BURST_END;
				end		
			end	
			CMR_2_ADDR_RDY	:begin 
				if(axi_araddr_ready && axi_araddr_valid && axi_ar_id == CMR_2_AXI_ID) begin
					nex_state = CMR_2_ADDR_END;
				end
			end			
			CMR_2_ADDR_END	:begin 
				if(axi_rlast && axi_rd_id == CMR_2_AXI_ID) begin
					nex_state = SINGLE_BURST_END;
				end	
			end	
			SINGLE_BURST_END:begin
				if(frame_req_end_flag) begin
					nex_state = FRAME_REQ_END;
				end
				else if(cmr_1_pix_fifo_wr_wl <= CMR_1_REQ_CTN_THRESHOLD) begin
					nex_state = CMR_1_ADDR_RDY;
				end
                else if(cmr_2_pix_fifo_wr_wl <= CMR_2_REQ_CTN_THRESHOLD) begin
                    nex_state = CMR_2_ADDR_RDY;
                end 
			end
			FRAME_REQ_END	:begin 
				if(cmr_1_pix_fifo_wr_wl == 0 && cmr_2_pix_fifo_wr_wl == 0) begin
					nex_state = IDLE;
				end
			end			
			default			:begin
				nex_state = IDLE;
			end
		endcase
	end
	
	always@(posedge axi_clk) begin
		if(!rst_n) begin
			cur_state <= IDLE;
		end
		else begin
			cur_state <= nex_state;
		end
	end
	
	localparam SINGLE_LINE_REQ_VALUE = H_VALID * PIX_DWIDTH / AXI_DATA_WIDTH;

	function integer fn_get_burst_len;
		input integer value;
		reg found;
		integer i;
		begin
			fn_get_burst_len = 1;
			found = 1'b0;
			for (i = {AXI_LEN_WIDTH{1'b1}} + 1'b1; i >= 1; i = i - 1) begin
				if (!found && (value % i == 0)) begin
					fn_get_burst_len = i;
					found = 1'b1;
				end
			end
		end
	endfunction

	localparam SINGLE_BURST_LEN       = fn_get_burst_len(SINGLE_LINE_REQ_VALUE);
	localparam TOTAL_BURST_CNT_VALUE  = SINGLE_LINE_REQ_VALUE / SINGLE_BURST_LEN * V_VALID;
	localparam TOTAL_BURST_CNT_WIDTH  = $clog2(TOTAL_BURST_CNT_VALUE);
	localparam AXI_ADDR_STEP_VAL      = SINGLE_BURST_LEN * AXI_DATA_WIDTH / DDR_DQ_WIDTH;

	reg [TOTAL_BURST_CNT_WIDTH-1:0] cmr_1_burst_cnt;
	reg [TOTAL_BURST_CNT_WIDTH-1:0] cmr_2_burst_cnt;

	always @(posedge axi_clk) begin
		if (!rst_n) begin
			cmr_1_burst_cnt <= {TOTAL_BURST_CNT_WIDTH{1'b0}};
			cmr_2_burst_cnt <= {TOTAL_BURST_CNT_WIDTH{1'b0}};
		end
		else begin
			if (cur_state == IDLE) begin
				cmr_1_burst_cnt <= {TOTAL_BURST_CNT_WIDTH{1'b0}};
				cmr_2_burst_cnt <= {TOTAL_BURST_CNT_WIDTH{1'b0}};
			end
			else if (cur_state == CMR_1_ADDR_RDY && axi_araddr_valid && axi_araddr_ready) begin
				cmr_1_burst_cnt <= cmr_1_burst_cnt + 1'b1;
			end
			else if (cur_state == CMR_2_ADDR_RDY && axi_araddr_valid && axi_araddr_ready) begin
				cmr_2_burst_cnt <= cmr_2_burst_cnt + 1'b1;
			end
		end
	end

	wire cmr_1_wr_end_flag;
	wire cmr_2_wr_end_flag;
	assign cmr_1_wr_end_flag = axi_rlast && axi_rd_id == CMR_1_AXI_ID;
	assign cmr_2_wr_end_flag = axi_rlast && axi_rd_id == CMR_2_AXI_ID;

	assign frame_req_end_flag = (cmr_1_burst_cnt == TOTAL_BURST_CNT_VALUE) &&
	                            (cmr_2_burst_cnt == TOTAL_BURST_CNT_VALUE);

	always @(posedge axi_clk or negedge rst_n) begin
		if (!rst_n) begin
			axi_ar_id        <= {AXI_ID_WIDTH{1'b0}};
			axi_ar_len       <= {AXI_LEN_WIDTH{1'b0}};
			axi_araddr       <= {AXI_ADDR_WIDTH{1'b0}};
			axi_araddr_valid <= 1'b0;
		end else begin
			if (axi_araddr_ready && axi_araddr_valid) begin
				axi_ar_id        <= {AXI_ID_WIDTH{1'b0}};
				axi_ar_len       <= {AXI_LEN_WIDTH{1'b0}};
				axi_araddr       <= {AXI_ADDR_WIDTH{1'b0}};
				axi_araddr_valid <= 1'b0;
			end
			else begin
				case (cur_state)
					CMR_1_ADDR_RDY: begin
						axi_araddr       <= cmr_1_burst_cnt * AXI_ADDR_STEP_VAL + cmr_1_rd_buf_ofst;
						axi_ar_id        <= CMR_1_AXI_ID;
						axi_ar_len       <= SINGLE_BURST_LEN - 1'b1;
						axi_araddr_valid <= 1'b1;
					end
					CMR_2_ADDR_RDY: begin
						axi_araddr       <= cmr_2_burst_cnt * AXI_ADDR_STEP_VAL + cmr_2_rd_buf_ofst;
						axi_ar_id        <= CMR_2_AXI_ID;
						axi_ar_len       <= SINGLE_BURST_LEN - 1'b1;
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

endmodule