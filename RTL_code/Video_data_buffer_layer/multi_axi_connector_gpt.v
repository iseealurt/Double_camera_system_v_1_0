module multi_axi_connector#(
	parameter		AXI_ADDR_WIDTH			=	28					,
	parameter 		AXI_DATA_WIDTH			=	256					,
	parameter 		AXI_ID_WIDTH			=	4					,
	parameter		AXI_LEN_WIDTH			=	4					,
	parameter 		DDR_DATA_MASK_WIDTH		=	32					,
	parameter 		DATA_BACKPRESSURE_EN	=	1'b0				,
	parameter 		ARBITER_CLIENT_ID		=	4'b0001				, // 所冒用的仲裁器用户ID
	parameter		USER_0_AXI_ID 			=	4'b0001				,
	parameter		USER_1_AXI_ID 			=	4'b0011				,
	parameter		CREDIT_DIGITS			=	4					,
	parameter 		CREDIT_MAX_NUM			=	4'd10				
)(
	input 	wire 							axi_clk					,
	input 	wire							rst_n					,
	
	output 	wire	[3:0]					grant_busy				, //3: user_0_write , 2: user_1_write , 1: user_0_read , 0: user_1_read
	output 	wire 	[3:0]					grant_overtime			, //3: user_0_write , 2: user_1_write , 1: user_0_read , 0: user_1_read
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
	
	output 	wire 	[AXI_ADDR_WIDTH-1:0]	arbitor_araddr			,
	output 	wire 	[AXI_ID_WIDTH-1:0]		arbitor_ar_id			,
	output 	wire 	[AXI_LEN_WIDTH-1:0]		arbitor_ar_len			,
	output 	wire 							arbitor_araddr_valid	,
	input 	wire 							arbitor_araddr_ready	,
	
	output 	wire 	[AXI_ADDR_WIDTH-1:0]	arbitor_awaddr			,
	output 	wire 	[AXI_ID_WIDTH-1:0]		arbitor_aw_id			,
	output 	wire 	[AXI_LEN_WIDTH-1:0]		arbitor_aw_len			,
	output 	wire 							arbitor_awaddr_valid	,
	input 	wire  							arbitor_awaddr_ready	,
	
	input 	wire 	[AXI_DATA_WIDTH-1:0]	user_0_wr_data			,
	input 	wire 							user_0_wr_data_valid	,
	input 	wire [DDR_DATA_MASK_WIDTH-1:0]	user_0_wstrb			,
	output 	reg 							user_0_wr_data_ready	,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		user_0_wr_id			,	// 不支持数据反压时id信号由mux给出
	inout 	wire 							user_0_wr_data_last		, 	// 不支持数据反压时last信号由mux给出
	
	output 	wire 	[AXI_DATA_WIDTH-1:0]	user_0_rd_data			,
	output 	wire 							user_0_rd_data_valid	,
	input 	wire 							user_0_rd_data_ready	,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		user_0_rd_id			,	// 不支持数据反压时id信号由mux给出
	inout 	wire 							user_0_rd_data_last		,	// 不支持数据反压时last信号由mux给出
	
	input 	wire 	[AXI_DATA_WIDTH-1:0]	user_1_wr_data			,
	input 	wire 							user_1_wr_data_valid	,
	input 	wire [DDR_DATA_MASK_WIDTH-1:0]	user_1_wstrb			,
	output 	reg 							user_1_wr_data_ready	,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		user_1_wr_id			,	// 不支持数据反压时id信号由mux给出
	inout 	wire 							user_1_wr_data_last		, 	// 不支持数据反压时last信号由mux给出
	
	output 	wire 	[AXI_DATA_WIDTH-1:0]	user_1_rd_data			,
	output 	wire 							user_1_rd_data_valid	,
	input 	wire 							user_1_rd_data_ready	,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		user_1_rd_id			,	// 不支持数据反压时id信号由mux给出
	inout 	wire 							user_1_rd_data_last		,	// 不支持数据反压时last信号由mux给出
	
	output 	wire 	[AXI_DATA_WIDTH-1:0]	arbitor_wr_data			,
	output 	wire 							arbitor_wr_data_valid	,
	input 	wire 							arbitor_wr_data_ready	,
	output 	wire [DDR_DATA_MASK_WIDTH-1:0]	arbitor_wstrb			,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		arbitor_wr_id			, 	// 不支持数据反压时id信号由arbitor给出
	inout	wire 							arbitor_wr_data_last	, 	// 不支持数据反压时last信号由arbitor给出
	
	input 	wire 	[AXI_DATA_WIDTH-1:0]	arbitor_rd_data			,
	input 	wire 							arbitor_rd_data_valid	,
	output 	wire 							arbitor_rd_data_ready	,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		arbitor_rd_id			,	// 不支持数据反压时id信号由arbitor给出
	inout	wire 							arbitor_rd_data_last		// 不支持数据反压时last信号由arbitor给出
);

	generate
		if (DATA_BACKPRESSURE_EN == 1'b0) begin : DATA_BACKPRESSURE_DISABLED
			// ----------------------------------------------------------------
			// 无数据反压版本：
			// 1. 固定优先级：user_0 > user_1
			// 2. 先地址握手，后打开数据通道
			// 3. 写通道 last 由本模块根据 aw_len 生成
			// 4. 读通道 last 由 arbitor 侧直接返回，本模块只做路由
			// 5. arbitor 地址ID统一冒用 ARBITER_CLIENT_ID，返回 user 侧时恢复锁存的真实ID
			// ----------------------------------------------------------------
			
			localparam [1:0] WR_IDLE      = 2'b00;
			localparam [1:0] WR_ADDR_SEND = 2'b01;
			localparam [1:0] WR_DATA_SEND = 2'b10;
			
			localparam [1:0] RD_IDLE      = 2'b00;
			localparam [1:0] RD_ADDR_SEND = 2'b01;
			localparam [1:0] RD_DATA_RECV = 2'b10;
			
			reg [1:0] wr_state;
			reg [1:0] rd_state;
			
			reg       wr_sel_user;  // 0:user_0  1:user_1
			reg       rd_sel_user;  // 0:user_0  1:user_1
			
			reg [AXI_ADDR_WIDTH-1:0] wr_addr_reg;
			reg [AXI_LEN_WIDTH-1:0]  wr_len_reg;
			reg [AXI_ID_WIDTH-1:0]   wr_real_id_reg;
			reg [AXI_LEN_WIDTH-1:0]  wr_cnt;
			
			reg [AXI_ADDR_WIDTH-1:0] rd_addr_reg;
			reg [AXI_LEN_WIDTH-1:0]  rd_len_reg;
			reg [AXI_ID_WIDTH-1:0]   rd_real_id_reg;
			
			reg [7:0] wr_timeout_cnt;
			reg [7:0] rd_timeout_cnt;
			reg       wr_timeout_flag;
			reg       rd_timeout_flag;
			
			wire user_0_aw_hs;
			wire user_1_aw_hs;
			wire user_0_ar_hs;
			wire user_1_ar_hs;
			wire arb_aw_hs;
			wire arb_ar_hs;
			wire user_0_w_hs;
			wire user_1_w_hs;
			wire arb_r_hs_user0;
			wire arb_r_hs_user1;
			
			assign user_0_aw_hs = user_0_awaddr_valid && user_0_awaddr_ready;
			assign user_1_aw_hs = user_1_awaddr_valid && user_1_awaddr_ready;
			assign user_0_ar_hs = user_0_araddr_valid && user_0_araddr_ready;
			assign user_1_ar_hs = user_1_araddr_valid && user_1_araddr_ready;
			assign arb_aw_hs    = arbitor_awaddr_valid && arbitor_awaddr_ready;
			assign arb_ar_hs    = arbitor_araddr_valid && arbitor_araddr_ready;
			assign user_0_w_hs  = user_0_wr_data_valid && user_0_wr_data_ready;
			assign user_1_w_hs  = user_1_wr_data_valid && user_1_wr_data_ready;
			
			assign arb_r_hs_user0 = arbitor_rd_data_valid && arbitor_rd_data_ready && (rd_sel_user == 1'b0);
			assign arb_r_hs_user1 = arbitor_rd_data_valid && arbitor_rd_data_ready && (rd_sel_user == 1'b1);
			
			// -------------------- 写通道：主状态机 --------------------
			always @(posedge axi_clk or negedge rst_n) begin
				if(!rst_n) begin
					wr_state       <= WR_IDLE;
					wr_sel_user    <= 1'b0;
					wr_addr_reg    <= {AXI_ADDR_WIDTH{1'b0}};
					wr_len_reg     <= {AXI_LEN_WIDTH{1'b0}};
					wr_real_id_reg <= {AXI_ID_WIDTH{1'b0}};
					wr_cnt         <= {AXI_LEN_WIDTH{1'b0}};
				end
				else begin
					case(wr_state)
						WR_IDLE: begin
							wr_cnt <= {AXI_LEN_WIDTH{1'b0}};
							// 固定优先级 user_0 > user_1
							if(user_0_aw_hs) begin
								wr_sel_user    <= 1'b0;
								wr_addr_reg    <= user_0_awaddr;
								wr_len_reg     <= user_0_aw_len;
								wr_real_id_reg <= user_0_aw_id;
								wr_state       <= WR_ADDR_SEND;
							end
							else if(user_1_aw_hs) begin
								wr_sel_user    <= 1'b1;
								wr_addr_reg    <= user_1_awaddr;
								wr_len_reg     <= user_1_aw_len;
								wr_real_id_reg <= user_1_aw_id;
								wr_state       <= WR_ADDR_SEND;
							end
						end
						
						WR_ADDR_SEND: begin
							if(arb_aw_hs) begin
								wr_cnt   <= {AXI_LEN_WIDTH{1'b0}};
								wr_state <= WR_DATA_SEND;
							end
						end
						
						WR_DATA_SEND: begin
							if((wr_sel_user == 1'b0) && user_0_w_hs) begin
								if(wr_cnt == wr_len_reg) begin
									wr_cnt   <= {AXI_LEN_WIDTH{1'b0}};
									wr_state <= WR_IDLE;
								end
								else begin
									wr_cnt <= wr_cnt + 1'b1;
								end
							end
							else if((wr_sel_user == 1'b1) && user_1_w_hs) begin
								if(wr_cnt == wr_len_reg) begin
									wr_cnt   <= {AXI_LEN_WIDTH{1'b0}};
									wr_state <= WR_IDLE;
								end
								else begin
									wr_cnt <= wr_cnt + 1'b1;
								end
							end
						end
						
						default: begin
							wr_state <= WR_IDLE;
						end
					endcase
				end
			end
			
			// -------------------- 读通道：主状态机 --------------------
			always @(posedge axi_clk or negedge rst_n) begin
				if(!rst_n) begin
					rd_state       <= RD_IDLE;
					rd_sel_user    <= 1'b0;
					rd_addr_reg    <= {AXI_ADDR_WIDTH{1'b0}};
					rd_len_reg     <= {AXI_LEN_WIDTH{1'b0}};
					rd_real_id_reg <= {AXI_ID_WIDTH{1'b0}};
				end
				else begin
					case(rd_state)
						RD_IDLE: begin
							// 固定优先级 user_0 > user_1
							if(user_0_ar_hs) begin
								rd_sel_user    <= 1'b0;
								rd_addr_reg    <= user_0_araddr;
								rd_len_reg     <= user_0_ar_len;
								rd_real_id_reg <= user_0_ar_id;
								rd_state       <= RD_ADDR_SEND;
							end
							else if(user_1_ar_hs) begin
								rd_sel_user    <= 1'b1;
								rd_addr_reg    <= user_1_araddr;
								rd_len_reg     <= user_1_ar_len;
								rd_real_id_reg <= user_1_ar_id;
								rd_state       <= RD_ADDR_SEND;
							end
						end
						
						RD_ADDR_SEND: begin
							if(arb_ar_hs) begin
								rd_state <= RD_DATA_RECV;
							end
						end
						
						RD_DATA_RECV: begin
							if(arbitor_rd_data_valid && arbitor_rd_data_ready && arbitor_rd_data_last) begin
								rd_state <= RD_IDLE;
							end
						end
						
						default: begin
							rd_state <= RD_IDLE;
						end
					endcase
				end
			end
			
			// -------------------- 写地址 ready --------------------
			always @(*) begin
				user_0_awaddr_ready = 1'b0;
				user_1_awaddr_ready = 1'b0;
				
				if(wr_state == WR_IDLE) begin
					if(user_0_awaddr_valid) begin
						user_0_awaddr_ready = 1'b1;
					end
					else if(user_1_awaddr_valid) begin
						user_1_awaddr_ready = 1'b1;
					end
				end
			end
			
			// -------------------- 读地址 ready --------------------
			always @(*) begin
				user_0_araddr_ready = 1'b0;
				user_1_araddr_ready = 1'b0;
				
				if(rd_state == RD_IDLE) begin
					if(user_0_araddr_valid) begin
						user_0_araddr_ready = 1'b1;
					end
					else if(user_1_araddr_valid) begin
						user_1_araddr_ready = 1'b1;
					end
				end
			end
			
			// -------------------- 写数据 ready --------------------
			always @(*) begin
				user_0_wr_data_ready = 1'b0;
				user_1_wr_data_ready = 1'b0;
				
				if(wr_state == WR_DATA_SEND) begin
					if(wr_sel_user == 1'b0) begin
						user_0_wr_data_ready = arbitor_wr_data_ready;
					end
					else begin
						user_1_wr_data_ready = arbitor_wr_data_ready;
					end
				end
			end
			
			// -------------------- 发送到 arbitor 的地址通道 --------------------
			assign arbitor_awaddr       = wr_addr_reg;
			assign arbitor_aw_len       = wr_len_reg;
			assign arbitor_aw_id        = ARBITER_CLIENT_ID;
			assign arbitor_awaddr_valid = (wr_state == WR_ADDR_SEND);
			
			assign arbitor_araddr       = rd_addr_reg;
			assign arbitor_ar_len       = rd_len_reg;
			assign arbitor_ar_id        = ARBITER_CLIENT_ID;
			assign arbitor_araddr_valid = (rd_state == RD_ADDR_SEND);
			
			// -------------------- 发送到 arbitor 的写数据通道 --------------------
			assign arbitor_wr_data = (wr_sel_user == 1'b0) ? user_0_wr_data : user_1_wr_data;
			assign arbitor_wstrb   = (wr_sel_user == 1'b0) ? user_0_wstrb   : user_1_wstrb;
			assign arbitor_wr_data_valid =
					(wr_state == WR_DATA_SEND) &&
					((wr_sel_user == 1'b0) ? user_0_wr_data_valid : user_1_wr_data_valid);
			
			// -------------------- 从 arbitor 返回的读数据通道 --------------------
			assign arbitor_rd_data_ready =
					(rd_state == RD_DATA_RECV) &&
					((rd_sel_user == 1'b0) ? user_0_rd_data_ready : user_1_rd_data_ready);
			
			assign user_0_rd_data       = arbitor_rd_data;
			assign user_1_rd_data       = arbitor_rd_data;
			assign user_0_rd_data_valid = (rd_state == RD_DATA_RECV) && (rd_sel_user == 1'b0) && arbitor_rd_data_valid;
			assign user_1_rd_data_valid = (rd_state == RD_DATA_RECV) && (rd_sel_user == 1'b1) && arbitor_rd_data_valid;
			
			// -------------------- user 侧 inout 信号驱动 --------------------
			// 写通道：connector 生成给 user 的 id/last
			assign user_0_wr_id        = (wr_state == WR_DATA_SEND && wr_sel_user == 1'b0) ? wr_real_id_reg : {AXI_ID_WIDTH{1'bz}};
			assign user_1_wr_id        = (wr_state == WR_DATA_SEND && wr_sel_user == 1'b1) ? wr_real_id_reg : {AXI_ID_WIDTH{1'bz}};
			assign user_0_wr_data_last = (wr_state == WR_DATA_SEND && wr_sel_user == 1'b0 && user_0_wr_data_ready && (wr_cnt == wr_len_reg)) ? 1'b1 : 1'bz;
			assign user_1_wr_data_last = (wr_state == WR_DATA_SEND && wr_sel_user == 1'b1 && user_1_wr_data_ready && (wr_cnt == wr_len_reg)) ? 1'b1 : 1'bz;
			
			// 读通道：connector 把 arbitor 返回的 id/last 恢复给被授权 user
			assign user_0_rd_id        = (rd_state == RD_DATA_RECV && rd_sel_user == 1'b0) ? rd_real_id_reg      : {AXI_ID_WIDTH{1'bz}};
			assign user_1_rd_id        = (rd_state == RD_DATA_RECV && rd_sel_user == 1'b1) ? rd_real_id_reg      : {AXI_ID_WIDTH{1'bz}};
			assign user_0_rd_data_last = (rd_state == RD_DATA_RECV && rd_sel_user == 1'b0) ? arbitor_rd_data_last : 1'bz;
			assign user_1_rd_data_last = (rd_state == RD_DATA_RECV && rd_sel_user == 1'b1) ? arbitor_rd_data_last : 1'bz;
			
			// arbitor 侧这些 inout 在当前“无反压直通”实现中不主动驱动
			assign arbitor_wr_id        = {AXI_ID_WIDTH{1'bz}};
			assign arbitor_wr_data_last = 1'bz;
			assign arbitor_rd_id        = {AXI_ID_WIDTH{1'bz}};
			assign arbitor_rd_data_last = 1'bz;
			
			// -------------------- 超时计数 --------------------
			always @(posedge axi_clk or negedge rst_n) begin
				if(!rst_n) begin
					wr_timeout_cnt  <= 8'd0;
					wr_timeout_flag <= 1'b0;
				end
				else begin
					if(wr_state == WR_IDLE) begin
						wr_timeout_cnt  <= 8'd0;
						wr_timeout_flag <= 1'b0;
					end
					else if(
						(wr_state == WR_ADDR_SEND && arb_aw_hs) ||
						(wr_state == WR_DATA_SEND && ((wr_sel_user == 1'b0 && user_0_w_hs) || (wr_sel_user == 1'b1 && user_1_w_hs)))
					) begin
						wr_timeout_cnt  <= 8'd0;
						wr_timeout_flag <= 1'b0;
					end
					else begin
						if(wr_timeout_cnt == 8'hff) begin
							wr_timeout_cnt  <= 8'hff;
							wr_timeout_flag <= 1'b1;
						end
						else begin
							wr_timeout_cnt  <= wr_timeout_cnt + 1'b1;
							wr_timeout_flag <= 1'b0;
						end
					end
				end
			end
			
			always @(posedge axi_clk or negedge rst_n) begin
				if(!rst_n) begin
					rd_timeout_cnt  <= 8'd0;
					rd_timeout_flag <= 1'b0;
				end
				else begin
					if(rd_state == RD_IDLE) begin
						rd_timeout_cnt  <= 8'd0;
						rd_timeout_flag <= 1'b0;
					end
					else if(
						(rd_state == RD_ADDR_SEND && arb_ar_hs) ||
						(rd_state == RD_DATA_RECV && ((rd_sel_user == 1'b0 && arb_r_hs_user0) || (rd_sel_user == 1'b1 && arb_r_hs_user1)))
					) begin
						rd_timeout_cnt  <= 8'd0;
						rd_timeout_flag <= 1'b0;
					end
					else begin
						if(rd_timeout_cnt == 8'hff) begin
							rd_timeout_cnt  <= 8'hff;
							rd_timeout_flag <= 1'b1;
						end
						else begin
							rd_timeout_cnt  <= rd_timeout_cnt + 1'b1;
							rd_timeout_flag <= 1'b0;
						end
					end
				end
			end
			
			// -------------------- grant 指示 --------------------
			assign grant_busy[3] = (wr_state == WR_DATA_SEND) && (wr_sel_user == 1'b0);
			assign grant_busy[2] = (wr_state == WR_DATA_SEND) && (wr_sel_user == 1'b1);
			assign grant_busy[1] = (rd_state == RD_DATA_RECV) && (rd_sel_user == 1'b0);
			assign grant_busy[0] = (rd_state == RD_DATA_RECV) && (rd_sel_user == 1'b1);
			
			assign grant_overtime[3] = (wr_sel_user == 1'b0) && wr_timeout_flag;
			assign grant_overtime[2] = (wr_sel_user == 1'b1) && wr_timeout_flag;
			assign grant_overtime[1] = (rd_sel_user == 1'b0) && rd_timeout_flag;
			assign grant_overtime[0] = (rd_sel_user == 1'b1) && rd_timeout_flag;
			
		end
		else begin : DATA_BACKPRESSURE_ENABLED
			// in progress：当前先给安全缺省，避免悬空
			always @(*) begin
				user_0_araddr_ready  = 1'b0;
				user_0_awaddr_ready  = 1'b0;
				user_1_araddr_ready  = 1'b0;
				user_1_awaddr_ready  = 1'b0;
				user_0_wr_data_ready = 1'b0;
				user_1_wr_data_ready = 1'b0;
			end
			
			assign arbitor_araddr       = {AXI_ADDR_WIDTH{1'b0}};
			assign arbitor_ar_id        = {AXI_ID_WIDTH{1'b0}};
			assign arbitor_ar_len       = {AXI_LEN_WIDTH{1'b0}};
			assign arbitor_araddr_valid = 1'b0;
			
			assign arbitor_awaddr       = {AXI_ADDR_WIDTH{1'b0}};
			assign arbitor_aw_id        = {AXI_ID_WIDTH{1'b0}};
			assign arbitor_aw_len       = {AXI_LEN_WIDTH{1'b0}};
			assign arbitor_awaddr_valid = 1'b0;
			
			assign arbitor_wr_data       = {AXI_DATA_WIDTH{1'b0}};
			assign arbitor_wr_data_valid = 1'b0;
			assign arbitor_wstrb         = {DDR_DATA_MASK_WIDTH{1'b0}};
			
			assign user_0_rd_data       = {AXI_DATA_WIDTH{1'b0}};
			assign user_1_rd_data       = {AXI_DATA_WIDTH{1'b0}};
			assign user_0_rd_data_valid = 1'b0;
			assign user_1_rd_data_valid = 1'b0;
			assign arbitor_rd_data_ready = 1'b0;
			
			assign user_0_wr_id         = {AXI_ID_WIDTH{1'bz}};
			assign user_0_wr_data_last  = 1'bz;
			assign user_0_rd_id         = {AXI_ID_WIDTH{1'bz}};
			assign user_0_rd_data_last  = 1'bz;
			assign user_1_wr_id         = {AXI_ID_WIDTH{1'bz}};
			assign user_1_wr_data_last  = 1'bz;
			assign user_1_rd_id         = {AXI_ID_WIDTH{1'bz}};
			assign user_1_rd_data_last  = 1'bz;
			assign arbitor_wr_id        = {AXI_ID_WIDTH{1'bz}};
			assign arbitor_wr_data_last = 1'bz;
			assign arbitor_rd_id        = {AXI_ID_WIDTH{1'bz}};
			assign arbitor_rd_data_last = 1'bz;
			
			assign grant_busy      = 4'b0000;
			assign grant_overtime  = 4'b0000;
		end
	endgenerate

endmodule