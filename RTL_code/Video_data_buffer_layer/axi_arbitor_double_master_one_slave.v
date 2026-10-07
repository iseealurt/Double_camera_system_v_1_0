//注意，此为紫光同创FPGA DDR3控制器的私有AXI协议版本
module axi_arbitor_double_master_one_slave#(
	parameter		AXI_ADDR_WIDTH			=	28					,
	parameter 		AXI_DATA_WIDTH			=	256					,
	parameter 		AXI_ID_WIDTH			=	4					,
	parameter		AXI_LEN_WIDTH			=	4					,
	parameter 		DDR_DATA_MASK_WIDTH		=	32					,
	parameter 		DATA_BACKPRESSURE_EN	=	1'b1				,
	parameter 		CLIENT_0_AXI_ID			=	4'b0001				,
	parameter 		CLIENT_1_AXI_ID			=	4'b0010				,
	parameter 		ROLL_POLING_MAX_INTERVAL= 	4'd1				
)(
	input 	wire 							clk						,
	input 	wire 							rst_n					,
	input 	wire 	[1:0]					arbit_vector			,	
	input 	wire 							arb_vec_cfg_valid		,
	output 	reg 							arb_vec_cfg_ready		,
	
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
	parameter 	STRAIGHT_IN		=	2'b00	,
				CLIENT_0_FIRST	=	2'b01	,
				CLIENT_1_FIRST	=	2'b10	,
				ROLL_POLING		=	2'b11	;
	
	reg 	[1:0]		arbit_vector_reg;
	
	always@(posedge clk) begin
		if(!rst_n) begin
			arb_vec_cfg_ready <= 1'b0;
			arbit_vector_reg <= ROLL_POLING;
		end
		else begin
			if(arb_vec_cfg_valid && arb_vec_cfg_ready) begin
				arb_vec_cfg_ready <= 1'b0;
				arbit_vector_reg <= arbit_vector;
			end
			else if(arb_vec_cfg_valid 
					&& !arb_vec_cfg_ready 
					) begin
				arb_vec_cfg_ready <= 1'b1;
			end
			else begin
				arb_vec_cfg_ready <= arb_vec_cfg_ready;
				arbit_vector_reg <= arbit_vector_reg;
			end
		end	
	end
	
	// ---------------------------------------- in progress ---------------------------------------- //
	generate
		if (DATA_BACKPRESSURE_EN == 1'b1) begin : BACKPRESSURE_ENABLE_MODE
		// ---------------------------------------- in progress ---------------------------------------- //
		
		// 先完成不支持数据反压的仲裁生成
		end
		else begin: BACKPRESSURE_DISABLE_MODE
			//分为上下两层
			//上层负责主机的轮询仲裁，下层负责从机的数据读写
			//工作流程如下：
			/*
				上层（写通道）：
				1. 有主机发起请求时，检查数据FIFO是否将要写满，若将要写满，则要求主机等待
				2. 若未将要写满，则检查当前主机是否为待轮询对象，如果不是，不进行授权
				3. 若是待轮询对象，则先开放地址通道，等待握手成功后开放数据通道，等待数据完成写入后返回闲置
				
				下层（写通道）：
				1. 检查地址FIFO内是否有新地址传入，如果没有，则等待
				2. 如果有待发起的地址，则检查数据FIFO内数据量是否足够，如果不足，则等待
				3. 如果足够，则对从机的写通道发起请求，先发起写地址请求，握手成功后返回从机的读取请求（ready信号）
				4. 如果请求完成（last），返回闲置状态
				
				上层（读通道）：
				1. 有主机发起请求时，检查地址FIFO是否即将写满，若即将写满，则要求主机等待
				2. 若未写满，则检查当前主机是否为待轮询对象，如果不是，不进行授权
				3. 若是待轮询对象，则开放地址通道，握手成功后继续下一次授权
				
				下层（读通道）：
				1. 检查地址FIFO内是否有新地址传入，如果没有，则等待
				2. 如果有待发起的地址，则将其发起
				3. 不断发起请求直至地址FIFO为空
				
				注意：
					数据完整性检查和大深度FIFO是必要的，由于刷新机制问题，DDR3控制器的最大传输延迟非常大，
				因此存在一个致命问题：如果DDR在读取/写入数据时进入了刷新状态，
				那么从地址通道响应到数据完整输出中间会有巨大的延迟（将近200个时钟周期），
				如果FIFO深度不足，很有可能造成FIFO的严重溢出
			*/
			// ---------------------------------------- 写通道FIFO行为定义 ----------------------------------------
			parameter 	WR_ADDR_FIIO_WIDTH	=	AXI_ADDR_WIDTH + AXI_ID_WIDTH + AXI_LEN_WIDTH;
			
			
			wire 								wr_addr_fifo_almost_full_flag;
			
			wire 								wr_addr_fifo_empty;
			wire 								wr_addr_fifo_wr_en; 
			wire 								wr_addr_fifo_rd_en; 
			
			reg   [WR_ADDR_FIIO_WIDTH -1 : 0]	wr_addr_fifo_din;
			wire   [WR_ADDR_FIIO_WIDTH -1 : 0]	wr_addr_fifo_dout;
			
			always@(*) begin	
				wr_addr_fifo_din = 'd0;
				if(master_0_awaddr_valid) begin
					wr_addr_fifo_din = {master_0_awaddr,master_0_aw_id,master_0_aw_len};
				end
				else if(master_1_awaddr_valid) begin
					wr_addr_fifo_din = {master_1_awaddr,master_1_aw_id,master_1_aw_len};
				end
			end
			
			assign wr_addr_fifo_wr_en =		(master_0_awaddr_valid && master_0_awaddr_ready)
										||	(master_1_awaddr_valid && master_1_awaddr_ready);
			
			assign wr_addr_fifo_rd_en = 	slave_awaddr_valid && slave_awaddr_ready;
			
			wire 	[5:0]						wr_data_rd_water_level;							
			wire 								wr_data_fifo_almost_full_flag;
			wire 								wr_data_fifo_wr_en; //也是掩码FIFO的写使能
			wire 								wr_data_fifo_rd_en; //也是掩码FIFO的读使能
			reg 	[AXI_DATA_WIDTH -1 : 0]		wr_data_fifo_din;
			reg 	[DDR_DATA_MASK_WIDTH-1:0]	wr_mask_fifo_din;
			wire 	[AXI_DATA_WIDTH -1 : 0]		wr_data_fifo_dout;
			wire 	[DDR_DATA_MASK_WIDTH-1:0]	wr_mask_fifo_dout;
						
			assign wr_data_fifo_wr_en = master_0_wr_data_ready || master_1_wr_data_ready;
			
			assign wr_data_fifo_rd_en = slave_wr_data_ready;
			
			// ---------------------------------------- 写通道上层 ----------------------------------------
			reg 	[7:0]	wr_overtime_cnt;	//最多运行256个周期的突发超时
			reg 			wr_overtime_flag;
			
			reg 			wr_wait_timeout_flag;
			reg 	[3:0]	wr_wait_timeout_cnt;
			reg 	[3:0]	wr_client_to_grant;	//轮询对象指示
			reg 	[3:0]	wr_data_client;	//数据处理对象指示
			reg 	[1:0]	wr_data_busy_flag; //数据通道忙碌指示
			
			always@(posedge clk) begin
				if(!rst_n) begin
					wr_client_to_grant <= CLIENT_0_AXI_ID;
				end
				else begin
					if(arbit_vector_reg == ROLL_POLING) begin
						if(wr_overtime_flag) begin
							if(wr_data_client == CLIENT_0_AXI_ID) begin
								wr_client_to_grant <= CLIENT_1_AXI_ID;
							end
							else begin	
								wr_client_to_grant <= CLIENT_0_AXI_ID;
							end
						end
						else if(wr_wait_timeout_flag) begin
							if(wr_client_to_grant == CLIENT_0_AXI_ID) begin
								wr_client_to_grant <= CLIENT_1_AXI_ID;
							end
							else begin	
								wr_client_to_grant <= CLIENT_0_AXI_ID;
							end
						end
						else if(master_0_awaddr_valid && master_0_awaddr_ready) begin
							wr_client_to_grant <= CLIENT_1_AXI_ID;
						end
						else if(master_1_awaddr_valid && master_1_awaddr_ready) begin
							wr_client_to_grant <= CLIENT_0_AXI_ID;
						end
					//其他条件下保持
					end
					else if(arbit_vector_reg == STRAIGHT_IN) begin
		// ---------------------------------------- in progress ----------------------------------------
					end
					else if(arbit_vector_reg == CLIENT_0_FIRST) begin
		// ---------------------------------------- in progress ----------------------------------------
					end
					else begin
		// ---------------------------------------- in progress ----------------------------------------			
					end	
				end
			end
			
			always@(posedge clk) begin
				if(!rst_n) begin
					wr_data_client <= 4'd0;
					wr_data_busy_flag <= 2'b00;
				end
				else begin			
					if(master_0_wr_data_last && wr_data_busy_flag[0]) begin
						wr_data_client <= 4'd0;
						wr_data_busy_flag <= 2'b00;
					end
					else if(master_0_awaddr_valid && master_0_awaddr_ready && !wr_data_busy_flag[1]) begin
						wr_data_client <= wr_client_to_grant;
						wr_data_busy_flag <= 2'b01;
					end
					
					if(master_1_wr_data_last && wr_data_busy_flag[1]) begin
						wr_data_client <= 4'd0;
						wr_data_busy_flag <= 2'b00;
					end
					else if(master_1_awaddr_valid && master_1_awaddr_ready && !wr_data_busy_flag[0]) begin
						wr_data_client <= wr_client_to_grant;
						wr_data_busy_flag <= 2'b10;
					end
					//其他条件下保持
				end
			end
			
			parameter 		WR_TOP_IDLE 		=	4'b0001		,
							WR_TOP_ADDR_START	=	4'b0010		,
							WR_TOP_ADDR_END		=	4'b0100		,
							WR_TOP_DATA_END		=	4'b1000		;
						
			reg 	[3:0]						wr_top_cur_state;
			reg 	[3:0]						wr_top_nex_state;
			
			always@(*) begin
				wr_top_nex_state = wr_top_cur_state;	//reset
				case(wr_top_cur_state) 
					WR_TOP_IDLE			:begin 
						if(master_0_awaddr_valid 
							&& wr_client_to_grant == CLIENT_0_AXI_ID 
							&& !wr_data_fifo_almost_full_flag 
							&& !wr_addr_fifo_almost_full_flag) begin
							wr_top_nex_state = WR_TOP_ADDR_START;
						end
						else if(master_1_awaddr_valid 
							&& wr_client_to_grant == CLIENT_1_AXI_ID
							&& !wr_data_fifo_almost_full_flag 
							&& !wr_addr_fifo_almost_full_flag) begin
							wr_top_nex_state = WR_TOP_ADDR_START;
						end
					end
					WR_TOP_ADDR_START	:begin 
						if(wr_overtime_flag) begin
							wr_top_nex_state = WR_TOP_IDLE;
						end
						else if(master_0_awaddr_valid && master_0_awaddr_ready && !wr_data_busy_flag[1]) begin
							wr_top_nex_state = WR_TOP_ADDR_END;
						end
						else if(master_1_awaddr_valid && master_1_awaddr_ready && !wr_data_busy_flag[0]) begin
							wr_top_nex_state = WR_TOP_ADDR_END;
						end
					end
					WR_TOP_ADDR_END		:begin 
						if(wr_overtime_flag) begin
							wr_top_nex_state = WR_TOP_IDLE;
						end
						else if(master_0_wr_data_last && wr_data_busy_flag[0]) begin
							wr_top_nex_state = WR_TOP_DATA_END;
						end
						else if(master_1_wr_data_last && wr_data_busy_flag[1]) begin
							wr_top_nex_state = WR_TOP_DATA_END;
						end
					end
					WR_TOP_DATA_END		:begin 
						if(master_0_awaddr_valid || master_1_awaddr_valid) begin
							wr_top_nex_state = WR_TOP_IDLE;
						end
					end
				endcase
			end
			
			always@(posedge clk) begin
				if(!rst_n) begin
					wr_top_cur_state <= WR_TOP_IDLE;
				end
				else begin
					wr_top_cur_state <= wr_top_nex_state; 
				end
			end
			
			always@(posedge clk) begin
				if(!rst_n) begin
					master_0_awaddr_ready <= 1'b0;
					master_1_awaddr_ready <= 1'b0;
				end
				else begin
					if(wr_top_cur_state == WR_TOP_ADDR_START) begin
						if(wr_client_to_grant == CLIENT_0_AXI_ID) begin	
							if(master_0_awaddr_valid && master_0_awaddr_ready && !wr_data_busy_flag[1]) begin
								master_0_awaddr_ready <= 1'b0;
								master_1_awaddr_ready <= 1'b0;
							end
							else begin
								master_0_awaddr_ready <= 1'b1;
								master_1_awaddr_ready <= 1'b0;
							end
						end
						else if(wr_client_to_grant == CLIENT_1_AXI_ID) begin
							if(master_1_awaddr_valid && master_1_awaddr_ready && !wr_data_busy_flag[0]) begin
								master_0_awaddr_ready <= 1'b0;
								master_1_awaddr_ready <= 1'b0;
							end
							else begin
								master_0_awaddr_ready <= 1'b0;
								master_1_awaddr_ready <= 1'b1;
							end
						end
						else begin
							master_0_awaddr_ready <= 1'b0;
							master_1_awaddr_ready <= 1'b0;
						end
					end
					else begin
						master_0_awaddr_ready <= 1'b0;
						master_1_awaddr_ready <= 1'b0;
					end
				end
			end
			
			reg 	[AXI_LEN_WIDTH-1:0]		wr_d_val;
			
			always@(posedge clk) begin
				if(!rst_n) begin
					wr_d_val <= 'd0;
				end
				else begin
					if(wr_top_cur_state == WR_TOP_ADDR_START) begin
						if(master_0_awaddr_valid && master_0_awaddr_ready && !wr_data_busy_flag[1]) begin
							wr_d_val <= master_0_aw_len;
						end
						else if(master_1_awaddr_valid && master_1_awaddr_ready && !wr_data_busy_flag[0]) begin
							wr_d_val <= master_1_aw_len;
						end
					end
				end
			end
			
			reg 	[AXI_LEN_WIDTH-1:0]		wr_d_cnt;
			
			always@(posedge clk) begin
				if(!rst_n) begin
					wr_d_cnt <= 'd0;
					master_0_wr_data_ready <= 1'b0;
					master_1_wr_data_ready <= 1'b0;
				end
				else begin
					if(master_0_wr_data_ready || master_1_wr_data_ready) begin
						wr_d_cnt <= wr_d_cnt == wr_d_val ? 'd0 : wr_d_cnt + 1'b1;
					end
					else begin
						wr_d_cnt <= 'd0;
					end
					
					if(wr_top_cur_state == WR_TOP_ADDR_END) begin
						if(wr_data_client == CLIENT_0_AXI_ID) begin
							if(wr_d_cnt == wr_d_val) begin
								master_0_wr_data_ready <= 1'b0;
							end
							else begin
								master_0_wr_data_ready <= 1'b1;
							end
						end
						else if(wr_data_client == CLIENT_1_AXI_ID) begin
							if(wr_d_cnt == wr_d_val) begin
								master_1_wr_data_ready <= 1'b0;
							end
							else begin
								master_1_wr_data_ready <= 1'b1;
							end
						end
					end
					else begin
						master_0_wr_data_ready <= 1'b0;
						master_1_wr_data_ready <= 1'b0;
					end
				end
			end
			
			assign master_0_wr_data_last = wr_data_client == CLIENT_0_AXI_ID && wr_d_cnt == wr_d_val && master_0_wr_data_ready;
			assign master_1_wr_data_last = wr_data_client == CLIENT_1_AXI_ID && wr_d_cnt == wr_d_val && master_1_wr_data_ready;
			assign master_0_wr_id = wr_data_client;
			assign master_1_wr_id = wr_data_client;
			
			//超时机制行为定义
			always@(posedge clk) begin
				if(!rst_n) begin
					wr_overtime_cnt <= 'd0;
					wr_overtime_flag <= 1'b0;
				end
				else begin
					if (master_0_awaddr_valid && master_0_awaddr_ready) begin
						wr_overtime_cnt <= 'd0;
						wr_overtime_flag <= 1'b0;
					end
					else if(master_1_awaddr_valid && master_1_awaddr_ready) begin
						wr_overtime_cnt <= 'd0;
						wr_overtime_flag <= 1'b0;
					end
					else if(master_0_wr_data_ready || master_1_wr_data_ready) begin
						wr_overtime_cnt <= 'd0;
						wr_overtime_flag <= 1'b0;
					end
					else if(wr_top_cur_state != WR_TOP_IDLE && wr_top_cur_state != WR_TOP_DATA_END) begin
						wr_overtime_cnt <= wr_overtime_cnt == 8'hff ? 8'hff : wr_overtime_cnt + 1'b1;
						wr_overtime_flag <= wr_overtime_cnt == 8'hff ? 1'b1 : 1'b0;
					end
					else begin
						wr_overtime_cnt <= 'd0;
						wr_overtime_flag <= 1'b0;
					end
				end
			end
			
			always@(posedge clk) begin
				if(!rst_n) begin
					wr_wait_timeout_cnt <= 'd0;
					wr_wait_timeout_flag <= 1'b0;
				end
				else begin
					if(wr_top_cur_state == WR_TOP_IDLE) begin
						if(master_0_awaddr_valid && master_0_awaddr_ready) begin
							wr_wait_timeout_cnt <= 'd0;
							wr_wait_timeout_flag <= 1'b0;
						end
						else if(master_1_awaddr_valid && master_1_awaddr_ready)begin
							wr_wait_timeout_cnt <= 'd0;
							wr_wait_timeout_flag <= 1'b0;
						end
						else if(wr_client_to_grant == CLIENT_0_AXI_ID && !master_0_awaddr_valid && master_1_awaddr_valid) begin
							wr_wait_timeout_cnt <= wr_wait_timeout_cnt == ROLL_POLING_MAX_INTERVAL ? 'd0 : wr_wait_timeout_cnt + 1'b1;
							wr_wait_timeout_flag <= wr_wait_timeout_cnt == ROLL_POLING_MAX_INTERVAL ? 1'b1 : 1'b0;
						end
						else if(wr_client_to_grant == CLIENT_1_AXI_ID && !master_1_awaddr_valid && master_0_awaddr_valid) begin
							wr_wait_timeout_cnt <= wr_wait_timeout_cnt == ROLL_POLING_MAX_INTERVAL ? 'd0 : wr_wait_timeout_cnt + 1'b1;
							wr_wait_timeout_flag <= wr_wait_timeout_cnt == ROLL_POLING_MAX_INTERVAL ? 1'b1 : 1'b0;
						end
						else begin
							wr_wait_timeout_cnt <= 'd0;
							wr_wait_timeout_flag <= 1'b0;
						end
					end
					else begin
						wr_wait_timeout_cnt <= 'd0;
						wr_wait_timeout_flag <= 1'b0;
					end
				end
			end
			// ---------------------------------------- 写通道FIFO 实例化 ----------------------------------------		
			always@(*) begin
				wr_data_fifo_din = 'd0;
				wr_mask_fifo_din = 'd0;
				if(wr_data_client == CLIENT_0_AXI_ID) begin
					wr_data_fifo_din = master_0_wr_data;
					wr_mask_fifo_din = master_0_wstrb;
				end
				else if(wr_data_client == CLIENT_1_AXI_ID) begin
					wr_data_fifo_din = master_1_wr_data;
					wr_mask_fifo_din = master_1_wstrb;
				end
			end
			
			arbitor_dfifo arbitor_wr_dfifo_inst (
				.clk			(clk							),	// input
				.rst			(!rst_n							),	// input
				.wr_en			(wr_data_fifo_wr_en				),	// input
				.wr_data		(wr_data_fifo_din				),	// input [255:0]
				.full			(								),	// output
				.wr_water_level	(								),	// output [5:0]
				.almost_full	(wr_data_fifo_almost_full_flag	),	// output
				.rd_en			(wr_data_fifo_rd_en				),	// input
				.rd_data		(wr_data_fifo_dout				),	// output [255:0]
				.empty			(								),	// output
				.rd_water_level	(wr_data_rd_water_level			),	// output [5:0]
				.almost_empty	(								)	// output
			);		
			arbitor_afifo arbitor_wr_afifo_inst (
				.clk			(clk							),	// input
				.rst			(!rst_n							),	// input
				.wr_en			(wr_addr_fifo_wr_en				),	// input
				.wr_data		(wr_addr_fifo_din				),	// input [39:0]
				.almost_full	(wr_addr_fifo_almost_full_flag	),	// output
				.rd_en			(wr_addr_fifo_rd_en				),	// input
				.rd_data		(wr_addr_fifo_dout				),	// output [39:0]
				.empty			(wr_addr_fifo_empty				),	// output
				.almost_empty	(								)	// output
			);
			arbitor_mask_fifo arbitor_wr_mask_fifo_inst (
				.clk			(clk							),	// input
				.rst			(!rst_n							),	// input
				.wr_en			(wr_data_fifo_wr_en				),	// input
				.wr_data		(wr_mask_fifo_din				),	// input [31:0]
				.full			(								),	// output
				.almost_full	(								),	// output
				.rd_en			(wr_data_fifo_rd_en				),	// input
				.rd_data		(wr_mask_fifo_dout				),	// output [31:0]
				.empty			(								),	// output
				.almost_empty	(								)	// output
			);
			
			// ---------------------------------------- 写通道下层 ----------------------------------------
			// 使用类似于FIFO的指针操作来处理写地址和写数据通道的异步问题：
			// 有符号4位数 wr_bottom_addr_ptr 每握手一次自增1，
			// 有符号4位数 wr_bottom_burst_ptr 在每次last信号拉高时自增 1
			// 将两值相减，取绝对值得到待处理突发次数 burst_val ，如果其为0，则返回闲置，
			// 如果burst_val 不为0，则检查数据FIFO水位是否足够，若足够则发起请求，否则等待
			//工作流程：
			//1. 检查地址FIFO是否不为空，不为空则进入2
			//2. 暂存地址FIFO内LEN信息，检查数据FIFO内数据量是否大于等于 wr_bottom_data_cnt + burst_len，满足进入3,否则进入4
			//3. 发起一次请求，并将wr_bottom_data_cnt加上burst_len,返回1
			//4. 等待，若abs_burst_val变为0，返回1
			reg 				[3:0]		wr_bottom_burst_cnt;
			reg 				[5:0]		wr_bottom_data_cnt;
			
			wire    trade_completed;
			wire    trade_full;

			assign trade_completed = wr_bottom_burst_cnt == 4'd0;
			assign trade_full = wr_bottom_burst_cnt == 4'd15;

			wire 	[3:0]		burst_val;
			reg 	[3:0]		burst_reg;
			reg 	[3:0]		burst_len_reg;

			// 然后用 "committed - consumed" 作为真实待处理量
					
			
			parameter		WR_BOTTOM_IDLE		= 4'b0001	,
							WR_BOTTOM_ADDR_RDY	= 4'b0010	,
							WR_BOTTOM_ADDR_END	= 4'b0100	,
							WR_BOTTOM_BUSY		= 4'b1000	;
							
			reg 	[3:0]	wr_bottom_cur_state;
			reg 	[3:0]	wr_bottom_nex_state;
			// 状态机转移逻辑有误			
			always@(*) begin
				wr_bottom_nex_state = wr_bottom_cur_state;
				case(wr_bottom_cur_state)
					WR_BOTTOM_IDLE		:begin 
						if(!wr_addr_fifo_empty && !trade_full) begin
							wr_bottom_nex_state = WR_BOTTOM_ADDR_RDY;
						end
					end
					WR_BOTTOM_ADDR_RDY	:begin 
						if(wr_data_rd_water_level >= burst_len_reg) begin
							wr_bottom_nex_state = WR_BOTTOM_ADDR_END;
						end
						else begin
							wr_bottom_nex_state = WR_BOTTOM_BUSY;
						end
					end	
					WR_BOTTOM_ADDR_END	:begin 
						if(slave_awaddr_valid && slave_awaddr_ready) begin
							wr_bottom_nex_state = WR_BOTTOM_BUSY;
						end
					end
					WR_BOTTOM_BUSY		:begin 
						if(trade_completed) begin
							wr_bottom_nex_state = WR_BOTTOM_IDLE;
						end
					end
					default				:begin
						wr_bottom_nex_state = WR_BOTTOM_IDLE;
					end
				endcase
			end
			
			always@(posedge clk) begin
				if(!rst_n) begin
					wr_bottom_cur_state <= WR_BOTTOM_IDLE;
				end
				else begin
					wr_bottom_cur_state <= wr_bottom_nex_state;
				end
			end
			
			always@(posedge clk) begin
				if(!rst_n) begin
					burst_len_reg <= 4'd0;
					wr_bottom_data_cnt <= 6'd0;
				end
				else begin
					if(wr_bottom_cur_state == WR_BOTTOM_IDLE && !wr_addr_fifo_empty) begin
						burst_len_reg <= wr_addr_fifo_dout[AXI_LEN_WIDTH -1:0];
					end
					
					if(wr_bottom_cur_state == WR_BOTTOM_BUSY) begin
						wr_bottom_data_cnt <= 6'd0;
					end
					else if(slave_awaddr_valid && slave_awaddr_ready) begin
						wr_bottom_data_cnt <= wr_bottom_data_cnt + burst_len_reg;
					end
				end
			end
			
			always@(posedge clk) begin
				if(!rst_n) begin
					wr_bottom_burst_cnt <= 0;
				end
				else begin
					if(slave_awaddr_valid && slave_awaddr_ready) begin
						wr_bottom_burst_cnt <= wr_bottom_burst_cnt == 4'b1111 ? wr_bottom_burst_cnt : wr_bottom_burst_cnt + 1'b1;
					end
					
					if(slave_wr_data_last) begin
						wr_bottom_burst_cnt <= wr_bottom_burst_cnt == 4'd0 ? wr_bottom_burst_cnt : wr_bottom_burst_cnt - 1'b1;
					end
				end
			end
			
			always@(posedge clk) begin
				if(!rst_n) begin
					slave_awaddr_valid <= 1'b0;
				end
				else begin
					if(slave_awaddr_valid && slave_awaddr_ready) begin
						slave_awaddr_valid <= 1'b0;
					end
					else if(wr_bottom_cur_state == WR_BOTTOM_ADDR_END && !wr_addr_fifo_empty) begin	
						slave_awaddr_valid <= 1'b1;
					end				
				end
			end
			
			assign slave_wr_data = wr_data_fifo_dout;
			assign slave_awaddr = wr_addr_fifo_dout[WR_ADDR_FIIO_WIDTH-1:AXI_ID_WIDTH + AXI_LEN_WIDTH];
			assign slave_wstrb  = wr_mask_fifo_dout; 
			assign slave_aw_id  = wr_addr_fifo_dout[AXI_ID_WIDTH + AXI_LEN_WIDTH-1:AXI_LEN_WIDTH];
			assign slave_aw_len = wr_addr_fifo_dout[AXI_LEN_WIDTH-1:0];
			assign slave_wr_data_last = 1'bz;
			assign slave_wr_id = 4'bzzzz;
			// ---------------------------------------- 读通道FIFO行为定义 ----------------------------------------
			parameter 	RD_ADDR_FIIO_WIDTH	=	AXI_ADDR_WIDTH + AXI_ID_WIDTH + AXI_LEN_WIDTH;
			
			
			wire 								rd_addr_fifo_almost_full_flag;
			
			wire 								rd_addr_fifo_empty;
			wire 								rd_addr_fifo_wr_en; 
			wire 								rd_addr_fifo_rd_en; 
			
			reg   [RD_ADDR_FIIO_WIDTH -1 : 0]	rd_addr_fifo_din;
			wire   [RD_ADDR_FIIO_WIDTH -1 : 0]	rd_addr_fifo_dout;
			
			always@(*) begin	
				rd_addr_fifo_din = 'd0;
				if(master_0_araddr_valid) begin
					rd_addr_fifo_din = {master_0_araddr,master_0_ar_id,master_0_ar_len};
				end
				else if(master_1_araddr_valid) begin
					rd_addr_fifo_din = {master_1_araddr,master_1_ar_id,master_1_ar_len};
				end
			end
			
			assign rd_addr_fifo_wr_en =		(master_0_araddr_valid && master_0_araddr_ready)
										||	(master_1_araddr_valid && master_1_araddr_ready);
			
			assign rd_addr_fifo_rd_en = 	slave_araddr_valid && slave_araddr_ready;
			
			// ---------------------------------------- 读通道上层 ----------------------------------------
			reg 			rd_timeout_flag;
			reg 	[3:0]	rd_timeout_cnt;	//读突发超时最多16个周期
			reg 			rd_wait_timeout_flag;
			reg 	[3:0]	rd_wait_timeout_cnt;
			
			parameter 	RD_TOP_IDLE 		=	4'b0001	,
						RD_TOP_ADDR_RDY		=	4'b0010	,
						RD_TOP_ADDR_GRANT	=	4'b0100	,
						RD_TOP_ADDR_END		=	4'b1000	;
			
			reg 	[3:0]	rd_client_to_grant;
			
			reg 	[3:0]	rd_top_cur_state;
			reg 	[3:0]	rd_top_nex_state;
			
			always@(posedge clk) begin
				if(!rst_n) begin
					rd_client_to_grant <= CLIENT_0_AXI_ID;
				end
				else begin
					if(arbit_vector_reg == ROLL_POLING) begin
						if(rd_timeout_flag) begin
							if(rd_client_to_grant == CLIENT_0_AXI_ID) begin
								rd_client_to_grant <= CLIENT_1_AXI_ID;
							end
							else if(rd_client_to_grant == CLIENT_1_AXI_ID) begin
								rd_client_to_grant <= CLIENT_0_AXI_ID;
							end
						end
						else if(rd_wait_timeout_flag) begin
							if(rd_client_to_grant == CLIENT_0_AXI_ID) begin
								rd_client_to_grant <= CLIENT_1_AXI_ID;
							end
							else if(rd_client_to_grant == CLIENT_1_AXI_ID) begin
								rd_client_to_grant <= CLIENT_0_AXI_ID;
							end
						end
						else if(master_0_araddr_valid && master_0_araddr_ready) begin
							rd_client_to_grant <= CLIENT_1_AXI_ID;
						end
						else if(master_1_araddr_valid && master_1_araddr_ready) begin
							rd_client_to_grant <= CLIENT_0_AXI_ID;
						end
					end
					else if(arbit_vector_reg == STRAIGHT_IN) begin
		// ---------------------------------------- in progress ----------------------------------------
					end
					else if(arbit_vector_reg == CLIENT_0_FIRST) begin
		// ---------------------------------------- in progress ----------------------------------------
					end
					else if (arbit_vector_reg == CLIENT_1_FIRST) begin
		// ---------------------------------------- in progress ----------------------------------------			
					end
				end
			end
			
			always@(*) begin
				rd_top_nex_state = rd_top_cur_state;
				case(rd_top_cur_state) 
					RD_TOP_IDLE			:begin 
						if (master_0_araddr_valid || master_1_araddr_valid 
							&& !rd_addr_fifo_almost_full_flag) begin
							rd_top_nex_state = RD_TOP_ADDR_RDY;							
						end
					end
					RD_TOP_ADDR_RDY		:begin 
						if(rd_timeout_flag) begin
							rd_top_nex_state = RD_TOP_IDLE;		
						end
						else if(rd_client_to_grant == CLIENT_0_AXI_ID && master_0_araddr_valid) begin
							rd_top_nex_state = RD_TOP_ADDR_GRANT;							
						end
						else if(rd_client_to_grant == CLIENT_1_AXI_ID && master_1_araddr_valid) begin
							rd_top_nex_state = RD_TOP_ADDR_GRANT;		
						end
					end
					RD_TOP_ADDR_GRANT	:begin 
						if(rd_timeout_flag) begin
							rd_top_nex_state = RD_TOP_IDLE;		
						end
						else if(master_0_araddr_valid && master_0_araddr_ready) begin
							rd_top_nex_state = RD_TOP_ADDR_END;
						end
						else if(master_1_araddr_valid && master_1_araddr_ready) begin
							rd_top_nex_state = RD_TOP_ADDR_END;
						end
					end
					RD_TOP_ADDR_END		:begin 
						if(master_0_araddr_valid || master_1_araddr_valid) begin
							rd_top_nex_state = RD_TOP_ADDR_RDY;							
						end
						else begin
							rd_top_nex_state = RD_TOP_IDLE;		
						end
					end
					default				:begin
						rd_top_nex_state = RD_TOP_IDLE;		
					end
				endcase
			end
			
			always@(posedge clk) begin
				if(!rst_n) begin
					rd_top_cur_state <= RD_TOP_IDLE;
				end
				else begin	
					rd_top_cur_state <= rd_top_nex_state;
				end
			end
			
			always@(posedge clk) begin
				if(!rst_n) begin
					master_0_araddr_ready <= 1'b0;
					master_1_araddr_ready <= 1'b0;
				end
				else begin	
					if(rd_top_cur_state == RD_TOP_ADDR_GRANT) begin
						if(master_0_araddr_valid && master_0_araddr_ready) begin
							master_0_araddr_ready <= 1'b0;
						end
						else if(rd_client_to_grant == CLIENT_0_AXI_ID)begin
							master_0_araddr_ready <= 1'b1;
						end
						
						if(master_1_araddr_valid && master_1_araddr_ready) begin
							master_1_araddr_ready <= 1'b0;
						end
						else if(rd_client_to_grant == CLIENT_1_AXI_ID)begin
							master_1_araddr_ready <= 1'b1;
						end
					end
					else begin
						master_0_araddr_ready <= 1'b0;
						master_1_araddr_ready <= 1'b0;
					end
				end
			end
			
			always@(posedge clk) begin
				if(!rst_n) begin
					rd_timeout_flag <= 1'b0;
					rd_timeout_cnt <= 4'd0;
				end
				else begin
					if(master_1_araddr_valid && master_1_araddr_ready) begin
						rd_timeout_cnt <= 4'd0;
					end
					else if(master_0_araddr_valid && master_0_araddr_ready) begin
						rd_timeout_cnt <= 4'd0;
					end
					else if(rd_top_cur_state != RD_TOP_IDLE) begin
						rd_timeout_cnt <= rd_timeout_cnt == 4'hf ? 4'd0 : rd_timeout_cnt + 4'd1;
					end				
					rd_timeout_flag <= rd_timeout_cnt == 4'hf ? 1'b1 : 1'b0;
				end
			end
			
			always@(posedge clk) begin
				if(!rst_n) begin
					rd_wait_timeout_cnt <= 'd0;
					rd_wait_timeout_flag <= 1'b0;
				end
				else begin
					if(rd_top_cur_state == RD_TOP_IDLE || rd_top_cur_state == RD_TOP_ADDR_RDY) begin
						if(master_0_araddr_valid && master_0_araddr_ready) begin
							rd_wait_timeout_cnt <= 'd0;
							rd_wait_timeout_flag <= 1'b0;
						end
						else if(master_1_araddr_valid && master_1_araddr_ready)begin
							rd_wait_timeout_cnt <= 'd0;
							rd_wait_timeout_flag <= 1'b0;
						end
						else if(rd_client_to_grant == CLIENT_0_AXI_ID && !master_0_araddr_valid && master_1_araddr_valid) begin
							rd_wait_timeout_cnt <= rd_wait_timeout_cnt == ROLL_POLING_MAX_INTERVAL ? 'd0 : rd_wait_timeout_cnt + 1'b1;
							rd_wait_timeout_flag <= rd_wait_timeout_cnt == ROLL_POLING_MAX_INTERVAL ? 1'b1 : 1'b0;
						end
						else if(rd_client_to_grant == CLIENT_1_AXI_ID && !master_1_araddr_valid && master_0_araddr_valid) begin
							rd_wait_timeout_cnt <= rd_wait_timeout_cnt == ROLL_POLING_MAX_INTERVAL ? 'd0 : rd_wait_timeout_cnt + 1'b1;
							rd_wait_timeout_flag <= rd_wait_timeout_cnt == ROLL_POLING_MAX_INTERVAL ? 1'b1 : 1'b0;
						end
						else begin
							rd_wait_timeout_cnt <= 'd0;
							rd_wait_timeout_flag <= 1'b0;
						end
					end
					else begin
						rd_wait_timeout_cnt <= 'd0;
						rd_wait_timeout_flag <= 1'b0;
					end
				end
			end
			// ---------------------------------------- 读通道 FIFO 实例化 ----------------------------------------
			arbitor_afifo arbitor_rd_afifo_inst (
				.clk			(clk							),	// input
				.rst			(!rst_n							),	// input
				.wr_en			(rd_addr_fifo_wr_en				),	// input
				.wr_data		(rd_addr_fifo_din				),	// input [255:0]
				.almost_full	(rd_addr_fifo_almost_full_flag	),	// output
				.rd_en			(rd_addr_fifo_rd_en				),	// input
				.rd_data		(rd_addr_fifo_dout				),	// output [255:0]
				.empty			(rd_addr_fifo_empty				),	// output
				.almost_empty	(								)	// output
			);
			
			// ---------------------------------------- 读通道下层 ----------------------------------------
			assign slave_araddr_valid = !rd_addr_fifo_empty;
			assign slave_araddr = rd_addr_fifo_dout[WR_ADDR_FIIO_WIDTH-1:AXI_ID_WIDTH + AXI_LEN_WIDTH];
			assign slave_ar_id  = rd_addr_fifo_dout[AXI_ID_WIDTH + AXI_LEN_WIDTH-1:AXI_LEN_WIDTH];
			assign slave_ar_len = rd_addr_fifo_dout[AXI_LEN_WIDTH-1:0];
			assign slave_rd_data_last = 1'bz;
			assign slave_rd_id = 4'bzzzz;
			
			
			assign master_0_rd_data = slave_rd_data;
			assign master_0_rd_data_last = slave_rd_data_last;
			assign master_0_rd_id = slave_rd_id;
			assign master_0_rd_data_valid = slave_rd_data_valid;
			
			assign master_1_rd_data = slave_rd_data;
			assign master_1_rd_data_last = slave_rd_data_last;
			assign master_1_rd_id = slave_rd_id;
			assign master_1_rd_data_valid = slave_rd_data_valid;
			
			// ---------------------------------------- 超时机制行为定义 ----------------------------------------
			assign grant_busy[3] = master_0_wr_id == CLIENT_0_AXI_ID && master_0_wr_data_ready;
			assign grant_busy[2] = master_1_wr_id == CLIENT_1_AXI_ID && master_1_wr_data_ready;
			assign grant_busy[1] = master_0_rd_id == CLIENT_0_AXI_ID && master_0_rd_data_valid;
			assign grant_busy[0] = master_1_rd_id == CLIENT_1_AXI_ID && master_1_rd_data_valid;
			
			assign grant_overtime[3] = wr_data_client == CLIENT_0_AXI_ID && wr_overtime_flag;
			assign grant_overtime[2] = wr_data_client == CLIENT_1_AXI_ID && wr_overtime_flag;
			assign grant_overtime[1] = rd_client_to_grant == CLIENT_0_AXI_ID && rd_timeout_flag;
			assign grant_overtime[0] = rd_client_to_grant == CLIENT_1_AXI_ID && rd_timeout_flag;
		end
	endgenerate
endmodule