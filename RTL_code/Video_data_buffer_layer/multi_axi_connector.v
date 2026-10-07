module multi_axi_connector#(
	parameter		AXI_ADDR_WIDTH			=	28					,
	parameter 		AXI_DATA_WIDTH			=	256					,
	parameter 		AXI_ID_WIDTH			=	4					,
	parameter		AXI_LEN_WIDTH			=	4					,
	parameter 		DDR_DATA_MASK_WIDTH		=	32					,  
	parameter 		DATA_BACKPRESSURE_EN	=	1'b0				,
	parameter		CREDIT_DIGITS			=	4					,
	parameter 		CREDIT_MAX_NUM			=	4'd10				
)(
	input 	wire 							axi_clk					,
	input 	wire							rst_n					,
	
	output 	wire	[3:0]					grant_busy				, //3: user_0_write , 2: user_1_write , 1: user_0_read , 0: user_1_read
	input 	wire 	[AXI_ADDR_WIDTH-1:0]	user_0_araddr			,
	input 	wire 	[AXI_ID_WIDTH-1:0]		user_0_ar_id			,
	input 	wire 	[AXI_LEN_WIDTH-1:0]		user_0_ar_len			,
	input 	wire 							user_0_araddr_valid		,
	output 	reg 							user_0_araddr_ready		,
	
	input 	wire 	[AXI_ADDR_WIDTH-1:0]	user_0_awaddr			,
	input 	wire 	[AXI_ID_WIDTH-1:0]		user_0_aw_id			,
	input 	wire 	[AXI_LEN_WIDTH-1:0]		user_0_aw_len			,
	input 	wire 							user_0_awaddr_valid		,
	output 	reg 							user_0_awaddr_ready		,
	
	input 	wire 	[AXI_ADDR_WIDTH-1:0]	user_1_araddr			,
	input 	wire 	[AXI_ID_WIDTH-1:0]		user_1_ar_id			,
	input 	wire 	[AXI_LEN_WIDTH-1:0]		user_1_ar_len			,
	input 	wire 							user_1_araddr_valid		,
	output 	reg 							user_1_araddr_ready		,
	
	input 	wire 	[AXI_ADDR_WIDTH-1:0]	user_1_awaddr			,
	input 	wire 	[AXI_ID_WIDTH-1:0]		user_1_aw_id			,
	input 	wire 	[AXI_LEN_WIDTH-1:0]		user_1_aw_len			,
	input 	wire 							user_1_awaddr_valid		,
	output 	reg 							user_1_awaddr_ready		,
	
	output 	reg 	[AXI_ADDR_WIDTH-1:0]	arbiter_araddr			,
	output 	reg 	[AXI_ID_WIDTH-1:0]		arbiter_ar_id			,
	output 	reg 	[AXI_LEN_WIDTH-1:0]		arbiter_ar_len			,
	output 	reg 							arbiter_araddr_valid	,
	input 	wire 							arbiter_araddr_ready	,
	
	output 	reg 	[AXI_ADDR_WIDTH-1:0]	arbiter_awaddr			,
	output 	reg 	[AXI_ID_WIDTH-1:0]		arbiter_aw_id			,
	output 	reg 	[AXI_LEN_WIDTH-1:0]		arbiter_aw_len			,
	output 	reg 							arbiter_awaddr_valid	,
	input 	wire  							arbiter_awaddr_ready	,
	
	input 	wire 	[AXI_DATA_WIDTH-1:0]	user_0_wr_data			,
	input 	wire 							user_0_wr_data_valid	,
	input 	wire [DDR_DATA_MASK_WIDTH-1:0]	user_0_wstrb			,
	output 	wire 							user_0_wr_data_ready	,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		user_0_wr_id			,	//不支持数据反压时id信号由mux给出
	inout 	wire 							user_0_wr_data_last		, 	//不支持数据反压时last信号由mux给出
	
	output 	wire 	[AXI_DATA_WIDTH-1:0]	user_0_rd_data			,
	output 	wire 							user_0_rd_data_valid	,
	input 	wire 							user_0_rd_data_ready	,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		user_0_rd_id			,	//不支持数据反压时id信号由mux给出
	inout 	wire 							user_0_rd_data_last		,	//不支持数据反压时last信号由mux给出
	
	input 	wire 	[AXI_DATA_WIDTH-1:0]	user_1_wr_data			,
	input 	wire 							user_1_wr_data_valid	,
	input 	wire [DDR_DATA_MASK_WIDTH-1:0]	user_1_wstrb			,
	output 	wire 							user_1_wr_data_ready	,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		user_1_wr_id			,	//不支持数据反压时id信号由mux给出
	inout 	wire 							user_1_wr_data_last		,	//不支持数据反压时last信号由mux给出
	
	output 	wire 	[AXI_DATA_WIDTH-1:0]	user_1_rd_data			,
	output 	wire 							user_1_rd_data_valid	,
	input 	wire 							user_1_rd_data_ready	,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		user_1_rd_id			,	//不支持数据反压时id信号由mux给出
	inout 	wire 							user_1_rd_data_last		,	//不支持数据反压时last信号由mux给出
	
	output 	reg 	[AXI_DATA_WIDTH-1:0]	arbiter_wr_data			,
	output 	wire 							arbiter_wr_data_valid	,
	input 	wire 							arbiter_wr_data_ready	,
	output 	reg [DDR_DATA_MASK_WIDTH-1:0]	arbiter_wstrb			,
	input 	wire 	[AXI_ID_WIDTH-1:0]		arbiter_wr_id			, 	//不支持数据反压时id信号由arbiter给出
	input	wire 							arbiter_wr_data_last	, 	//不支持数据反压时last信号由arbiter给出
	
	input 	wire 	[AXI_DATA_WIDTH-1:0]	arbiter_rd_data			,
	input 	wire 							arbiter_rd_data_valid	,
	output 	wire 							arbiter_rd_data_ready	,
	input 	wire 	[AXI_ID_WIDTH-1:0]		arbiter_rd_id			,	//不支持数据反压时id信号由arbiter给出
	input	wire 							arbiter_rd_data_last		//不支持数据反压时last信号由arbiter给出
);
	generate
		if (DATA_BACKPRESSURE_EN == 1'b0) begin : DATA_BACKPRESSURE_DISABLED
			//采用数据MUX的方式来完成传输，DDR传输延迟的问题已经在仲裁器中解决,不需要FIFO缓冲
			localparam USER_0_ID_ARB = 4'b0000;
			localparam USER_1_ID_ARB = 4'b0001;
			// --------------------------------- 写通道 ---------------------------------
			reg 	[AXI_ID_WIDTH-1:0]		wr_user_to_grant	;
			reg 	[1:0]					wr_grant_ready_flag	;
			reg 	[CREDIT_DIGITS-1:0]		wr_user_0_credit 	,	wr_user_1_credit	;	// 信用点
			
			always@(posedge axi_clk) begin
				if(!rst_n) begin //reset 
					wr_user_0_credit <= CREDIT_MAX_NUM;
					wr_user_1_credit <= CREDIT_MAX_NUM;
				end
				else begin
					if(user_0_awaddr_valid && user_0_awaddr_ready) begin
						wr_user_0_credit <= wr_user_0_credit == {CREDIT_DIGITS{1'b0}} ? {CREDIT_DIGITS{1'b0}} : wr_user_0_credit - 1'b1; 
						//防止0减1导致溢出 
					end
					else if(user_0_wr_data_last) begin
						wr_user_0_credit <= wr_user_0_credit == {CREDIT_DIGITS{1'b1}} ? {CREDIT_DIGITS{1'b1}} : wr_user_0_credit + 1'b1; 
						//防止溢出 
					end
					
					if(user_1_awaddr_valid && user_1_awaddr_ready) begin
						wr_user_1_credit <= wr_user_1_credit == {CREDIT_DIGITS{1'b0}} ? {CREDIT_DIGITS{1'b0}} : wr_user_1_credit - 1'b1; 
						//防止0减1导致溢出 
					end
					else if(user_1_wr_data_last) begin
						wr_user_1_credit <= wr_user_1_credit == {CREDIT_DIGITS{1'b1}} ? {CREDIT_DIGITS{1'b1}} : wr_user_1_credit + 1'b1; 
						//防止溢出 
					end
				end
			end
			
			always@(posedge axi_clk) begin
				if(!rst_n) begin
					wr_user_to_grant <= {AXI_ID_WIDTH{1'b0}};
					wr_grant_ready_flag <= 2'b00;
				end
				else begin
					if(arbiter_awaddr_valid && arbiter_awaddr_ready) begin
						wr_user_to_grant <= {AXI_ID_WIDTH{1'b0}};
						wr_grant_ready_flag <= 2'b00;
					end
					else if(wr_grant_ready_flag == 2'b01)begin
						if(wr_user_to_grant == USER_0_ID_ARB && user_0_awaddr_valid && user_0_awaddr_ready) begin
							wr_grant_ready_flag <= 2'b11;
						end
					end
					else if(wr_grant_ready_flag == 2'b10)begin
						if(wr_user_to_grant == USER_1_ID_ARB && user_1_awaddr_valid && user_1_awaddr_ready) begin
							wr_grant_ready_flag <= 2'b11;
						end
					end
					else if(wr_grant_ready_flag == 2'b00)begin
						if(user_0_awaddr_valid && !user_0_awaddr_ready) begin
							wr_grant_ready_flag <= wr_user_0_credit > 0 ? 2'b01 : 2'b00;
							wr_user_to_grant <= wr_user_0_credit > 0 ? USER_0_ID_ARB : {AXI_ID_WIDTH{1'b0}};
						end
						else if(user_1_awaddr_valid && !user_1_awaddr_ready) begin
							wr_grant_ready_flag <= wr_user_1_credit > 0 ? 2'b10 : 2'b00;
							wr_user_to_grant <= wr_user_1_credit > 0 ? USER_1_ID_ARB : {AXI_ID_WIDTH{1'b0}};
						end
					end
				end
			end
			
			always@(posedge axi_clk) begin
				if(!rst_n) begin
					user_0_awaddr_ready <= 1'b0;
					user_1_awaddr_ready <= 1'b0;
				end
				else begin
					if(user_0_awaddr_valid && user_0_awaddr_ready) begin
						user_0_awaddr_ready <= 1'b0;
					end
					else if(wr_user_to_grant == USER_0_ID_ARB && wr_grant_ready_flag == 2'b01) begin
						user_0_awaddr_ready <= 1'b1;
					end
					if (user_1_awaddr_valid && user_1_awaddr_ready) begin
						user_1_awaddr_ready <= 1'b0;
					end
					else if(wr_user_to_grant == USER_1_ID_ARB && wr_grant_ready_flag == 2'b10) begin
						user_1_awaddr_ready <= 1'b1;
					end
				end
 			end
			
			wire 						wr_id_fifo_wr_en	;
			wire 	[AXI_ID_WIDTH-1:0]	wr_id_fifo_din		;
			wire 						wr_id_fifo_rd_en	;
			wire 	[AXI_ID_WIDTH-1:0] 	wr_id_fifo_dout		;
			wire 	[AXI_ID_WIDTH-1:0] 	wr_client_fifo_dout	;
			wire						wr_id_fifo_empty	;
			
			assign wr_id_fifo_din = wr_user_to_grant == USER_0_ID_ARB ? user_0_aw_id : user_1_aw_id;
			assign wr_id_fifo_wr_en = user_0_awaddr_valid && user_0_awaddr_ready || user_1_awaddr_valid && user_1_awaddr_ready;
			assign wr_id_fifo_rd_en = user_0_wr_data_last || user_1_wr_data_last;
			
			always@(posedge axi_clk) begin
				if(!rst_n) begin
					arbiter_awaddr_valid <= 1'b0;
					arbiter_awaddr <= {AXI_ADDR_WIDTH{1'b0}};
					arbiter_aw_id <= {AXI_ID_WIDTH{1'b0}};
					arbiter_aw_len <= {AXI_LEN_WIDTH{1'b0}};
				end
				else begin
					if(arbiter_awaddr_valid && arbiter_awaddr_ready) begin
						arbiter_awaddr_valid <= 1'b0;
						arbiter_awaddr <= {AXI_ADDR_WIDTH{1'b0}};
						arbiter_aw_id <= {AXI_ID_WIDTH{1'b0}};
						arbiter_aw_len <= {AXI_LEN_WIDTH{1'b0}};
					end
					else begin
						if(user_0_awaddr_valid && user_0_awaddr_ready) begin
							arbiter_awaddr_valid <= 1'b1;
							arbiter_awaddr <= user_0_awaddr;
							arbiter_aw_id  <= user_0_aw_id;
							arbiter_aw_len <= user_0_aw_len;
						end
						else if(user_1_awaddr_valid && user_1_awaddr_ready) begin
							arbiter_awaddr_valid <= 1'b1;
							arbiter_awaddr <= user_1_awaddr;
							arbiter_aw_id  <= user_1_aw_id;
							arbiter_aw_len <= user_1_aw_len;
						end
					end
				end
			end
			
			always@(*) begin
				arbiter_wr_data = {AXI_DATA_WIDTH{1'b0}};
				if(wr_client_fifo_dout == USER_0_ID_ARB && !wr_id_fifo_empty) begin
					arbiter_wr_data = user_0_wr_data;
					arbiter_wstrb = user_0_wstrb;
				end
				else if(wr_client_fifo_dout == USER_1_ID_ARB && !wr_id_fifo_empty) begin
					arbiter_wr_data = user_1_wr_data;
					arbiter_wstrb = user_1_wstrb;
				end
			end
			
			assign user_0_wr_data_last = !wr_id_fifo_empty ? arbiter_wr_data_last : 1'b0;
			assign user_0_wr_data_ready = !wr_id_fifo_empty ? arbiter_wr_data_ready : 1'b0;
			assign user_0_wr_id = !wr_id_fifo_empty ? wr_id_fifo_dout : {AXI_ID_WIDTH{1'b0}};
			
			assign user_1_wr_data_last = !wr_id_fifo_empty ? arbiter_wr_data_last : 1'b0;
			assign user_1_wr_data_ready = !wr_id_fifo_empty ? arbiter_wr_data_ready : 1'b0;
			assign user_1_wr_id = !wr_id_fifo_empty ? wr_id_fifo_dout : {AXI_ID_WIDTH{1'b0}};
			
			// id fifo
			axi_mux_id_fifo wr_id_fifo (
				.wr_data		(wr_id_fifo_din		),	// input [3:0]
				.wr_en			(wr_id_fifo_wr_en	),	// input
				.full			(					),	// output
				.almost_full	(					),	// output
				.rd_data		(wr_id_fifo_dout	),	// output [3:0]
				.rd_en			(wr_id_fifo_rd_en	),	// input
				.empty			(wr_id_fifo_empty	),	// output
				.almost_empty	(					),	// output
				.clk			(axi_clk			),	// input
				.rst			(!rst_n				)	// input
			);	
			
			axi_mux_id_fifo wr_client_fifo (
				.wr_data		(wr_user_to_grant	),	// input [3:0]
				.wr_en			(wr_id_fifo_wr_en	),	// input
				.full			(					),	// output
				.almost_full	(					),	// output
				.rd_data		(wr_client_fifo_dout),	// output [3:0]
				.rd_en			(wr_id_fifo_rd_en	),	// input
				.empty			(					),	// output
				.almost_empty	(					),	// output
				.clk			(axi_clk			),	// input
				.rst			(!rst_n				)	// input
			);	

			// --------------------------------- 读通道 ---------------------------------

			reg 	[AXI_ID_WIDTH-1:0]		rd_user_to_grant	;
			reg 	[1:0]					rd_grant_ready_flag	;
			reg 	[CREDIT_DIGITS-1:0]		rd_user_0_credit 	,	rd_user_1_credit	;	// 信用点
			
			always@(posedge axi_clk) begin
				if(!rst_n) begin //reset 
					rd_user_0_credit <= CREDIT_MAX_NUM;
					rd_user_1_credit <= CREDIT_MAX_NUM;
				end
				else begin
					if(user_0_araddr_valid && user_0_araddr_ready) begin
						rd_user_0_credit <= rd_user_0_credit == {CREDIT_DIGITS{1'b0}} ? rd_user_0_credit : rd_user_0_credit - 1'b1; 
						//防止0减1导致溢出 
					end
					else if(user_0_rd_data_last) begin
						rd_user_0_credit <= rd_user_0_credit == {CREDIT_DIGITS{1'b1}} ? rd_user_0_credit : rd_user_0_credit + 1'b1; 
						//防止溢出 
					end
					
					if(user_1_araddr_valid && user_1_araddr_ready) begin
						rd_user_1_credit <= rd_user_1_credit == {CREDIT_DIGITS{1'b0}} ? rd_user_1_credit : rd_user_1_credit - 1'b1; 
						//防止0减1导致溢出 
					end
					else if(user_1_rd_data_last) begin
						rd_user_1_credit <= rd_user_1_credit == {CREDIT_DIGITS{1'b1}} ? rd_user_1_credit : rd_user_1_credit + 1'b1; 
						//防止溢出 
					end
				end
			end
			
			always@(posedge axi_clk) begin
				if(!rst_n) begin
					rd_user_to_grant <= {AXI_ID_WIDTH{1'b0}};
					rd_grant_ready_flag <= 2'b00;
				end
				else begin
					if(rd_grant_ready_flag == 2'b11) begin
						if(arbiter_araddr_valid && arbiter_araddr_ready) begin
							rd_grant_ready_flag <= 2'b00;
							rd_user_to_grant <= {AXI_ID_WIDTH{1'b0}};
						end					
					end
					else if(rd_grant_ready_flag == 2'b01) begin
						if(rd_user_to_grant == USER_0_ID_ARB && user_0_araddr_valid && user_0_araddr_ready) begin
							rd_grant_ready_flag <= 2'b11;
						end
					end
					else if(rd_grant_ready_flag == 2'b10) begin
						if(rd_user_to_grant == USER_1_ID_ARB && user_1_araddr_valid && user_1_araddr_ready) begin
							rd_grant_ready_flag <= 2'b11;
						end
					end
					else if(rd_grant_ready_flag == 2'b00) begin
						if(user_0_araddr_valid && !user_0_araddr_ready) begin
							rd_grant_ready_flag <= rd_user_0_credit > 0 ? 2'b01 : 2'b00;
							rd_user_to_grant <= rd_user_0_credit > 0 ? USER_0_ID_ARB : {AXI_ID_WIDTH{1'b0}};
						end
						else if(user_1_araddr_valid && !user_1_araddr_ready) begin
							rd_grant_ready_flag <= rd_user_1_credit > 0 ? 2'b10 : 2'b00;
							rd_user_to_grant <= rd_user_1_credit > 0 ? USER_1_ID_ARB : {AXI_ID_WIDTH{1'b0}};
						end
					end
				end
			end
			
			always@(posedge axi_clk) begin
				if(!rst_n) begin
					user_0_araddr_ready <= 1'b0;
					user_1_araddr_ready <= 1'b0;
				end
				else begin
					if(user_0_araddr_valid && user_0_araddr_ready) begin
						user_0_araddr_ready <= 1'b0;
					end
					else if(rd_user_to_grant == USER_0_ID_ARB && rd_grant_ready_flag == 2'b01) begin
						user_0_araddr_ready <= 1'b1;
					end
					if (user_1_araddr_valid && user_1_araddr_ready) begin
						user_1_araddr_ready <= 1'b0;
					end
					else if(rd_user_to_grant == USER_1_ID_ARB && rd_grant_ready_flag == 2'b10) begin
						user_1_araddr_ready <= 1'b1;
					end
				end
 			end
			
			wire 						rd_id_fifo_wr_en	;
			wire 	[AXI_ID_WIDTH-1:0]	rd_id_fifo_din		;
			wire 						rd_id_fifo_rd_en	;
			wire 	[AXI_ID_WIDTH-1:0] 	rd_id_fifo_dout		;
			wire						rd_id_fifo_empty	;
			
			assign rd_id_fifo_din = rd_user_to_grant == USER_0_ID_ARB ? user_0_ar_id : user_1_ar_id;
			assign rd_id_fifo_wr_en = user_0_araddr_valid && user_0_araddr_ready || user_1_araddr_valid && user_1_araddr_ready;
			assign rd_id_fifo_rd_en = user_0_rd_data_last || user_1_rd_data_last;
			
			always@(posedge axi_clk) begin
				if(!rst_n) begin
					arbiter_araddr_valid <= 1'b0;
					arbiter_araddr <= {AXI_ADDR_WIDTH{1'b0}};
					arbiter_ar_id <= {AXI_ID_WIDTH{1'b0}};
					arbiter_ar_len <= {AXI_LEN_WIDTH{1'b0}};
				end
				else begin
					if(arbiter_araddr_valid && arbiter_araddr_ready) begin
						arbiter_araddr_valid <= 1'b0;
						arbiter_araddr <= {AXI_ADDR_WIDTH{1'b0}};
						arbiter_ar_id <= {AXI_ID_WIDTH{1'b0}};
						arbiter_ar_len <= {AXI_LEN_WIDTH{1'b0}};
					end
					else begin
						if(user_0_araddr_valid && user_0_araddr_ready && !arbiter_araddr_valid) begin
							arbiter_araddr_valid <= 1'b1;
							arbiter_araddr <= user_0_araddr;
							arbiter_ar_id <= user_0_ar_id;
							arbiter_ar_len <= user_0_ar_len;
						end
						else if(user_1_araddr_valid && user_1_araddr_ready && !arbiter_araddr_valid) begin
							arbiter_araddr_valid <= 1'b1;
							arbiter_araddr <= user_1_araddr;
							arbiter_ar_id <= user_1_ar_id;
							arbiter_ar_len <= user_1_ar_len;
						end
					end
				end
			end
			
			assign user_0_rd_data = !rd_id_fifo_empty ? arbiter_rd_data : {AXI_DATA_WIDTH{1'b0}};
			assign user_0_rd_data_last = !rd_id_fifo_empty ? arbiter_rd_data_last : 1'b0;
			assign user_0_rd_data_valid = !rd_id_fifo_empty ? arbiter_rd_data_valid : 1'b0;
			assign user_0_rd_id = !rd_id_fifo_empty ? rd_id_fifo_dout : {AXI_ID_WIDTH{1'b0}};
			
			assign user_1_rd_data = !rd_id_fifo_empty ? arbiter_rd_data : {AXI_DATA_WIDTH{1'b0}};
			assign user_1_rd_data_last = !rd_id_fifo_empty ? arbiter_rd_data_last : 1'b0;
			assign user_1_rd_data_valid = !rd_id_fifo_empty ? arbiter_rd_data_valid : 1'b0;
			assign user_1_rd_id = !rd_id_fifo_empty ? rd_id_fifo_dout : {AXI_ID_WIDTH{1'b0}};
			
			// id fifo
			axi_mux_id_fifo rd_id_fifo (
				.wr_data		(rd_id_fifo_din		),	// input [3:0]
				.wr_en			(rd_id_fifo_wr_en	),	// input
				.full			(					),	// output
				.almost_full	(					),	// output
				.rd_data		(rd_id_fifo_dout	),	// output [3:0]
				.rd_en			(rd_id_fifo_rd_en	),	// input
				.empty			(rd_id_fifo_empty	),	// output
				.almost_empty	(					),	// output
				.clk			(axi_clk			),	// input
				.rst			(!rst_n				)	// input
			);
		end
		
		else begin : DATA_BACKPRESSURE_ENABLED
			// in progress 暂不进行开发
		end
	endgenerate
endmodule