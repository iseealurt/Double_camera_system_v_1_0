module uart_cfg#(
	parameter 	SYS_CLK_FREQ	=	100_000_000		,
				I2C_CLK_FREQ	=	250_000			,
				UART_BODE_RATE	=	115_200			,
				UART_DEVICE_ID	=	8'h57			,
				UART_WR_CMD		=	8'hcd			,
				UART_RD_CMD		=	8'hab			,
				DEVICE_ACK_CODE	=	8'hac			,
				TIMEOUT_CODE	=	8'hef			,
				WR_END_CODE		=	8'hca			,
				RD_END_CODE		=	8'haa			,
				CMD_FALSE_CODE 	=	8'hcf			,
				CFG_BUSY_CODE	=	8'hcb
)(
	input 	wire 				clk				,
	input 	wire 				rst_n			,
	input 	wire 				uart_rx			,
	output 	wire 				uart_tx			,
	input	wire 				cmr_init_en		,
	output 	wire 				cmr_init_done	,
	
	//I2C interface
	inout 	wire 				i2c_scl			,
	inout 	wire 				i2c_sda			
);

	// UART 接口信号
	wire 			uart_rx_valid;
	wire 	[7:0]	uart_rx_data;
	reg 			uart_rx_ready;
	
	wire 			uart_tx_busy;
	reg 	[7:0]	uart_tx_data;
	reg 			uart_tx_valid;
	wire 			uart_tx_ready;
	
	reg 			cmd_false_flag;
	// OV5640 配置接口信号
	reg 			ov_wr_valid;
	wire 			ov_wr_ready;
	reg 	[15:0]	ov_wr_addr;
	reg 	[7:0]	ov_wr_data;
	
	reg 			ov_rw_flag;
	
	reg 			ov_rd_valid;
	wire 			ov_rd_ready;
	reg 	[15:0]	ov_rd_addr;
	wire 	[7:0]	ov_rd_data;
	reg 	[7:0]	ov_rd_data_reg;
	wire 			ov_busy;
	
	reg 	[31:0]	uart_timeout_cnt;
	wire 			uart_timeout_flag;
	
	reg 	[7:0]	uart_data_reg[4:0];
	reg 	[2:0]	uart_data_cnt;
	wire 	[39:0]	uart_data;
	
	assign uart_data = {uart_data_reg[4],uart_data_reg[3],uart_data_reg[2],uart_data_reg[1],uart_data_reg[0]};
	
	integer i;
	always@(posedge clk) begin
		if(!rst_n) begin
			for(i=0;i<5;i=i+1) begin
				uart_data_reg[i] <= 'd0;
			end
		end
		else begin
			if(uart_rx_valid && uart_rx_ready) begin
				uart_data_reg[4 - uart_data_cnt] <= uart_rx_data;
			end
		end
	end
	
	always@(posedge clk) begin
		if(!rst_n) begin
			uart_data_cnt <= 'd0;
		end
		else begin
			if(uart_timeout_flag) begin
				uart_data_cnt <= 'd0;
			end
			else if(cmd_false_flag) begin
				uart_data_cnt <= 'd0;
			end
			else if(uart_tx_ready && uart_tx_valid) begin
				uart_data_cnt <= 'd0;
			end
			else if(ov_wr_ready && ov_wr_valid) begin
				uart_data_cnt <= 'd0;
			end
			else if(ov_rd_ready && ov_rd_valid) begin
				uart_data_cnt <= 'd0;
			end
			else if(uart_rx_valid && uart_rx_ready) begin
				uart_data_cnt <= uart_data_cnt + 1'b1;
			end
		end
	end
	
	parameter TIMEOUT_CNT_VALUE = 12 * SYS_CLK_FREQ / UART_BODE_RATE - 1;
	
	always@(posedge clk) begin
		if(!rst_n) begin
			uart_timeout_cnt <= 'd0;
		end
		else begin
			if(uart_rx_valid && uart_rx_ready) begin
				uart_timeout_cnt <= 'd0;
			end
			else if(ov_wr_ready && ov_wr_valid) begin
				uart_timeout_cnt <= 'd0;
			end
			else if(ov_rd_ready && ov_rd_valid) begin
				uart_timeout_cnt <= 'd0;
			end
			else if(uart_tx_ready && uart_tx_valid) begin 
				uart_timeout_cnt <= 'd0; 
			end
			else if(uart_data_cnt > 0 && uart_data_cnt != 3'd5) begin
				
				uart_timeout_cnt <= uart_timeout_cnt == TIMEOUT_CNT_VALUE ? uart_timeout_cnt : uart_timeout_cnt + 1'b1;
				
			end
		end
	end
	
	assign uart_timeout_flag = uart_timeout_cnt == TIMEOUT_CNT_VALUE;
	
	parameter 	IDLE			=	7'd1	,
				INIT_BUSY		=	7'd2	,
				CMD_CHECK		=	7'd4	,
				CMD_EXE_RDY		=	7'd8	,
				CMD_EXE_BUSY	=	7'd16	,
				CMD_EXE_END		=	7'd32	,
				CMD_RESP		=	7'd64	;
			
	reg 	[6:0]	cur_state;
	reg 	[6:0]	nex_state;
	
	always@(*) begin
		nex_state = cur_state;
		case(cur_state)
			IDLE		:begin
				if(!cmr_init_done) begin
					nex_state = INIT_BUSY;
				end
				else if(uart_data_cnt == 3'd5) begin
					nex_state = CMD_CHECK;
				end
			end
			INIT_BUSY	:begin
				if(cmr_init_done) begin
					nex_state = IDLE;
				end
			end
			CMD_CHECK	:begin
				if(uart_data_reg[4] == UART_DEVICE_ID) begin
					if(uart_data_reg[3] == UART_RD_CMD) begin
						nex_state = CMD_EXE_RDY;
					end
					else if(uart_data_reg[3] == UART_WR_CMD) begin
						nex_state = CMD_EXE_RDY;
					end
					else begin
						nex_state = CMD_RESP;
					end
				end
				else begin
					nex_state = CMD_RESP;
				end
			end
			CMD_EXE_RDY		:begin
				if(ov_rd_valid && ov_rd_ready) begin
					nex_state = CMD_EXE_BUSY;
				end
				else if(ov_wr_valid && ov_wr_ready) begin
					nex_state = CMD_EXE_BUSY;
				end
			end
			CMD_EXE_BUSY	:begin
				if(ov_busy) begin
					nex_state = CMD_EXE_END;
				end
			end
			CMD_EXE_END		:begin
				if(ov_rd_valid && ov_rd_ready && !ov_rw_flag) begin
					nex_state = CMD_RESP;
				end
				else if(!ov_busy && ov_rw_flag) begin
					nex_state = CMD_RESP;
				end
			end
			CMD_RESP		:begin
				if(uart_tx_valid && uart_tx_ready) begin
					nex_state = IDLE;
				end
			end
			default			:begin
				nex_state = IDLE;
			end
		endcase
	end
	
	always@(posedge clk) begin
		if(!rst_n) begin
			cur_state <= IDLE;
		end
		else begin
			cur_state <= nex_state;
		end
	end
	
	always@(posedge clk) begin
		if(!rst_n) begin
			uart_rx_ready <= 1'b0;
		end
		else begin
			if(uart_rx_ready && uart_rx_valid) begin
				uart_rx_ready <= 1'b0;
			end
			else if(cur_state == IDLE && uart_rx_valid) begin
				uart_rx_ready <= 1'b1;
			end
		end
	end
	
	always@(posedge clk) begin
		if(!rst_n) begin
			cmd_false_flag <= 1'b0;
		end
		else begin
			if(cur_state == CMD_CHECK) begin
				if(uart_data_reg[4] == UART_DEVICE_ID) begin
						if(uart_data_reg[3] == UART_RD_CMD) begin
							cmd_false_flag <= 1'b0;
						end
						else if(uart_data_reg[3] == UART_WR_CMD) begin
							cmd_false_flag <= 1'b0;
						end
						else begin
							cmd_false_flag <= 1'b1;
						end
					end
				else begin
					cmd_false_flag <= 1'b1;
				end
			end
			else begin
				if(uart_tx_ready && uart_tx_valid) cmd_false_flag <= 1'b0;
			end
		end
	end
	
	always@(posedge clk) begin
		if(!rst_n) begin
			ov_wr_valid <= 1'b0;
			ov_wr_addr  <= 'd0;
			ov_wr_data  <= 'd0;
			ov_rd_addr 	<= 'd0;
			ov_rd_valid <= 'd0;
			ov_rd_data_reg <= 'd0;
			ov_rw_flag  <= 1'b0;
		end
		else begin
			case(cur_state) 
				CMD_CHECK  :begin 
					if(uart_data_reg[3] == UART_RD_CMD) begin
						ov_rw_flag <= 1'b0;
					end
					else if(uart_data_reg[3] == UART_WR_CMD) begin
						ov_rw_flag <= 1'b1;
					end
				end
				CMD_EXE_RDY:begin
					if(!ov_rw_flag) begin	
						if(ov_rd_valid && ov_rd_ready) begin
							ov_rd_valid <= 1'b0;
						end
						else begin
							ov_rd_addr 	<= {uart_data_reg[2],uart_data_reg[1]};
							ov_rd_valid <= 1'b1;
						end
					end
					else begin
						if(ov_wr_valid && ov_wr_ready) begin
							ov_wr_valid <= 1'b0;
						end
						else begin
							ov_wr_addr 	<= {uart_data_reg[2],uart_data_reg[1]};
							ov_wr_data 	<= uart_data_reg[0];
							ov_wr_valid <= 1'b1;
						end
					end
				end
				CMD_EXE_END:begin
					if(!ov_rw_flag) begin
						if(ov_rd_valid && ov_rd_ready) begin
							ov_rd_valid <= 1'b0;
							ov_rd_data_reg <= ov_rd_data;
						end
						else if(ov_rd_ready && !ov_rd_valid) begin
							ov_rd_valid <= 1'b1;
						end
						else begin
							ov_rd_valid <= 1'b0;
						end
					end
					else begin
						ov_rd_valid <= 1'b0;
						ov_rd_data_reg <= 'd0;
					end
				end
				default:	begin
					ov_wr_valid <= 1'b0;
					ov_wr_addr  <= 'd0;
					ov_wr_data  <= 'd0;
					ov_rd_addr 	<= 'd0;
					ov_rd_valid <= 'd0;
					ov_rw_flag  <= ov_rw_flag;
				end
			endcase
		end
	end
	
	always@(posedge clk) begin
		if(!rst_n) begin
			uart_tx_data <= 'd0;
			uart_tx_valid <= 1'b0;
		end
		else begin
			if(uart_tx_valid && uart_tx_ready) begin
				uart_tx_valid <= 1'b0;
				uart_tx_data <= uart_tx_data;
			end
			else if(uart_timeout_flag) begin
				uart_tx_data <= TIMEOUT_CODE;
				uart_tx_valid <= 1'b1;
			end
			else if(cmd_false_flag) begin
				uart_tx_data <= CMD_FALSE_CODE;
				uart_tx_valid <= 1'b1;
			end
			else if(cur_state == CMD_RESP) begin
				if(ov_rw_flag) begin
					uart_tx_data <= WR_END_CODE;
					uart_tx_valid <= 1'b1;
				end
				else begin
					uart_tx_data <= ov_rd_data_reg;
					uart_tx_valid <= 1'b1;
				end
			end
			else begin
				uart_tx_data <= uart_tx_data;
				uart_tx_valid <= uart_tx_valid;
			end	
		end
	end 
	
	uart_rx #(
		.CLK_FREQ			(SYS_CLK_FREQ	),
		.BODE_RATE			(UART_BODE_RATE	)
	) uart_rx_inst (
		.sys_clk			(clk			),
		.sys_rst_n			(rst_n			),
		.RX					(uart_rx		),
		.rd_ready			(uart_rx_ready	),
		.rd_valid			(uart_rx_valid	),
		.rd_data			(uart_rx_data	)
	);
	
	uart_tx #(
		.CLK_FREQ			(SYS_CLK_FREQ	),
		.BODE_RATE			(UART_BODE_RATE	)
	) uart_tx_inst (
		.sys_clk			(clk			),
		.sys_rst_n			(rst_n			),
		.wr_data			(uart_tx_data	),
		.wr_valid			(uart_tx_valid	),
		.busy				(uart_tx_busy	),
		.wr_ready			(uart_tx_ready	),
		.TX					(uart_tx		)
	);
	
	ov5640_config #(
		.SYS_CLK_FREQ_HZ	(SYS_CLK_FREQ	),
		.DEVICE_ID			(7'h3C			),
		.I2C_CLK_FREQ_HZ	(I2C_CLK_FREQ	)
	) ov5640_config_inst (
		.clk				(clk			),
		.rst_n				(rst_n			),
		.wr_valid			(ov_wr_valid	),
		.wr_ready			(ov_wr_ready	),
		.wr_addr			(ov_wr_addr		),
		.wr_data			(ov_wr_data		),
		.rd_valid			(ov_rd_valid	),
		.rd_ready			(ov_rd_ready	),
		.rd_addr			(ov_rd_addr		),
		.rd_data			(ov_rd_data		),
		.cmr_init_en		(cmr_init_en	),
		.cmr_init_done		(cmr_init_done	),
		.i2c_scl			(i2c_scl		),
		.i2c_sda			(i2c_sda		),
		.i2c_busy			(ov_busy		)
	);

endmodule
