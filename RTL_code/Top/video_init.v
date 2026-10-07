module video_init#(
	parameter 	CLK_PERIOD 		=	20			,	//50M hz
				DDR_RST_TIME	=	205000		//205us
)(
	input 	wire			clk_in			,
	input 	wire 			ext_rst_n		,
	input 	wire 			ddr_init_done	,
	input 	wire 			cmr1_init_done	, 
	input 	wire 			cmr2_init_done	, 
	input 	wire 			ms_init_done	,
	output 	reg 			ddr_rst_n		,
	output 	reg				cmr1_init_en	,
	output 	reg 			cmr2_init_en	,
	output 	reg 			ms_init_en		,
	output 	reg 			stream_rst_n	
);
	// paramter define
	parameter 	DDR_RST_CNT_VALUE	=	 DDR_RST_TIME / CLK_PERIOD; 
	parameter 	CMR_RST_CNT_VALUE	=	16'd49999;
	parameter 	IDLE 		=	6'b00_0001	,	DDR_INIT		=	6'b00_0010	,	
				CMR_INIT	=	6'b00_0100	,	MS_INIT 		=	6'b00_1000	,
				STREAM_INIT	=	6'b01_0000	,	INIT_FINISHED	=	6'b10_0000	;
	wire 	cmr_delay_end;
	// register variable define
	reg 	[15:0]		ddr_rst_cnt = 0;
	reg 	[15:0]		cmr_rst_cnt = 0;
	
	assign cmr_delay_end = cmr_rst_cnt == CMR_RST_CNT_VALUE;
	
	
	// the three-stage state machine used for initialization
	reg		[5:0]		init_cur_state;
	reg 	[5:0]		init_nex_state;
	
	always@(posedge clk_in or negedge ext_rst_n) begin
		if(!ext_rst_n) begin
			cmr_rst_cnt <= 16'd0;
		end
		else begin
			if(init_cur_state == CMR_INIT) begin
				cmr_rst_cnt <= cmr_rst_cnt == CMR_RST_CNT_VALUE ? cmr_rst_cnt : cmr_rst_cnt + 16'd1;
			end
			else begin
				cmr_rst_cnt <= cmr_rst_cnt;
			end
			
		end
	end
	
	always@(*)	begin
		init_nex_state = IDLE;
		case(init_cur_state) 
			IDLE:			begin 
				 init_nex_state = DDR_INIT;
			end
			DDR_INIT:		begin 
				if (ddr_init_done) begin
					init_nex_state = CMR_INIT;
				end
				else begin
					init_nex_state = DDR_INIT;
				end
			end
			CMR_INIT:		begin 
				if(cmr1_init_done && cmr2_init_done) begin
					init_nex_state = MS_INIT;
				end
				else begin
					init_nex_state = CMR_INIT;
				end
			end
			MS_INIT:		begin 
				if(ms_init_done) begin
					init_nex_state = STREAM_INIT;
				end
				else begin
					init_nex_state = MS_INIT;
				end
			end
			STREAM_INIT:	begin 
				if(stream_rst_n) begin
					init_nex_state = INIT_FINISHED;
				end
				else begin 
					init_nex_state = STREAM_INIT;
				end
			end
			INIT_FINISHED:	begin 
				init_nex_state = INIT_FINISHED;
			end
			default:		begin 
				init_nex_state = IDLE;
			end
		endcase
	end
	
	always@(posedge clk_in or negedge ext_rst_n) begin 
		if (!ext_rst_n) begin
			init_cur_state <= IDLE;
		end
		else begin
			init_cur_state <= init_nex_state;
		end
	end
	
	always@(posedge clk_in or negedge ext_rst_n) begin 
		if (!ext_rst_n) begin
			ddr_rst_n 	 <= 1'b0;
			cmr1_init_en <= 1'b0;
			cmr2_init_en <= 1'b0;
			ms_init_en 	 <= 1'b0;
			stream_rst_n <= 1'b0;
		end
		else begin
			case(init_cur_state) 
				IDLE:			begin
					ddr_rst_n 	 <= 1'b1;
					cmr1_init_en <= 1'b0;
					cmr2_init_en <= 1'b0;
					ms_init_en 	 <= 1'b0;
					stream_rst_n <= 1'b0;
				end
				DDR_INIT:		begin 	
					if(ddr_rst_cnt < DDR_RST_CNT_VALUE - 16'd1) begin
						ddr_rst_n <= 1'b0;
					end	
					else begin 
						ddr_rst_n <= 1'b1;
					end
					cmr1_init_en <= 1'b0;
					cmr2_init_en <= 1'b0;
					ms_init_en 	 <= 1'b0;
					stream_rst_n <= 1'b0;
				end
				CMR_INIT:		begin 
					ddr_rst_n 	 <= 1'b1;
					if(cmr_delay_end) begin
						cmr1_init_en <= 1'b1;
						cmr2_init_en <= 1'b1;
					end
					else begin
						cmr1_init_en <= 1'b0;
						cmr2_init_en <= 1'b0;
					end
					ms_init_en 	 <= 1'b0;
					stream_rst_n <= 1'b0;
				end
				MS_INIT:		begin 
					ddr_rst_n 	 <= 1'b1;
					cmr1_init_en <= 1'b1;
					cmr2_init_en <= 1'b1;
					ms_init_en 	 <= 1'b1;
					stream_rst_n <= 1'b0;
				end
				STREAM_INIT:	begin 
					ddr_rst_n 	 <= 1'b1;
					cmr1_init_en <= 1'b1;
					cmr2_init_en <= 1'b1;
					ms_init_en 	 <= 1'b1;
					stream_rst_n <= 1'b1;
				end
				INIT_FINISHED:	begin 
					ddr_rst_n 	 <= 1'b1;
					cmr1_init_en <= 1'b1;
					cmr2_init_en <= 1'b1;
					ms_init_en 	 <= 1'b1;
					stream_rst_n <= 1'b1;
				end
				default: begin 
					ddr_rst_n 	 <= 1'b0;
					cmr1_init_en <= 1'b0;
					cmr2_init_en <= 1'b0;
					ms_init_en 	 <= 1'b0;
					stream_rst_n <= 1'b0;
				end
			endcase
		end
	end
	
	//DDR reset time counter
	always@(posedge clk_in or negedge ext_rst_n) begin 
		if (!ext_rst_n) begin
			ddr_rst_cnt <= 16'd0;
		end
		else begin
			if(init_cur_state == IDLE) begin
				ddr_rst_cnt <= 16'd0;
			end
			else begin
				ddr_rst_cnt <= ddr_rst_cnt == DDR_RST_CNT_VALUE - 16'd1 ? ddr_rst_cnt : ddr_rst_cnt + 16'd1;
			end
		end
	end
endmodule