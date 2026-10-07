module axi_arbiter_v_2_0#(
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
	
	output 	wire	[7:0]					grant_busy				, //3: user_0_write , 2: user_1_write , 1: user_0_read , 0: user_1_read

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
	
    input 	wire 	[AXI_ADDR_WIDTH-1:0]	user_2_araddr			,
	input 	wire 	[AXI_ID_WIDTH-1:0]		user_2_ar_id			,
	input 	wire 	[AXI_LEN_WIDTH-1:0]		user_2_ar_len			,
	input 	wire 							user_2_araddr_valid		,
	output 	reg 							user_2_araddr_ready		,
	
	input 	wire 	[AXI_ADDR_WIDTH-1:0]	user_2_awaddr			,
	input 	wire 	[AXI_ID_WIDTH-1:0]		user_2_aw_id			,
	input 	wire 	[AXI_LEN_WIDTH-1:0]		user_2_aw_len			,
	input 	wire 							user_2_awaddr_valid		,
	output 	reg 							user_2_awaddr_ready		,
    input 	wire 	[AXI_ADDR_WIDTH-1:0]	user_3_araddr			,
	input 	wire 	[AXI_ID_WIDTH-1:0]		user_3_ar_id			,
	input 	wire 	[AXI_LEN_WIDTH-1:0]		user_3_ar_len			,
	input 	wire 							user_3_araddr_valid		,
	output 	reg 							user_3_araddr_ready		,
	
	input 	wire 	[AXI_ADDR_WIDTH-1:0]	user_3_awaddr			,
	input 	wire 	[AXI_ID_WIDTH-1:0]		user_3_aw_id			,
	input 	wire 	[AXI_LEN_WIDTH-1:0]		user_3_aw_len			,
	input 	wire 							user_3_awaddr_valid		,
	output 	reg 							user_3_awaddr_ready		,

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
	
    input 	wire 	[AXI_DATA_WIDTH-1:0]	user_2_wr_data			,
	input 	wire 							user_2_wr_data_valid	,
	input 	wire [DDR_DATA_MASK_WIDTH-1:0]	user_2_wstrb			,
	output 	wire 							user_2_wr_data_ready	,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		user_2_wr_id			,	//不支持数据反压时id信号由mux给出
	inout 	wire 							user_2_wr_data_last		,	//不支持数据反压时last信号由mux给出
	
	output 	wire 	[AXI_DATA_WIDTH-1:0]	user_2_rd_data			,
	output 	wire 							user_2_rd_data_valid	,
	input 	wire 							user_2_rd_data_ready	,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		user_2_rd_id			,	//不支持数据反压时id信号由mux给出
	inout 	wire 							user_2_rd_data_last		,	//不支持数据反压时last信号由mux给出

    input 	wire 	[AXI_DATA_WIDTH-1:0]	user_3_wr_data			,
	input 	wire 							user_3_wr_data_valid	,
	input 	wire [DDR_DATA_MASK_WIDTH-1:0]	user_3_wstrb			,
	output 	wire 							user_3_wr_data_ready	,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		user_3_wr_id			,	//不支持数据反压时id信号由mux给出
	inout 	wire 							user_3_wr_data_last		,	//不支持数据反压时last信号由mux给出
	
	output 	wire 	[AXI_DATA_WIDTH-1:0]	user_3_rd_data			,
	output 	wire 							user_3_rd_data_valid	,
	input 	wire 							user_3_rd_data_ready	,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		user_3_rd_id			,	//不支持数据反压时id信号由mux给出
	inout 	wire 							user_3_rd_data_last		,	//不支持数据反压时last信号由mux给出

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
			localparam USER_0_ID_ARB = 4'b0001;
			localparam USER_1_ID_ARB = 4'b0010;
            localparam USER_2_ID_ARB = 4'b0011;
			localparam USER_3_ID_ARB = 4'b0100;
			// --------------------------------- 写通道 ---------------------------------
			reg 	[AXI_ID_WIDTH-1:0]		wr_user_to_grant	;
			reg 	[3:0]					wr_grant_ready_flag	;
			reg 	[CREDIT_DIGITS-1:0]		wr_user_credit[3:0] ;
			
            integer i;
			always@(posedge axi_clk) begin
				if(!rst_n) begin //reset 
					for(i=0;i<4;i=i+1) begin
                        wr_user_credit[i] <= CREDIT_MAX_NUM;
                    end
				end
				else begin
					if(user_0_awaddr_valid && user_0_awaddr_ready) begin
						wr_user_credit[0] <= wr_user_credit[0] == {CREDIT_DIGITS{1'b0}} ? {CREDIT_DIGITS{1'b0}} : wr_user_credit[0] - 1'b1; 
						//防止0减1导致溢出 
					end
					else if(user_0_wr_data_last) begin
						wr_user_credit[0] <= wr_user_credit[0] == {CREDIT_DIGITS{1'b1}} ? {CREDIT_DIGITS{1'b1}} : wr_user_credit[0] + 1'b1; 
						//防止溢出 
					end
					
					if(user_1_awaddr_valid && user_1_awaddr_ready) begin
						wr_user_credit[1] <= wr_user_credit[1] == {CREDIT_DIGITS{1'b0}} ? {CREDIT_DIGITS{1'b0}} : wr_user_credit[1] - 1'b1; 
						//防止0减1导致溢出 
					end
					else if(user_1_wr_data_last) begin
						wr_user_credit[1] <= wr_user_credit[1] == {CREDIT_DIGITS{1'b1}} ? {CREDIT_DIGITS{1'b1}} : wr_user_credit[1] + 1'b1; 
						//防止溢出 
					end

                    if(user_2_awaddr_valid && user_2_awaddr_ready) begin
						wr_user_credit[2] <= wr_user_credit[2] == {CREDIT_DIGITS{1'b0}} ? {CREDIT_DIGITS{1'b0}} : wr_user_credit[2] - 1'b1; 
						//防止0减1导致溢出 
					end
					else if(user_2_wr_data_last) begin
						wr_user_credit[2] <= wr_user_credit[2] == {CREDIT_DIGITS{1'b1}} ? {CREDIT_DIGITS{1'b1}} : wr_user_credit[2] + 1'b1; 
						//防止溢出 
					end

                    if(user_3_awaddr_valid && user_3_awaddr_ready) begin
						wr_user_credit[3] <= wr_user_credit[3] == {CREDIT_DIGITS{1'b0}} ? {CREDIT_DIGITS{1'b0}} : wr_user_credit[3] - 1'b1; 
						//防止0减1导致溢出 
					end
					else if(user_3_wr_data_last) begin
						wr_user_credit[3] <= wr_user_credit[3] == {CREDIT_DIGITS{1'b1}} ? {CREDIT_DIGITS{1'b1}} : wr_user_credit[3] + 1'b1; 
						//防止溢出 
					end
				end
			end
			
			always@(posedge axi_clk) begin
				if(!rst_n) begin
					wr_user_to_grant <= {AXI_ID_WIDTH{1'b0}};
					wr_grant_ready_flag <= 4'b0000;
				end
				else begin
					if(arbiter_awaddr_valid && arbiter_awaddr_ready && wr_grant_ready_flag == 4'h5) begin
						wr_user_to_grant <= {AXI_ID_WIDTH{1'b0}};
						wr_grant_ready_flag <= 4'h0;
					end
					else if(wr_grant_ready_flag == 4'h1)begin
						if(wr_user_to_grant == USER_0_ID_ARB && user_0_awaddr_valid && user_0_awaddr_ready) begin
							wr_grant_ready_flag <= 4'h5;
						end
					end
                    else if(wr_grant_ready_flag == 4'h2)begin
						if(wr_user_to_grant == USER_1_ID_ARB && user_1_awaddr_valid && user_1_awaddr_ready) begin
							wr_grant_ready_flag <= 4'h5;
						end
					end
                    else if(wr_grant_ready_flag == 4'h3)begin
						if(wr_user_to_grant == USER_2_ID_ARB && user_2_awaddr_valid && user_2_awaddr_ready) begin
							wr_grant_ready_flag <= 4'h5;
						end
					end
                    else if(wr_grant_ready_flag == 4'h4)begin
						if(wr_user_to_grant == USER_3_ID_ARB && user_3_awaddr_valid && user_3_awaddr_ready) begin
							wr_grant_ready_flag <= 4'h5;
						end
					end
					else if(wr_grant_ready_flag == 4'h0)begin
						if(user_0_awaddr_valid && !user_0_awaddr_ready) begin
							wr_grant_ready_flag <= wr_user_credit[0] > 0 ? 4'h1 : 4'h0;
							wr_user_to_grant <= wr_user_credit[0] > 0 ? USER_0_ID_ARB : {AXI_ID_WIDTH{1'b0}};
						end
						else if(user_1_awaddr_valid && !user_1_awaddr_ready) begin
							wr_grant_ready_flag <= wr_user_credit[1] > 0 ? 4'h2 : 4'h0;
							wr_user_to_grant <= wr_user_credit[1] > 0 ? USER_1_ID_ARB : {AXI_ID_WIDTH{1'b0}};
						end
                        else if(user_2_awaddr_valid && !user_2_awaddr_ready) begin
							wr_grant_ready_flag <= wr_user_credit[2] > 0 ? 4'h3 : 4'h0;
							wr_user_to_grant <= wr_user_credit[2] > 0 ? USER_2_ID_ARB : {AXI_ID_WIDTH{1'b0}};
						end
                        else if(user_3_awaddr_valid && !user_3_awaddr_ready) begin
							wr_grant_ready_flag <= wr_user_credit[3] > 0 ? 4'h4 : 4'h0;
							wr_user_to_grant <= wr_user_credit[3] > 0 ? USER_3_ID_ARB : {AXI_ID_WIDTH{1'b0}};
						end
					end
				end
			end
			
			always@(posedge axi_clk) begin
				if(!rst_n) begin
					user_0_awaddr_ready <= 1'b0;
					user_1_awaddr_ready <= 1'b0;
                    user_2_awaddr_ready <= 1'b0;
					user_3_awaddr_ready <= 1'b0;
				end
				else begin
					if(user_0_awaddr_valid && user_0_awaddr_ready) begin
						user_0_awaddr_ready <= 1'b0;
					end
					else if(wr_user_to_grant == USER_0_ID_ARB && wr_grant_ready_flag == 4'h1) begin
						user_0_awaddr_ready <= 1'b1;
					end

					if (user_1_awaddr_valid && user_1_awaddr_ready) begin
						user_1_awaddr_ready <= 1'b0;
					end
					else if(wr_user_to_grant == USER_1_ID_ARB && wr_grant_ready_flag == 4'h2) begin
						user_1_awaddr_ready <= 1'b1;
					end

                    if (user_2_awaddr_valid && user_2_awaddr_ready) begin
						user_2_awaddr_ready <= 1'b0;
					end
					else if(wr_user_to_grant == USER_2_ID_ARB && wr_grant_ready_flag == 4'h3) begin
						user_2_awaddr_ready <= 1'b1;
					end

                    if (user_3_awaddr_valid && user_3_awaddr_ready) begin
						user_3_awaddr_ready <= 1'b0;
					end
					else if(wr_user_to_grant == USER_3_ID_ARB && wr_grant_ready_flag == 4'h4) begin
						user_3_awaddr_ready <= 1'b1;
					end
				end
 			end
			
			reg 						wr_client_fifo_wr_en;
			reg 	[AXI_ID_WIDTH-1:0]	wr_client_fifo_din	;
			reg 						wr_client_fifo_rd_en;
			wire 	[AXI_ID_WIDTH-1:0] 	wr_client_fifo_dout	;
			wire						wr_client_fifo_empty;
			
            always@(*) begin
                wr_client_fifo_din = {AXI_ID_WIDTH{1'b0}};
                case(wr_user_to_grant) 
                    USER_0_ID_ARB : wr_client_fifo_din = USER_0_ID_ARB;
                    USER_1_ID_ARB : wr_client_fifo_din = USER_1_ID_ARB;
                    USER_2_ID_ARB : wr_client_fifo_din = USER_2_ID_ARB;
                    USER_3_ID_ARB : wr_client_fifo_din = USER_3_ID_ARB;
                    default: wr_client_fifo_din = {AXI_ID_WIDTH{1'b0}};
                endcase
            end

            always@(*) begin
                wr_client_fifo_wr_en = 1'b0;
                case(wr_user_to_grant) 
                    USER_0_ID_ARB : wr_client_fifo_wr_en = user_0_awaddr_valid && user_0_awaddr_ready;
                    USER_1_ID_ARB : wr_client_fifo_wr_en = user_1_awaddr_valid && user_1_awaddr_ready;
                    USER_2_ID_ARB : wr_client_fifo_wr_en = user_2_awaddr_valid && user_2_awaddr_ready;
                    USER_3_ID_ARB : wr_client_fifo_wr_en = user_3_awaddr_valid && user_3_awaddr_ready;
                    default: wr_client_fifo_wr_en = 1'b0;
                endcase
            end

            always@(*) begin
                wr_client_fifo_rd_en = 1'b0;
                case(wr_client_fifo_dout) 
                    USER_0_ID_ARB : wr_client_fifo_rd_en = user_0_wr_data_last;
                    USER_1_ID_ARB : wr_client_fifo_rd_en = user_1_wr_data_last;
                    USER_2_ID_ARB : wr_client_fifo_rd_en = user_2_wr_data_last;
                    USER_3_ID_ARB : wr_client_fifo_rd_en = user_3_wr_data_last;
                    default: wr_client_fifo_rd_en = 1'b0;
                endcase
            end
			
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
                        else if(user_2_awaddr_valid && user_2_awaddr_ready) begin
							arbiter_awaddr_valid <= 1'b1;
							arbiter_awaddr <= user_2_awaddr;
							arbiter_aw_id  <= user_2_aw_id;
							arbiter_aw_len <= user_2_aw_len;
						end
                        else if(user_3_awaddr_valid && user_3_awaddr_ready) begin
							arbiter_awaddr_valid <= 1'b1;
							arbiter_awaddr <= user_3_awaddr;
							arbiter_aw_id  <= user_3_aw_id;
							arbiter_aw_len <= user_3_aw_len;
						end
					end
				end
			end
			
			always@(*) begin
				arbiter_wr_data = {AXI_DATA_WIDTH{1'b0}};
				if(wr_client_fifo_dout == USER_0_ID_ARB && !wr_client_fifo_empty) begin
					arbiter_wr_data = user_0_wr_data;
					arbiter_wstrb = user_0_wstrb;
				end
				else if(wr_client_fifo_dout == USER_1_ID_ARB && !wr_client_fifo_empty) begin
					arbiter_wr_data = user_1_wr_data;
					arbiter_wstrb = user_1_wstrb;
				end
                else if(wr_client_fifo_dout == USER_2_ID_ARB && !wr_client_fifo_empty) begin
					arbiter_wr_data = user_2_wr_data;
					arbiter_wstrb = user_2_wstrb;
				end
                else if(wr_client_fifo_dout == USER_3_ID_ARB && !wr_client_fifo_empty) begin
					arbiter_wr_data = user_3_wr_data;
					arbiter_wstrb = user_3_wstrb;
				end
			end
			
            assign user_0_wr_data_ready = (wr_client_fifo_dout == USER_0_ID_ARB) && !wr_client_fifo_empty ? arbiter_wr_data_ready : 1'b0;
            assign user_1_wr_data_ready = (wr_client_fifo_dout == USER_1_ID_ARB) && !wr_client_fifo_empty ? arbiter_wr_data_ready : 1'b0;
            assign user_2_wr_data_ready = (wr_client_fifo_dout == USER_2_ID_ARB) && !wr_client_fifo_empty ? arbiter_wr_data_ready : 1'b0;
            assign user_3_wr_data_ready = (wr_client_fifo_dout == USER_3_ID_ARB) && !wr_client_fifo_empty ? arbiter_wr_data_ready : 1'b0;

            assign user_0_wr_data_last = (wr_client_fifo_dout == USER_0_ID_ARB) && !wr_client_fifo_empty ? arbiter_wr_data_last : 1'b0;
            assign user_1_wr_data_last = (wr_client_fifo_dout == USER_1_ID_ARB) && !wr_client_fifo_empty ? arbiter_wr_data_last : 1'b0;
            assign user_2_wr_data_last = (wr_client_fifo_dout == USER_2_ID_ARB) && !wr_client_fifo_empty ? arbiter_wr_data_last : 1'b0;
            assign user_3_wr_data_last = (wr_client_fifo_dout == USER_3_ID_ARB) && !wr_client_fifo_empty ? arbiter_wr_data_last : 1'b0;

            assign user_0_wr_id = (wr_client_fifo_dout == USER_0_ID_ARB) && !wr_client_fifo_empty ? arbiter_wr_id : {AXI_ID_WIDTH{1'b0}};
            assign user_1_wr_id = (wr_client_fifo_dout == USER_1_ID_ARB) && !wr_client_fifo_empty ? arbiter_wr_id : {AXI_ID_WIDTH{1'b0}};
            assign user_2_wr_id = (wr_client_fifo_dout == USER_2_ID_ARB) && !wr_client_fifo_empty ? arbiter_wr_id : {AXI_ID_WIDTH{1'b0}};
            assign user_3_wr_id = (wr_client_fifo_dout == USER_3_ID_ARB) && !wr_client_fifo_empty ? arbiter_wr_id : {AXI_ID_WIDTH{1'b0}};

			// id fifo
			axi_mux_id_fifo wr_client_fifo (
				.wr_data		(wr_client_fifo_din	),	// input [3:0]
				.wr_en			(wr_client_fifo_wr_en	),	// input
				.full			(					),	// output
				.almost_full	(					),	// output
				.rd_data		(wr_client_fifo_dout),	// output [3:0]
				.rd_en			(wr_client_fifo_rd_en),	// input
				.empty			(wr_client_fifo_empty),	// output
				.almost_empty	(					),	// output
				.clk			(axi_clk			),	// input
				.rst			(!rst_n				)	// input
			);	
			

			// --------------------------------- 读通道 ---------------------------------

			reg 	[AXI_ID_WIDTH-1:0]		rd_user_to_grant	;
			reg 	[3:0]					rd_grant_ready_flag	;
			reg 	[CREDIT_DIGITS-1:0]		rd_user_credit[3:0] ;
			
			always@(posedge axi_clk) begin
				if(!rst_n) begin //reset 
					rd_user_credit[0] <= CREDIT_MAX_NUM;
                    rd_user_credit[1] <= CREDIT_MAX_NUM;
                    rd_user_credit[2] <= CREDIT_MAX_NUM;
                    rd_user_credit[3] <= CREDIT_MAX_NUM;
				end
				else begin
					if(user_0_araddr_valid && user_0_araddr_ready) begin
						rd_user_credit[0] <= rd_user_credit[0] == {CREDIT_DIGITS{1'b0}} ? {CREDIT_DIGITS{1'b0}} : rd_user_credit[0] - 1'b1; 
						//防止0减1导致溢出 
					end
					else if(user_0_rd_data_last) begin
						rd_user_credit[0] <= rd_user_credit[0] == {CREDIT_DIGITS{1'b1}} ? {CREDIT_DIGITS{1'b1}} : rd_user_credit[0] + 1'b1; 
						//防止溢出 
					end
					
					if(user_1_araddr_valid && user_1_araddr_ready) begin
						rd_user_credit[1] <= rd_user_credit[1] == {CREDIT_DIGITS{1'b0}} ? {CREDIT_DIGITS{1'b0}} : rd_user_credit[1] - 1'b1; 
						//防止0减1导致溢出 
					end
					else if(user_1_rd_data_last) begin
						rd_user_credit[1] <= rd_user_credit[1] == {CREDIT_DIGITS{1'b1}} ? {CREDIT_DIGITS{1'b1}} : rd_user_credit[1] + 1'b1; 
						//防止溢出 
					end

                    if(user_2_araddr_valid && user_2_araddr_ready) begin
						rd_user_credit[2] <= rd_user_credit[2] == {CREDIT_DIGITS{1'b0}} ? {CREDIT_DIGITS{1'b0}} : rd_user_credit[2] - 1'b1; 
						//防止0减1导致溢出 
					end
					else if(user_2_rd_data_last) begin
						rd_user_credit[2] <= rd_user_credit[2] == {CREDIT_DIGITS{1'b1}} ? {CREDIT_DIGITS{1'b1}} : rd_user_credit[2] + 1'b1; 
						//防止溢出 
					end

                    if(user_3_araddr_valid && user_3_araddr_ready) begin
						rd_user_credit[3] <= rd_user_credit[3] == {CREDIT_DIGITS{1'b0}} ? {CREDIT_DIGITS{1'b0}} : rd_user_credit[3] - 1'b1; 
						//防止0减1导致溢出 
					end
					else if(user_3_rd_data_last) begin
						rd_user_credit[3] <= rd_user_credit[3] == {CREDIT_DIGITS{1'b1}} ? {CREDIT_DIGITS{1'b1}} : rd_user_credit[3] + 1'b1; 
						//防止溢出 
					end
				end
			end
			
			always@(posedge axi_clk) begin
				if(!rst_n) begin
					rd_user_to_grant <= {AXI_ID_WIDTH{1'b0}};
					rd_grant_ready_flag <= 4'b0000;
				end
				else begin
					if(arbiter_araddr_valid && arbiter_araddr_ready && rd_grant_ready_flag == 4'h5) begin
						rd_user_to_grant <= {AXI_ID_WIDTH{1'b0}};
						rd_grant_ready_flag <= 4'h0;
					end
					else if(rd_grant_ready_flag == 4'h1) begin
						if(rd_user_to_grant == USER_0_ID_ARB && user_0_araddr_valid && user_0_araddr_ready) begin
							rd_grant_ready_flag <= 4'h5;
						end
					end
					else if(rd_grant_ready_flag == 4'h2) begin
						if(rd_user_to_grant == USER_1_ID_ARB && user_1_araddr_valid && user_1_araddr_ready) begin
							rd_grant_ready_flag <= 4'h5;
						end
					end
					else if(rd_grant_ready_flag == 4'h3) begin
						if(rd_user_to_grant == USER_2_ID_ARB && user_2_araddr_valid && user_2_araddr_ready) begin
							rd_grant_ready_flag <= 4'h5;
						end
					end
					else if(rd_grant_ready_flag == 4'h4) begin
						if(rd_user_to_grant == USER_3_ID_ARB && user_3_araddr_valid && user_3_araddr_ready) begin
							rd_grant_ready_flag <= 4'h5;
						end
					end
					else if(rd_grant_ready_flag == 4'h0) begin
						if(user_0_araddr_valid && !user_0_araddr_ready) begin
							rd_grant_ready_flag <= rd_user_credit[0] > 0 ? 4'h1 : 4'h0;
							rd_user_to_grant <= rd_user_credit[0] > 0 ? USER_0_ID_ARB : {AXI_ID_WIDTH{1'b0}};
						end
						else if(user_1_araddr_valid && !user_1_araddr_ready) begin
							rd_grant_ready_flag <= rd_user_credit[1] > 0 ? 4'h2 : 4'h0;
							rd_user_to_grant <= rd_user_credit[1] > 0 ? USER_1_ID_ARB : {AXI_ID_WIDTH{1'b0}};
						end
						else if(user_2_araddr_valid && !user_2_araddr_ready) begin
							rd_grant_ready_flag <= rd_user_credit[2] > 0 ? 4'h3 : 4'h0;
							rd_user_to_grant <= rd_user_credit[2] > 0 ? USER_2_ID_ARB : {AXI_ID_WIDTH{1'b0}};
						end
						else if(user_3_araddr_valid && !user_3_araddr_ready) begin
							rd_grant_ready_flag <= rd_user_credit[3] > 0 ? 4'h4 : 4'h0;
							rd_user_to_grant <= rd_user_credit[3] > 0 ? USER_3_ID_ARB : {AXI_ID_WIDTH{1'b0}};
						end
					end
				end
			end
			
			always@(posedge axi_clk) begin
				if(!rst_n) begin
					user_0_araddr_ready <= 1'b0;
					user_1_araddr_ready <= 1'b0;
                    user_2_araddr_ready <= 1'b0;
					user_3_araddr_ready <= 1'b0;
				end
				else begin
					if(user_0_araddr_valid && user_0_araddr_ready) begin
						user_0_araddr_ready <= 1'b0;
					end
					else if(rd_user_to_grant == USER_0_ID_ARB && rd_grant_ready_flag == 4'h1) begin
						user_0_araddr_ready <= 1'b1;
					end

					if (user_1_araddr_valid && user_1_araddr_ready) begin
						user_1_araddr_ready <= 1'b0;
					end
					else if(rd_user_to_grant == USER_1_ID_ARB && rd_grant_ready_flag == 4'h2) begin
						user_1_araddr_ready <= 1'b1;
					end

                    if (user_2_araddr_valid && user_2_araddr_ready) begin
						user_2_araddr_ready <= 1'b0;
					end
					else if(rd_user_to_grant == USER_2_ID_ARB && rd_grant_ready_flag == 4'h3) begin
						user_2_araddr_ready <= 1'b1;
					end

                    if (user_3_araddr_valid && user_3_araddr_ready) begin
						user_3_araddr_ready <= 1'b0;
					end
					else if(rd_user_to_grant == USER_3_ID_ARB && rd_grant_ready_flag == 4'h4) begin
						user_3_araddr_ready <= 1'b1;
					end
				end
 			end
			
			reg 						rd_client_fifo_wr_en	;
			reg 	[AXI_ID_WIDTH-1:0]	rd_client_fifo_din		;
			reg 						rd_client_fifo_rd_en	;
			wire 	[AXI_ID_WIDTH-1:0] 	rd_client_fifo_dout		;
			wire						rd_client_fifo_empty	;
			
            always@(*) begin
                rd_client_fifo_din = {AXI_ID_WIDTH{1'b0}};
                case(rd_user_to_grant) 
                    USER_0_ID_ARB : rd_client_fifo_din = USER_0_ID_ARB;
                    USER_1_ID_ARB : rd_client_fifo_din = USER_1_ID_ARB;
                    USER_2_ID_ARB : rd_client_fifo_din = USER_2_ID_ARB;
                    USER_3_ID_ARB : rd_client_fifo_din = USER_3_ID_ARB;
                    default: rd_client_fifo_din = {AXI_ID_WIDTH{1'b0}};
                endcase
            end

            always@(*) begin
                rd_client_fifo_wr_en = 1'b0;
                case(rd_user_to_grant) 
                    USER_0_ID_ARB : rd_client_fifo_wr_en = user_0_araddr_valid && user_0_araddr_ready;
                    USER_1_ID_ARB : rd_client_fifo_wr_en = user_1_araddr_valid && user_1_araddr_ready;
                    USER_2_ID_ARB : rd_client_fifo_wr_en = user_2_araddr_valid && user_2_araddr_ready;
                    USER_3_ID_ARB : rd_client_fifo_wr_en = user_3_araddr_valid && user_3_araddr_ready;
                    default: rd_client_fifo_wr_en = 1'b0;
                endcase
            end

            always@(*) begin
                rd_client_fifo_rd_en = 1'b0;
                case(rd_client_fifo_dout) 
                    USER_0_ID_ARB : rd_client_fifo_rd_en = user_0_rd_data_last;
                    USER_1_ID_ARB : rd_client_fifo_rd_en = user_1_rd_data_last;
                    USER_2_ID_ARB : rd_client_fifo_rd_en = user_2_rd_data_last;
                    USER_3_ID_ARB : rd_client_fifo_rd_en = user_3_rd_data_last;
                    default: rd_client_fifo_rd_en = 1'b0;
                endcase
            end

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
						if(user_0_araddr_valid && user_0_araddr_ready) begin
							arbiter_araddr_valid <= 1'b1;
							arbiter_araddr <= user_0_araddr;
							arbiter_ar_id <= user_0_ar_id;
							arbiter_ar_len <= user_0_ar_len;
						end
						else if(user_1_araddr_valid && user_1_araddr_ready) begin
							arbiter_araddr_valid <= 1'b1;
							arbiter_araddr <= user_1_araddr;
							arbiter_ar_id <= user_1_ar_id;
							arbiter_ar_len <= user_1_ar_len;
						end
                        else if(user_2_araddr_valid && user_2_araddr_ready) begin
							arbiter_araddr_valid <= 1'b1;
							arbiter_araddr <= user_2_araddr;
							arbiter_ar_id <= user_2_ar_id;
							arbiter_ar_len <= user_2_ar_len;
						end
                        else if(user_3_araddr_valid && user_3_araddr_ready) begin
							arbiter_araddr_valid <= 1'b1;
							arbiter_araddr <= user_3_araddr;
							arbiter_ar_id <= user_3_ar_id;
							arbiter_ar_len <= user_3_ar_len;
						end
					end
				end
			end
			
			assign user_0_rd_data = (rd_client_fifo_dout == USER_0_ID_ARB) && !rd_client_fifo_empty ? arbiter_rd_data : {AXI_DATA_WIDTH{1'b0}};
			assign user_0_rd_data_last = (rd_client_fifo_dout == USER_0_ID_ARB) && !rd_client_fifo_empty ? arbiter_rd_data_last : 1'b0;
			assign user_0_rd_data_valid = (rd_client_fifo_dout == USER_0_ID_ARB) && !rd_client_fifo_empty ? arbiter_rd_data_valid : 1'b0;
			assign user_0_rd_id = (rd_client_fifo_dout == USER_0_ID_ARB) && !rd_client_fifo_empty ? arbiter_rd_id : {AXI_ID_WIDTH{1'b0}};
			
			assign user_1_rd_data = (rd_client_fifo_dout == USER_1_ID_ARB) && !rd_client_fifo_empty ? arbiter_rd_data : {AXI_DATA_WIDTH{1'b0}};
			assign user_1_rd_data_last = (rd_client_fifo_dout == USER_1_ID_ARB) && !rd_client_fifo_empty ? arbiter_rd_data_last : 1'b0;
			assign user_1_rd_data_valid = (rd_client_fifo_dout == USER_1_ID_ARB) && !rd_client_fifo_empty ? arbiter_rd_data_valid : 1'b0;
			assign user_1_rd_id = (rd_client_fifo_dout == USER_1_ID_ARB) && !rd_client_fifo_empty ? arbiter_rd_id : {AXI_ID_WIDTH{1'b0}};
			
            assign user_2_rd_data = (rd_client_fifo_dout == USER_2_ID_ARB) && !rd_client_fifo_empty ? arbiter_rd_data : {AXI_DATA_WIDTH{1'b0}};
			assign user_2_rd_data_last = (rd_client_fifo_dout == USER_2_ID_ARB) && !rd_client_fifo_empty ? arbiter_rd_data_last : 1'b0;
			assign user_2_rd_data_valid = (rd_client_fifo_dout == USER_2_ID_ARB) && !rd_client_fifo_empty ? arbiter_rd_data_valid : 1'b0;
			assign user_2_rd_id = (rd_client_fifo_dout == USER_2_ID_ARB) && !rd_client_fifo_empty ? arbiter_rd_id : {AXI_ID_WIDTH{1'b0}};

            assign user_3_rd_data = (rd_client_fifo_dout == USER_3_ID_ARB) && !rd_client_fifo_empty ? arbiter_rd_data : {AXI_DATA_WIDTH{1'b0}};
			assign user_3_rd_data_last = (rd_client_fifo_dout == USER_3_ID_ARB) && !rd_client_fifo_empty ? arbiter_rd_data_last : 1'b0;
			assign user_3_rd_data_valid = (rd_client_fifo_dout == USER_3_ID_ARB) && !rd_client_fifo_empty ? arbiter_rd_data_valid : 1'b0;
			assign user_3_rd_id = (rd_client_fifo_dout == USER_3_ID_ARB) && !rd_client_fifo_empty ? arbiter_rd_id : {AXI_ID_WIDTH{1'b0}};
			// id fifo
			axi_mux_id_fifo rd_client_fifo (
				.wr_data		(rd_client_fifo_din	),	// input [3:0]
				.wr_en			(rd_client_fifo_wr_en),	// input
				.full			(					),	// output
				.almost_full	(					),	// output
				.rd_data		(rd_client_fifo_dout),	// output [3:0]
				.rd_en			(rd_client_fifo_rd_en),	// input
				.empty			(rd_client_fifo_empty),	// output
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