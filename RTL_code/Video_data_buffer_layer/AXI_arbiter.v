module AXI_arbiter#(
	parameter		AXI_ADDR_WIDTH			=	28					,
	parameter 		AXI_DATA_WIDTH			=	256					,
	parameter 		AXI_ID_WIDTH			=	4					,
	parameter		AXI_LEN_WIDTH			=	4					,
	parameter 		DDR_DATA_MASK_WIDTH		=	32					,
	parameter 		DATA_BACKPRESSURE_EN	=	1'b1				,
	parameter 		CLIENT_NUMBER			=	4					,
	parameter 		ROLL_POLING_MAX_INTERVAL= 	4'd1				
)(
	input 	wire 							clk						,
	input 	wire 							rst_n					,
	
	output 	wire 	[3:0]					grant_busy				,
	output 	wire 	[3:0]					grant_overtime			,
	input 	wire 	[AXI_ADDR_WIDTH-1:0]	master_0_araddr			,
	input 	wire 	[AXI_ID_WIDTH-1:0]		master_0_ar_id			,
	input 	wire 	[AXI_LEN_WIDTH-1:0]		master_0_ar_len			,
	input 	wire 							master_0_araddr_valid	,
	output 	reg 							master_0_araddr_ready	,
	
	input 	wire 	[AXI_ADDR_WIDTH-1:0]	master_0_awaddr			,
	input 	wire 	[AXI_ID_WIDTH-1:0]		master_0_aw_id			,
	input 	wire 	[AXI_LEN_WIDTH-1:0]		master_0_aw_len			,
	input 	wire 							master_0_awaddr_valid	,
	output 	reg 							master_0_awaddr_ready	,
	
	input 	wire 	[AXI_ADDR_WIDTH-1:0]	master_1_araddr			,
	input 	wire 	[AXI_ID_WIDTH-1:0]		master_1_ar_id			,
	input 	wire 	[AXI_LEN_WIDTH-1:0]		master_1_ar_len			,
	input 	wire 							master_1_araddr_valid	,
	output 	reg 							master_1_araddr_ready	,
	
	input 	wire 	[AXI_ADDR_WIDTH-1:0]	master_1_awaddr			,
	input 	wire 	[AXI_ID_WIDTH-1:0]		master_1_aw_id			,
	input 	wire 	[AXI_LEN_WIDTH-1:0]		master_1_aw_len			,
	input 	wire 							master_1_awaddr_valid	,
	output 	reg 							master_1_awaddr_ready	,
	
	output 	wire 	[AXI_ADDR_WIDTH-1:0]	slave_araddr			,
	output 	wire 	[AXI_ID_WIDTH-1:0]		slave_ar_id				,
	output 	wire 	[AXI_LEN_WIDTH-1:0]		slave_ar_len			,
	output 	wire 							slave_araddr_valid		,
	input 	wire 							slave_araddr_ready		,
	
	output 	wire 	[AXI_ADDR_WIDTH-1:0]	slave_awaddr			,
	output 	wire 	[AXI_ID_WIDTH-1:0]		slave_aw_id				,
	output 	wire 	[AXI_LEN_WIDTH-1:0]		slave_aw_len			,
	output 	reg 							slave_awaddr_valid		,
	input 	wire  							slave_awaddr_ready		,
	
	input 	wire 	[AXI_DATA_WIDTH-1:0]	master_0_wr_data		,
	input 	wire 							master_0_wr_data_valid	,
	input 	wire [DDR_DATA_MASK_WIDTH-1:0]	master_0_wstrb			,
	output 	reg 							master_0_wr_data_ready	,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		master_0_wr_id			,	//不支持数据反压时id信号由仲裁器给出
	inout 	wire 							master_0_wr_data_last	, 	//不支持数据反压时last信号由仲裁器给出
	
	output 	wire 	[AXI_DATA_WIDTH-1:0]	master_0_rd_data		,
	output 	wire 							master_0_rd_data_valid	,
	input 	wire 							master_0_rd_data_ready	,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		master_0_rd_id			,	//不支持数据反压时id信号由仲裁器给出
	inout 	wire 							master_0_rd_data_last	,	//不支持数据反压时last信号由仲裁器给出
	
	input 	wire 	[AXI_DATA_WIDTH-1:0]	master_1_wr_data		,
	input 	wire 							master_1_wr_data_valid	,
	input 	wire [DDR_DATA_MASK_WIDTH-1:0]	master_1_wstrb			,
	output 	reg 							master_1_wr_data_ready	,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		master_1_wr_id			,	//不支持数据反压时id信号由仲裁器给出
	inout 	wire 							master_1_wr_data_last	,	//不支持数据反压时last信号由仲裁器给出
	
	output 	wire 	[AXI_DATA_WIDTH-1:0]	master_1_rd_data		,
	output 	wire 							master_1_rd_data_valid	,
	input 	wire 							master_1_rd_data_ready	,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		master_1_rd_id			,	//不支持数据反压时id信号由仲裁器给出
	inout 	wire 							master_1_rd_data_last	,	//不支持数据反压时last信号由仲裁器给出
	
	output 	wire 	[AXI_DATA_WIDTH-1:0]	slave_wr_data			,
	output 	wire 							slave_wr_data_valid		,
	input 	wire 							slave_wr_data_ready		,
	output 	wire [DDR_DATA_MASK_WIDTH-1:0]	slave_wstrb				,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		slave_wr_id				, 	//不支持数据反压时id信号由slave给出
	inout	wire 							slave_wr_data_last		, 	//不支持数据反压时last信号由slave给出
	
	input 	wire 	[AXI_DATA_WIDTH-1:0]	slave_rd_data			,
	input 	wire 							slave_rd_data_valid		,
	output 	wire 							slave_rd_data_ready		,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		slave_rd_id				,	//不支持数据反压时id信号由slave给出
	inout	wire 							slave_rd_data_last			//不支持数据反压时last信号由slave给出
);

endmodule