//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: DC-CVS
// 
// Create Date: 2025-11-15 23:58  
// Design Name:  
// Module Name: ov5640_config
// Project Name: 
// Target Devices: \
// Tool Versions: 
// Description: 
//      
// Dependencies: 
// 
// Revision:
// Revision 1.0 - File Created
// 
//                       
//                                  
//////////////////////////////////////////////////////////////////////////////////
module ov5640_config#(
	parameter	SYS_CLK_FREQ_HZ	=	100_000_000	, 
	parameter	DEVICE_ID		=	7'h3C		,
	parameter 	I2C_CLK_FREQ_HZ	=	400_000			
)(
	input 	wire				clk				,
	input 	wire 				rst_n			,
	
	input 	wire 				wr_valid		,
	output	reg 				wr_ready		,
	input 	wire 	[15:0]		wr_addr			,
	input 	wire 	[7:0]		wr_data			,
		
	input 	wire 				rd_valid		,
	output 	reg 				rd_ready		,	
	//地址握手后开始读取，读取成功后拉高ready表示数据准备好，再次握手表示主机取走数据
	input 	wire 	[15:0]		rd_addr			,
	output 	reg 	[7:0]		rd_data			,
	
	input	wire 				cmr_init_en		,
	output 	wire 				cmr_init_done	,
	
	inout 	wire 				i2c_scl			/*synthesis PAP_MARK_DEBUG="true"*/,
	inout 	wire 				i2c_sda			/*synthesis PAP_MARK_DEBUG="true"*/,
	
	output 	wire 				i2c_busy	
);
	wire 			init_start;
	wire 			i2c_end;
	wire 	[23:0]	init_data;	
	reg 	[15:0]	addr_reg;
	reg 	[7:0]	wr_data_reg;
	wire 			i2c_end_pose;
	reg 			i2c_end_reg;
	
	
	always@(posedge clk) begin
		if(!rst_n) begin
			addr_reg <= 'd0;
			wr_data_reg <= 'd0;
		end
		else begin
			if(init_start) begin
				addr_reg <= init_data[23:8];
				wr_data_reg <= init_data[7:0];
			end
			else if(rd_valid && rd_ready) begin
				addr_reg <= rd_addr;
			end
			else if(wr_valid && wr_ready) begin
				addr_reg <= wr_addr;
				wr_data_reg <= wr_data;
			end
		end
	end
	
	parameter	IDLE		=	7'b000_0001	,
				INIT_RDY	=	7'b000_0010	,
				INIT_END	=	7'b000_0100	,
				WR_RDY		=	7'b000_1000	,
				WR_END		=	7'b001_0000	,
				RD_RDY		=	7'b010_0000 ,
				RD_END		=	7'b100_0000	;
				
	reg 	[6:0]	cur_state;
	reg 	[6:0]	nex_state;
	
	reg 			i2c_rw_ctrl;
	reg 			i2c_trans_en;
	
	wire 	[7:0]	i2c_rd_data;
	wire 			i2c_byte_over;
	
	always@(*) begin
		nex_state = cur_state;
		case(cur_state) 
			IDLE	:begin 
				if(cmr_init_en && !cmr_init_done) begin	
					nex_state = INIT_RDY;
				end
				else if(cmr_init_done && rd_valid && rd_ready) begin
					nex_state = RD_RDY;
				end
				else if(cmr_init_done && wr_valid && wr_ready) begin
					nex_state = WR_RDY;
				end
			end
			INIT_RDY:begin 
				if(cmr_init_done) begin
					nex_state = INIT_END;
				end
			end
			INIT_END:begin 
				nex_state = IDLE;
			end
			WR_RDY	:begin 
				if(i2c_end) begin
					nex_state = WR_END;
				end
			end
			WR_END	:begin 
				if(!i2c_end) begin
					nex_state = IDLE;
				end
			end
			RD_RDY	:begin 
				if(i2c_end) begin
					nex_state = RD_END;
				end
			end
			RD_END	:begin 
				if(rd_valid && rd_ready) begin
					nex_state = IDLE;
				end
			end
			default	:begin 
				nex_state = IDLE;
			end
		endcase
	end
	
	always@(posedge clk) begin
		if(!rst_n) begin
			cur_state <= IDLE;
			i2c_end_reg <= 1'b0;
		end
		else begin	
			cur_state <= nex_state;
			i2c_end_reg <= i2c_end;
		end
	end
	
	assign i2c_end_pose = i2c_end && !i2c_end_reg;
	
	
	always@(posedge clk) begin
		if(!rst_n) begin
			wr_ready <= 1'b0;
			rd_ready <= 1'b0;
		end
		else begin
			if(cur_state == IDLE) begin
				if(rd_valid && rd_ready) begin
					wr_ready <= 1'b0;
					rd_ready <= 1'b0;
				end
				else if(wr_valid && wr_ready) begin
					wr_ready <= 1'b0;
					rd_ready <= 1'b0;
				end
				else if(cmr_init_done && rd_valid && !rd_ready) begin
					wr_ready <= 1'b0;
					rd_ready <= 1'b1;
				end
				else if(cmr_init_done && wr_valid && !wr_ready) begin
					wr_ready <= 1'b1;
					rd_ready <= 1'b0;
				end
				else begin
					wr_ready <= 1'b0;
					rd_ready <= 1'b0;
				end
			end
			else if(cur_state == RD_END) begin
				if(rd_valid && rd_ready) begin
					wr_ready <= 1'b0;
					rd_ready <= 1'b0;
				end
				else begin
					wr_ready <= 1'b0;
					rd_ready <= 1'b1;
				end
			end
			else begin
				wr_ready <= 1'b0;
				rd_ready <= 1'b0;
			end
		end
	end
	
	always@(posedge clk) begin
		if(!rst_n) begin
			i2c_rw_ctrl <= 1'b0;
			i2c_trans_en <= 1'b0;
			rd_data <= 'd0;
		end
		else begin	
			if(cur_state == INIT_RDY) begin
				if(init_start) begin
					i2c_rw_ctrl <= 1'b1;
					i2c_trans_en <= 1'b1;
				end
				else begin
					i2c_rw_ctrl <= 1'b0;
					i2c_trans_en <= 1'b0;
				end
			end
			else if(cur_state == RD_RDY) begin
				i2c_rw_ctrl <= 1'b0;
				i2c_trans_en <= 1'b1;
			end
			else if(cur_state == WR_RDY) begin
				i2c_rw_ctrl <= 1'b1;
				i2c_trans_en <= 1'b1;
			end
			else begin
				i2c_rw_ctrl <= 1'b0;
				i2c_trans_en <= 1'b0;
			end
			
			if(cur_state == RD_END) begin
				rd_data <= i2c_end_pose ? i2c_rd_data : rd_data;
			end
		end
	end
	
	reg 	init_rdy;
	
	always@(posedge clk) begin
		if(!rst_n) begin
			init_rdy <= 1'b0;
		end
		else begin
			if(cur_state == INIT_RDY) begin
				init_rdy <= 1'b1;
			end
			else if(cur_state == INIT_END) begin
				init_rdy <= 1'b0;
			end
		end
	end
	
	assign i2c_busy = cur_state != IDLE;
	
	ov5640_cfg  ov5640_cfg_inst(
		.clk        	(clk    		),   //系统时钟,由iic模块传入
		.rst_n      	(rst_n  		),   //系统复位,低有效
		.cfg_rdy		(init_rdy		),
		.cfg_end        (i2c_end 		),   //单个寄存器配置完成
		.cfg_start      (init_start  	),   //单个寄存器配置触发信号
		.cfg_data       (init_data   	),   //ID,REG_ADDR,REG_VAL
		.cfg_done       (cmr_init_done  )    //寄存器配置完成
	);
	
	i2c_ctrl
	#(
		.DEVICE_ADDR    (DEVICE_ID 		), //i2c设备器件地址
		.SYS_CLK_FREQ   (SYS_CLK_FREQ_HZ), //i2c_ctrl模块系统时钟频率
		.SCL_FREQ       (I2C_CLK_FREQ_HZ)  //i2c的SCL时钟频率
	)
	i2c_ctrl_inst
	(
		.sys_clk     	(clk       		),   //输入系统时钟,50MHz
		.sys_rst_n   	(rst_n     		),   //输入复位信号,低电平有效
		.wr_en       	(i2c_rw_ctrl	),   //输入写使能信号
		.rd_en       	(!i2c_rw_ctrl	),   //输入读使能信号
		.i2c_start   	(i2c_trans_en	),   //输入i2c触发信号
		.addr_num    	(1'b1      		),   //输入i2c字节地址字节数
		.byte_addr   	(addr_reg		),   //输入i2c字节地址
		.wr_data     	(wr_data_reg	),   //输入i2c设备数据
		.rd_data    	(i2c_rd_data	),   //输出i2c设备读取数据
		.i2c_end     	(i2c_end       	),   //i2c一次读/写操作完成
		.i2c_clk     	(i2c_clk		),   //i2c驱动时钟
		.i2c_scl     	(i2c_scl      	),   //输出至i2c设备的串行时钟信号scl
		.i2c_sda     	(i2c_sda		)    //输出至i2c设备的串行数据信号sda
	);

endmodule