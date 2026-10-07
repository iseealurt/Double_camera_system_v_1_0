//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: DC-CVS
// 
// Create Date: 2026-05-11 11:50
// Design Name:  
// Module Name: VESA_AXI
// Project Name: 
// Target Devices: Pango
// Tool Versions: 
// Description: 
// 本模块为片内数VESA协议转Simlified AXI4协议专用，请勿用于片外接口     
// 
// Dependencies: 
// ipcore : fifo_256b6d fifo_24d6d
// Revision:
// 
//                       
//                                  
//////////////////////////////////////////////////////////////////////////////////
module VESA_AXI#(
	parameter   AXI_ADDR_WIDTH 		= 28			,  
				AXI_DATA_WIDTH      = 256			, 
                MEM_DQ_WIDTH       	= 32    		,
                WIDTH             	= 12'd640		,
                HEIGHT              = 12'd480		,
				PIXEL_DATA_WIDTH    = 8				,
				INPUT_DATA_WIDTH	= 8				,
				AXI_ID 				= 4'b0001		,
				AXI_LEN_WIDTH  	 	= 4		         
)(
	input 	wire 							rst_n				,
	
	input 	wire 							pclk				,
	input 	wire 	[INPUT_DATA_WIDTH-1:0]	din					,
	input 	wire 							href				,
	input 	wire							vref				,
	
	input 	wire 	[AXI_ADDR_WIDTH-1:0]	write_buffer_offset	,
	
	input	wire 							axi_clk				,
	output 	reg 	[AXI_ADDR_WIDTH-1:0]	axi_awaddr			,
	input 	wire 							axi_awready			,
	output 	reg 							axi_awvalid			,
	output 	reg 	[3:0]					axi_awid			,
	output 	reg  	[3:0]					axi_awlen			,
	
	input 	wire 	[3:0]					axi_wid				,
	input 	wire 							axi_wready			,
	input 	wire 							axi_wlast			,
	output 	wire 	[MEM_DQ_WIDTH*8-1:0	]	axi_wdata			,
	output 	wire 	[MEM_DQ_WIDTH-1:0	]	axi_wstrb
);
	//--------------- dvp data receive layer ---------------
	localparam 	COL_CNT_MAX_VAL	= WIDTH;
	localparam 	COL_CNT_WIDTH	= $clog2(COL_CNT_MAX_VAL);	
	wire 								fifo_rst;
	reg 	[23:0]						afifo_din;
	reg 								afifo_wrreq;
	reg 								dfifo_wrreq;
	wire 								dfifo_full, afifo_full;
	reg  	[15:0]						axi_addr_cal;

	wire 								vref_pose;
	reg									vref_dly;

	reg 	[AXI_DATA_WIDTH-1:0]		burst_data_reg;
	reg 	[COL_CNT_WIDTH-1:0]			col_cnt/*synthesis PAP_MARK_DEBUG="true"*/;
	
	assign vref_pose = vref && !vref_dly;
	assign fifo_rst = !rst_n || vref_pose;
	
	always@(posedge pclk) begin
		if(!rst_n) begin
			vref_dly <= 1'b0;
		end
		else begin
			vref_dly <= vref;
		end
	end
	
	wire 							afifo_wr_en;
	wire 							dfifo_wr_en;
	reg        						pix_valid_flag;

	always@(posedge pclk) begin
		if(!rst_n) begin
			col_cnt <= {COL_CNT_WIDTH{1'b0}};
		end
		else begin
			if(vref_pose) begin
				col_cnt <= {COL_CNT_WIDTH{1'b0}};
			end
			else if(pix_valid_flag) begin
				col_cnt <= col_cnt + 1'b1;
			end
			else begin
				col_cnt <= {COL_CNT_WIDTH{1'b0}};
			end
		end
	end
	
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

	localparam  PIXEL_DATA_BYTE_NUM	= (INPUT_DATA_WIDTH/8) + ((INPUT_DATA_WIDTH % 8 > 0) ? 1 : 0 );
	// data counter and shift register
	localparam  SHIFT_REG_WIDTH = 1 << ($clog2(INPUT_DATA_WIDTH));
	
	wire [SHIFT_REG_WIDTH-1:0] shift_reg_din;
	
	assign shift_reg_din = {{(SHIFT_REG_WIDTH-INPUT_DATA_WIDTH){1'b0}},din};

	always@(posedge pclk) begin
		if(!rst_n) begin
			burst_data_reg <= {AXI_DATA_WIDTH{1'b0}};
		end
		else begin
			if(href) begin
				burst_data_reg <= {burst_data_reg[AXI_DATA_WIDTH-9:0],shift_reg_din};
			end
		end
	end

	always@(posedge pclk) begin
		if(!rst_n) begin
			pix_valid_flag <= 1'b0;
		end
		else begin
			pix_valid_flag <= href;
		end
	end

	localparam SINGLE_LINE_REQ_VALUE = WIDTH * 8 / AXI_DATA_WIDTH;
	localparam AXI_WLEN  = fn_get_burst_len(SINGLE_LINE_REQ_VALUE);
	localparam DFIFO_WR_EN_VALUE = AXI_DATA_WIDTH / SHIFT_REG_WIDTH;
	localparam DFIFO_WR_EN_WIDTH = $clog2(DFIFO_WR_EN_VALUE);
	localparam AFIFO_WR_EN_VALUD = DFIFO_WR_EN_VALUE * AXI_WLEN;
	localparam AFIFO_WR_EN_WIDTH = $clog2(AFIFO_WR_EN_VALUD);

	assign afifo_wr_en = col_cnt[AFIFO_WR_EN_WIDTH-1:0] == AFIFO_WR_EN_VALUD - 1 && !afifo_full && pix_valid_flag;
	assign dfifo_wr_en = col_cnt[DFIFO_WR_EN_WIDTH-1:0] == DFIFO_WR_EN_VALUE - 1 && !dfifo_full && pix_valid_flag;
	localparam	AXI_ADDR_STEP_VAL = AXI_DATA_WIDTH*AXI_WLEN/MEM_DQ_WIDTH;

	always@(posedge pclk) begin
		if(!rst_n) begin
			axi_addr_cal <= 0;
		end
		else begin	
			if(vref_pose) begin
				axi_addr_cal <= 0;
			end
			else if(afifo_wr_en) begin
				axi_addr_cal <= axi_addr_cal + 1'b1;
			end
		end
	end
	
	//由于地址计算的组合逻辑比较深所以需要打一拍
	reg 	[MEM_DQ_WIDTH*8-1:0]	dfifo_din;
	always@(posedge pclk) begin
		if(!rst_n) begin
			afifo_din <= 'd0;
			afifo_wrreq <= 'd0;
			dfifo_wrreq <= 'd0;
			dfifo_din <= 'd0;
		end
		else begin
			afifo_din <= axi_addr_cal * AXI_ADDR_STEP_VAL;
			afifo_wrreq <= afifo_wr_en;
			dfifo_wrreq <= dfifo_wr_en;
			dfifo_din <= burst_data_reg;
		end
	end

	//--------------- AXI bus write address and data control channel ---------------

	parameter 	IDLE 		= 2'b00	, ADDR_SEND = 2'b01		, 
				DATA_SEND 	= 2'b11	, DATA_END 	= 2'b10		;
	
	reg 	[1:0]			axi_cur_st,axi_nex_st;
	
	wire 					afifo_rdreq,dfifo_rdreq;
	wire 					afifo_den_n,dfifo_den_n;
	wire 	[7:0]			afifo_rd_wl,dfifo_rd_wl;
	wire 	[23:0]			afifo_do;
	wire 	[MEM_DQ_WIDTH*8-1:0] dfifo_do;
	wire 					axi_send_en;
	reg						axi_send_en_reg;
	
	assign	axi_wdata = dfifo_do;
	assign 	axi_wstrb = {MEM_DQ_WIDTH{1'b1}};
	assign	axi_send_en = !afifo_den_n && !dfifo_den_n && dfifo_rd_wl >= AXI_WLEN;
	assign	afifo_rdreq = axi_awvalid && axi_awready;
	assign	dfifo_rdreq = axi_wready && axi_wid == AXI_ID;
	
	always@(posedge axi_clk) begin
		axi_send_en_reg <= axi_send_en;
	end
	// 3-stage state machine of AXI bus control
	always@(*) begin
		axi_nex_st = axi_cur_st;
		case(axi_cur_st) 
			IDLE: 		begin 
				if (axi_send_en_reg) axi_nex_st = ADDR_SEND;
				else axi_nex_st = IDLE;
			end
			ADDR_SEND:	begin 
				if (afifo_rdreq) axi_nex_st = DATA_SEND;
				else axi_nex_st = ADDR_SEND;
			end
			DATA_SEND:	begin 
				if (axi_wlast) axi_nex_st = DATA_END;
				else axi_nex_st = DATA_SEND;
			end
			DATA_END:		begin 
				axi_nex_st = IDLE;
			end
			default:	begin
				axi_nex_st = IDLE;
			end
		endcase
	end
	
	always@(posedge axi_clk) begin
		if(!rst_n) begin
			axi_cur_st <= IDLE;
		end
		else begin
			axi_cur_st <= axi_nex_st;
		end
	end
	
	always@(posedge axi_clk) begin
		if(!rst_n) begin
			axi_awvalid <= 1'b0;
			axi_awid   <=4'd0;
			axi_awlen <= 4'd0;
			axi_awaddr <= 'd0;
		end
		else begin
			if (axi_cur_st == ADDR_SEND) begin
				if(axi_awvalid && axi_awready) begin
					axi_awvalid <= 1'b0;
					axi_awid   <=4'd0;
					axi_awlen <= 4'd0;
					axi_awaddr <= 'd0;
				end
				else begin
					axi_awvalid <= 1'b1;
					axi_awid   <= AXI_ID;
					axi_awlen <=  AXI_WLEN - 4'd1;
					axi_awaddr <= {4'd0,afifo_do} + write_buffer_offset;
				end
			end
			else begin 
				axi_awvalid <= 1'b0;
				axi_awid   <=4'd0;
				axi_awlen <= 4'd0;
				axi_awaddr <= 'd0;
			end
		end
	end
	
	//fifo instance
	fifo_256b6d dfifo (
		.wr_data		(dfifo_din		),    	// input [255:0]
		.wr_en			(dfifo_wrreq	),   	// input
		.wr_clk			(pclk			),   	// input
		.full			(dfifo_full		),    	// output
		.wr_rst			(fifo_rst		),   	// input
		.almost_full	(				),   	// output
		.wr_water_level	(				),    	// output [6:0]
		.rd_data		(dfifo_do		),  	// output [255:0]
		.rd_en			(dfifo_rdreq	),   	// input
		.rd_clk			(axi_clk		),  	// input
		.empty			(dfifo_den_n	),   	// output
		.rd_rst			(fifo_rst		),     	// input
		.almost_empty	(				),		// output
		.rd_water_level	(dfifo_rd_wl	)     	// output [6:0]
	);

	fifo_24b6d afifo (
		.wr_data		(afifo_din		), 		// input [23:0]
		.wr_en			(afifo_wrreq	), 		// input
		.wr_clk			(pclk			),		// input
		.full			(afifo_full		),  	// output
		.wr_rst			(fifo_rst		),		// input
		.almost_full	(				),      // output
		.rd_data		(afifo_do		), 		// output [23:0]
		.rd_en			(afifo_rdreq	),   	// input
		.rd_clk			(axi_clk		), 		// input
		.empty			(afifo_den_n	),		// output
		.rd_rst			(fifo_rst		),   	// input
		.almost_empty	(				)     	// output
	);
	
endmodule