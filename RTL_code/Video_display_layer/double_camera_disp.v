`timescale 1ps/1ps
module double_camera_disp#(
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
	
	parameter 	CMR_1_AXI_ID	=	4'b0001		,
	parameter 	CMR_2_AXI_ID	=	4'b0010		,
	parameter 	DDR_DQ_WIDTH	=	32			,
	parameter	PIX_DWIDTH		=	16			,
	parameter	CMR_1_VWIDTH	=	640			,
	parameter	CMR_2_VWIDTH	=	640			,
	parameter	CMR_1_VHEIGHT	=	480			,
	parameter	CMR_2_VHEIGHT	=	480			,
	parameter	DISP_WIDTH		=	8			,
	parameter	AXI_ADDR_WIDTH	=	28			,
	parameter	AXI_DATA_WIDTH	=	256			,
	parameter	AXI_R_LEN_BASE	=	4'b0111		,
	parameter	AXI_ID_WIDTH	=	4			,
	parameter	AXI_LEN_WIDTH	=	4			
)(
	input 	wire 							rst_n				,
	 
	input 	wire 							pix_clk				,
	
	input 	wire 	[7:0]					cmr_1_pix_fifo_wr_wl, //wr端是AXI总线的时钟域
	input 	wire 	[7:0]					cmr_2_pix_fifo_wr_wl,
	
	input 	wire 							camera_1_rd_de		,
	input 	wire 	[AXI_DATA_WIDTH-1:0]	camera_1_rd_data	,
	output 	wire 							camera_1_rd_req		,
	
	input 	wire 							camera_2_rd_de		,
	input 	wire 	[AXI_DATA_WIDTH-1:0]	camera_2_rd_data	,
	output 	wire 							camera_2_rd_req		,
	
	output 	reg 							vsync				,
	output 	reg 							hsync				,
	output 	reg 							de					,
	output 	reg 	[DISP_WIDTH-1:0]		r_chn				,	
	output 	reg 	[DISP_WIDTH-1:0]		g_chn				,	
	output 	reg 	[DISP_WIDTH-1:0]		b_chn				,	
	
	input 	wire 	[AXI_ADDR_WIDTH-1:0]	cmr_1_rd_buf_ofst	,
	input 	wire 	[AXI_ADDR_WIDTH-1:0]	cmr_2_rd_buf_ofst	,
	input 	wire 							axi_clk				,
	output 	reg 	[AXI_ID_WIDTH-1:0]		axi_ar_id			,
	output 	reg 	[AXI_LEN_WIDTH-1:0]		axi_ar_len			,
	output 	reg 	[AXI_ADDR_WIDTH-1:0]	axi_araddr			/*synthesis PAP_MARK_DEBUG="true"*/,
	output 	reg 							axi_araddr_valid	,
	input 	wire 							axi_araddr_ready	,
	
	output 	reg 							l_disp_valid		,
	output 	reg 							r_disp_valid
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
	reg 	in_hsync;
	reg 	in_de;
	reg		[1:0]	in_hsync_dly;
	reg		[1:0]	in_vsync_dly;
	reg		[1:0]	in_de_dly;
	always @(posedge pix_clk) begin
		if (!rst_n) begin
			in_hsync <= 1'b0;
			in_vsync <= 1'b0;
			in_de 	 <= 1'b0;
			in_hsync_dly <= 2'b00;
			in_vsync_dly <= 2'b00;
			in_de_dly 	 <= 2'b00;
		end
		else begin
			in_hsync <= (cnt_h < H_SYNC) ? 1'b1 : 1'b0;
			in_vsync <= (cnt_v < V_SYNC) ? 1'b1 : 1'b0;
			in_de    <= in_h_valid && in_v_valid;
			in_hsync_dly <= {in_hsync_dly[0],in_hsync};
			in_vsync_dly <= {in_vsync_dly[0],in_vsync};
			in_de_dly 	 <= {in_de_dly[0],in_de};
		end
	end
	
	localparam CMR_1_DISP_AREA_H_OFST = 12'd160;
	localparam CMR_1_DISP_AREA_V_OFST = 12'd32;
	
	localparam CMR_2_DISP_AREA_H_OFST = 12'd1120;
	localparam CMR_2_DISP_AREA_V_OFST = 12'd32;
	
	wire 	cmr_1_disp_h_valid;
	wire 	cmr_1_disp_v_valid;
	wire 	cmr_2_disp_h_valid;
	wire 	cmr_2_disp_v_valid;
	
	assign cmr_1_disp_h_valid = cnt_h >=  H_SYNC + H_BACK + H_LEFT + CMR_1_DISP_AREA_H_OFST 
								&& cnt_h < H_SYNC + H_BACK + H_LEFT + CMR_1_DISP_AREA_H_OFST + CMR_1_VWIDTH;
								
	assign cmr_2_disp_h_valid = cnt_h >=  H_SYNC + H_BACK + H_LEFT + CMR_2_DISP_AREA_H_OFST 
								&& cnt_h < H_SYNC + H_BACK + H_LEFT + CMR_2_DISP_AREA_H_OFST + CMR_2_VWIDTH;	
	
	assign cmr_1_disp_v_valid = cnt_v >=  V_SYNC + V_BACK + V_TOP  + CMR_1_DISP_AREA_V_OFST 
								&& cnt_v < V_SYNC + V_BACK + V_TOP  + CMR_1_DISP_AREA_V_OFST + CMR_1_VHEIGHT;	
								
	assign cmr_2_disp_v_valid = cnt_v >=  V_SYNC + V_BACK + V_TOP  + CMR_2_DISP_AREA_V_OFST 
								&& cnt_v < V_SYNC + V_BACK + V_TOP  + CMR_2_DISP_AREA_V_OFST + CMR_2_VHEIGHT;

	reg 			cmr_1_disp_valid;
	reg 			cmr_2_disp_valid;
	reg 	[2:0]	cmr_1_disp_valid_dly;
	reg 	[2:0]	cmr_2_disp_valid_dly;
	always @(posedge pix_clk) begin
		if (!rst_n) begin
			cmr_1_disp_valid <= 1'b0;
			cmr_2_disp_valid <= 1'b0;
			cmr_1_disp_valid_dly <= 3'b00;
			cmr_2_disp_valid_dly <= 3'b00;
		end
		else begin
			cmr_1_disp_valid <= cmr_1_disp_h_valid && cmr_1_disp_v_valid;
			cmr_2_disp_valid <= cmr_2_disp_h_valid && cmr_2_disp_v_valid;
			cmr_1_disp_valid_dly <= {cmr_1_disp_valid_dly[1],cmr_1_disp_valid_dly[0],cmr_1_disp_valid};
			cmr_2_disp_valid_dly <= {cmr_2_disp_valid_dly[1],cmr_2_disp_valid_dly[0],cmr_2_disp_valid};
		end
	end
	
	reg 	[3:0]	cmr_1_rd_cnt;
	reg 	[3:0]	cmr_2_rd_cnt;
	reg 	[3:0]	cmr_1_rd_cnt_dly[1:0];
	reg 	[3:0]	cmr_2_rd_cnt_dly[1:0];
	always @(posedge pix_clk) begin
		if (!rst_n) begin
			cmr_1_rd_cnt <= 4'd0;
			cmr_2_rd_cnt <= 4'd0;
			cmr_1_rd_cnt_dly[0] <= 4'd0;
			cmr_2_rd_cnt_dly[0] <= 4'd0;
			cmr_1_rd_cnt_dly[1] <= 4'd0;
			cmr_2_rd_cnt_dly[1] <= 4'd0;
		end
		else begin
			cmr_1_rd_cnt_dly[0] <= cmr_1_rd_cnt;
			cmr_2_rd_cnt_dly[0] <= cmr_2_rd_cnt;
			cmr_1_rd_cnt_dly[1] <= cmr_1_rd_cnt_dly[0];
			cmr_2_rd_cnt_dly[1] <= cmr_2_rd_cnt_dly[0];
			if(cmr_1_disp_valid) begin
				cmr_1_rd_cnt <= cmr_1_rd_cnt + 4'd1;
			end
			else begin
				cmr_1_rd_cnt <= 4'd0;
			end
			
			if(cmr_2_disp_valid) begin
				cmr_2_rd_cnt <= cmr_2_rd_cnt + 4'd1;
			end
			else begin
				cmr_2_rd_cnt <= 4'd0;
			end		
		end
	end
	
	//注意FIFO必须是预读模式，
	//目前FIFO不是预读模式，所以会有显示不正常的情况，需要进行时序的调整
	assign camera_1_rd_req = cmr_1_rd_cnt == 4'd0 && camera_1_rd_de && cmr_1_disp_valid;
	assign camera_2_rd_req = cmr_2_rd_cnt == 4'd0 && camera_2_rd_de && cmr_2_disp_valid;
	
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
	reg 	[PIX_DWIDTH-1:0]	pix_disp_pre;
	reg 	[PIX_DWIDTH-1:0]	pix_disp;
	
	always @(posedge pix_clk) begin
		if (!rst_n) begin
			pix_disp <= 0;
			pix_disp_pre <= 0;
		end
		else begin
			if(cmr_1_disp_valid_dly[1]) begin
				pix_disp_pre <= camera_1_rd_data_reg[cmr_1_rd_cnt_dly[1]*16+:16];
			end
			else if(cmr_2_disp_valid_dly[1]) begin
				pix_disp_pre <= camera_2_rd_data_reg[cmr_2_rd_cnt_dly[1]*16+:16];
			end
			else begin
				pix_disp_pre <= 16'hffff;
			end
			pix_disp <= pix_disp_pre;
		end
	end
	
	always @(posedge pix_clk) begin
		if (!rst_n) begin
			hsync <= 1'b0;
			vsync <= 1'b0;
			de 	  <= 1'b0;
			r_chn <= 8'd0;
			g_chn <= 8'd0;
			b_chn <= 8'd0;
			l_disp_valid <= 1'b0;
			r_disp_valid <= 1'b0;
		end
		else begin
			hsync <= in_hsync_dly[1];
			vsync <= in_vsync_dly[1];
			de 	  <= in_de_dly[1];
			r_chn <= pix_disp[15:11] << 3;
			g_chn <= pix_disp[10:5 ] << 2;
			b_chn <= pix_disp[4 :0 ] << 3;
			l_disp_valid <= cmr_1_disp_valid_dly[2];
			r_disp_valid <= cmr_2_disp_valid_dly[2];
		end
	end
	
	
	// ---------------- AXI master layer ----------------
	localparam 	CMR_1_REQ_THRESHOLD	=	CMR_1_VWIDTH * PIX_DWIDTH / AXI_DATA_WIDTH;
	localparam 	CMR_2_REQ_THRESHOLD	=	CMR_2_VWIDTH * PIX_DWIDTH / AXI_DATA_WIDTH;
	localparam	CMR_1_REQ_CTN_THRESHOLD = CMR_1_VWIDTH * PIX_DWIDTH / AXI_DATA_WIDTH / 4;
	localparam	CMR_2_REQ_CTN_THRESHOLD = CMR_2_VWIDTH * PIX_DWIDTH / AXI_DATA_WIDTH / 4;	
	
	localparam 	IDLE				=	7'b0000001	,	
				FRAME_REQ_RDY		=	7'b0000010	,	
				CMR_1_LINE_REQ_RDY	=	7'b0000100	,	
				CMR_1_LINE_REQ_END	=	7'b0001000	,	
				CMR_2_LINE_REQ_RDY	=	7'b0010000	,	
				CMR_2_LINE_REQ_END	=	7'b0100000	,	
				FRAME_REQ_END		=	7'b1000000	;
	
	localparam 	FSM_CNT	=	7;
	
	wire 					vsync_axi_synced;
	reg 					vsync_axi_synced_reg;
	wire 					cmr_1_line_req_end_flag;
	wire 					cmr_2_line_req_end_flag;
	wire 					cmr_1_frame_req_end;
	wire 					cmr_2_frame_req_end;
	wire 					cmr_frame_req_end;
	reg 	[FSM_CNT-1:0] 	cur_state;
	reg 	[FSM_CNT-1:0] 	nex_state;
	wire 					cmr_1_req_ctn_flag;
	wire 					cmr_2_req_ctn_flag;
	
	assign cmr_1_req_ctn_flag = cmr_1_pix_fifo_wr_wl >= CMR_1_REQ_CTN_THRESHOLD && cmr_1_pix_fifo_wr_wl <=  CMR_1_REQ_THRESHOLD;
	assign cmr_2_req_ctn_flag = cmr_2_pix_fifo_wr_wl >= CMR_2_REQ_CTN_THRESHOLD && cmr_2_pix_fifo_wr_wl <=  CMR_2_REQ_THRESHOLD;
	
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
				if(cmr_1_pix_fifo_wr_wl <= CMR_1_REQ_CTN_THRESHOLD && cmr_2_pix_fifo_wr_wl <= CMR_2_REQ_CTN_THRESHOLD) begin
					nex_state = CMR_1_LINE_REQ_RDY;
				end
			end			
			CMR_1_LINE_REQ_RDY	:begin 
				if(cmr_1_line_req_end_flag) begin
					nex_state = CMR_1_LINE_REQ_END;
				end
			end			
			CMR_1_LINE_REQ_END	:begin 
				if(cmr_1_req_ctn_flag) begin
					nex_state = CMR_2_LINE_REQ_RDY;
				end				
			end	
			CMR_2_LINE_REQ_RDY	:begin 
				if(cmr_2_line_req_end_flag) begin
					nex_state = CMR_2_LINE_REQ_END;
				end
			end			
			CMR_2_LINE_REQ_END	:begin 
				if(cmr_frame_req_end) begin
					nex_state = FRAME_REQ_END;
				end
				else begin
					if(cmr_2_req_ctn_flag) begin
						nex_state = FRAME_REQ_RDY;
					end	
				end
			end	
			FRAME_REQ_END	:begin 
				if (cmr_1_pix_fifo_wr_wl == 0 && cmr_2_pix_fifo_wr_wl == 0) begin
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
	
	localparam	CMR_1_V_CNT_WIDTH	=	$clog2(CMR_1_VHEIGHT);
	localparam	CMR_2_V_CNT_WIDTH	=	$clog2(CMR_2_VHEIGHT);
	
	wire 								cmr_1_req_en;
	wire 								cmr_2_req_en;	
	
	reg 	[CMR_1_V_CNT_WIDTH-1:0]		cmr_1_v_cnt;
	reg 	[CMR_2_V_CNT_WIDTH-1:0]		cmr_2_v_cnt;
	
	always@(posedge axi_clk) begin
		if(!rst_n) begin
			cmr_1_v_cnt <= 'd0;
			cmr_2_v_cnt <= 'd0;
		end
		else begin
			if(vsync_axi_synced) begin
				cmr_1_v_cnt <= 'd0;
				cmr_2_v_cnt <= 'd0;			
			end
			else begin
				if(cmr_1_line_req_end_flag) begin
					cmr_1_v_cnt <= cmr_1_v_cnt == CMR_1_VHEIGHT ? CMR_1_VHEIGHT : cmr_1_v_cnt + 1'b1;
				end
				
				if(cmr_2_line_req_end_flag) begin
					cmr_2_v_cnt <= cmr_2_v_cnt == CMR_2_VHEIGHT ? CMR_2_VHEIGHT : cmr_2_v_cnt + 1'b1;
				end
				
			end
		end
	end
	assign cmr_1_frame_req_end = cmr_1_v_cnt == CMR_1_VHEIGHT;
	assign cmr_2_frame_req_end = cmr_2_v_cnt == CMR_2_VHEIGHT;
	assign cmr_frame_req_end = cmr_1_frame_req_end && cmr_2_frame_req_end;
	
	reg 		roll_polling_flag;
	
	always@(posedge axi_clk) begin
		if(!rst_n) begin
			roll_polling_flag <= 1'b0;
		end
		else begin
			if(cmr_1_line_req_end_flag || cmr_2_line_req_end_flag) begin
				roll_polling_flag <= ~ roll_polling_flag;
			end
		end
	end
	
	localparam CMR_1_LINE_REQ_VALUE = CMR_1_VWIDTH * PIX_DWIDTH / AXI_DATA_WIDTH / (AXI_R_LEN_BASE + 1);
	localparam CMR_2_LINE_REQ_VALUE = CMR_2_VWIDTH * PIX_DWIDTH / AXI_DATA_WIDTH / (AXI_R_LEN_BASE + 1);
	
	localparam CMR_1_REQ_CNT_WIDTH = $clog2(CMR_1_LINE_REQ_VALUE);
	localparam CMR_2_REQ_CNT_WIDTH = $clog2(CMR_2_LINE_REQ_VALUE);
	
	reg		[CMR_1_REQ_CNT_WIDTH-1:0]	cmr_1_req_cnt; 	
	reg		[CMR_2_REQ_CNT_WIDTH-1:0]	cmr_2_req_cnt;	
	
	always@(posedge axi_clk) begin
		if(!rst_n) begin
			cmr_1_req_cnt <= 'd0;
			cmr_2_req_cnt <= 'd0;
		end
		else begin
			if(cur_state == CMR_1_LINE_REQ_RDY) begin
				if(cmr_1_req_cnt == CMR_1_LINE_REQ_VALUE) begin
					cmr_1_req_cnt <= 'd0;
				end
				else if(axi_araddr_valid && axi_araddr_ready) begin
					cmr_1_req_cnt <= cmr_1_req_cnt + 1'b1;
				end
				cmr_2_req_cnt <= 'd0;
			end
			else if(cur_state == CMR_2_LINE_REQ_RDY) begin
				if(cmr_2_req_cnt == CMR_2_LINE_REQ_VALUE) begin
					cmr_2_req_cnt <= 'd0;
				end
				else if(axi_araddr_valid && axi_araddr_ready) begin
					cmr_2_req_cnt <= cmr_2_req_cnt + 1'b1;
				end
				cmr_1_req_cnt <= 'd0;
			end
			else begin
				cmr_1_req_cnt <= 'd0;
				cmr_2_req_cnt <= 'd0;
			end
		end
	end
	
	assign cmr_1_line_req_end_flag = cmr_1_req_cnt == CMR_1_LINE_REQ_VALUE ;
	assign cmr_2_line_req_end_flag = cmr_2_req_cnt == CMR_2_LINE_REQ_VALUE ;
	
	localparam	CMR_1_LINE_ADDR_OFST = CMR_1_VWIDTH * PIX_DWIDTH / AXI_DATA_WIDTH / (1+AXI_R_LEN_BASE);
	localparam	CMR_2_LINE_ADDR_OFST = CMR_2_VWIDTH * PIX_DWIDTH / AXI_DATA_WIDTH / (1+AXI_R_LEN_BASE);
	localparam	AXI_ADDR_STEP_VAL = AXI_DATA_WIDTH * (1+AXI_R_LEN_BASE)  / DDR_DQ_WIDTH;
	always@(posedge axi_clk) begin
		if(!rst_n) begin
			axi_ar_id <= 4'd0;
			axi_ar_len <= 4'd0;
			axi_araddr_valid <= 1'b0;
			axi_araddr <= 'd0;
		end
		else begin
			if(cur_state == CMR_1_LINE_REQ_RDY) begin
				if(axi_araddr_ready && axi_araddr_valid) begin
					axi_ar_id <= 4'd0;
					axi_ar_len <= 4'd0;
					axi_araddr_valid <= 1'b0;
					axi_araddr <= 'd0;
				end
				else begin
					if(cmr_1_req_cnt == CMR_1_LINE_REQ_VALUE) begin
						axi_ar_id <= 4'd0;
						axi_ar_len <= 4'd0;
						axi_araddr_valid <= 1'b0;
						axi_araddr <= 'd0;
					end
					else begin
						axi_ar_id <= CMR_1_AXI_ID;
						axi_ar_len <= AXI_R_LEN_BASE;
						axi_araddr_valid <= 1'b1;
						axi_araddr <= cmr_1_rd_buf_ofst + (cmr_1_v_cnt*CMR_1_LINE_ADDR_OFST + cmr_1_req_cnt)*AXI_ADDR_STEP_VAL;
					end
				end
			end
			else if(cur_state == CMR_2_LINE_REQ_RDY) begin
				if(axi_araddr_ready && axi_araddr_valid) begin
					axi_ar_id <= 4'd0;
					axi_ar_len <= 4'd0;
					axi_araddr_valid <= 1'b0;
					axi_araddr <= 'd0;
				end
				else begin
					if(cmr_2_req_cnt == CMR_2_LINE_REQ_VALUE) begin
						axi_ar_id <= 4'd0;
						axi_ar_len <= 4'd0;
						axi_araddr_valid <= 1'b0;
						axi_araddr <= 'd0;
					end
					else begin
						axi_ar_id <= CMR_2_AXI_ID;
						axi_ar_len <= AXI_R_LEN_BASE;
						axi_araddr_valid <= 1'b1;
						axi_araddr <= cmr_2_rd_buf_ofst + (cmr_2_v_cnt*CMR_2_LINE_ADDR_OFST + cmr_2_req_cnt)*AXI_ADDR_STEP_VAL;
					end
				end
			end
			else begin
				axi_ar_id <= 4'd0;
				axi_ar_len <= 4'd0;
				axi_araddr_valid <= 1'b0;
				axi_araddr <= 'd0;
			end
		end
	end
endmodule 