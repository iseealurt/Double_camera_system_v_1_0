//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: DC-CVS
// 
// Create Date: 2025-11-25 15:47 
// Design Name:  
// Module Name: tb_OV_DDR_HDMI_v_2_0
// Project Name: Double-Camera Computer Vision System (DC-CVS)
// Target Devices: Pango
// Tool Versions: 
// Description: 
//      
// Dependencies: 
// 
// Revision:
// 
//
// 
// 
// 
//                       
//                                  
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps
module tb_OV_DDR_HDMI_v_2_0();
	// ----------------------------------- global definition -----------------------------------
	`define DDR_CLK_SKEW_PS #0
	`define CMR_1_CLK_SKEW_PS #10
	`define CMR_2_CLK_SKEW_PS #300
	`define SIMULATION  
	`define sg25E       
	`define den4096Mb   
	`define x16   
	// ----------------------------------- included file -----------------------------------
	`include "../ipcore/ddr3_50h/example_design/bench/mem/ddr3_parameters.vh"
	// ----------------------------------- parameter definition -----------------------------------
	parameter 		MEM_ROW_ADDR_WIDTH 	= 15				;
	parameter 		MEM_COL_ADDR_WIDTH 	= 10				;
	parameter 		MEM_BADDR_WIDTH 	= 3					;
	parameter 		MEM_DQ_WIDTH 		= 32				;
	parameter 		MEM_DQS_WIDTH 		= MEM_DQ_WIDTH/8	;
	parameter 		MEM_DM_WIDTH 		= 4					;
	parameter 		MEM_NUM				= MEM_DQ_WIDTH/16	;
	parameter 		MEM_ADDR_WIDTH		= 15				;	
	parameter		CMR_1_FREQUENCY_KHZ	= 50_400			;
	parameter		CMR_2_FREQUENCY_KHZ	= 50_400			;
	parameter		CMR_1_PERIOD_PS		= 1_000_000_000 / CMR_1_FREQUENCY_KHZ /2;
	parameter		CMR_2_PERIOD_PS		= 1_000_000_000 / CMR_2_FREQUENCY_KHZ /2;
	parameter		CMR_1_V_WIDTH		= 640				;
	parameter		CMR_2_V_WIDTH		= 640				;
	parameter		CMR_1_V_HEIGHT		= 480				;
	parameter		CMR_2_V_HEIGHT		= 480				;
	parameter		CMR_1_FRESH_RATE	= 60				;
	parameter		CMR_1_ROW_INTERVAL_NS = 1_000_000_000 / CMR_1_FRESH_RATE / CMR_1_V_HEIGHT - CMR_1_V_WIDTH * CMR_1_PERIOD_PS / 1000;
	parameter		CMR_2_FRESH_RATE	= 60				;
	parameter		CMR_2_ROW_INTERVAL_NS = 1_000_000_000 / CMR_2_FRESH_RATE / CMR_2_V_HEIGHT - CMR_2_V_WIDTH * CMR_2_PERIOD_PS / 1000;
	// ----------------------------------- variale definition -----------------------------------
	reg										rst_n;
	reg 									clk_in_50m;
	
	reg 									cmr_1_pclk;
	reg 	[7:0]							cmr_1_din;
	reg 									cmr_1_href;
	reg 									cmr_1_vref;
	
	reg 									cmr_2_pclk;
	reg 	[7:0]							cmr_2_din;
	reg 									cmr_2_href;
	reg 									cmr_2_vref;
	
	wire 									ms_clk;
	wire 									ms_vsync;
	wire 									ms_hsync;
	wire 	[7:0]							ms_r_chn;
	wire 	[7:0]							ms_g_chn;
	wire 	[7:0]							ms_b_chn;
	wire 									ms_rst_n;
	wire 									ms_de;
	wire 									cmr_1_rst;
	wire 									cmr_2_rst;
	wire 									stream_stable;
	
	wire 									cmr_1_i2c_scl;
	wire 									cmr_1_i2c_sda;
	
	wire 									cmr_2_i2c_scl;
	wire 									cmr_2_i2c_sda;
	
	wire 									ms_i2c_scl;
	wire 									ms_i2c_sda;
	
	wire 									mem_rst_n;
	wire 									mem_ck;
	wire 									mem_ck_n;
	wire 									mem_cke;
	wire 									mem_cs_n;
	wire 									mem_ras_n;
	wire 									mem_cas_n;
	wire 									mem_we_n;
	wire 									mem_odt;
	wire 	[MEM_ROW_ADDR_WIDTH-1:0] 		mem_a;
	wire 	[MEM_BADDR_WIDTH-1:0] 			mem_ba;
	wire 	[MEM_DQS_WIDTH-1:0] 			mem_dqs;
	wire	[MEM_DQS_WIDTH-1:0]				mem_dqs_n;
	wire 	[MEM_DQ_WIDTH-1:0]				mem_dq;
	wire 	[MEM_DM_WIDTH-1:0]	 			mem_dm;
	reg  	[MEM_NUM:0]              		mem_ck_dly;
	reg  	[MEM_NUM:0]              		mem_ck_n_dly;
	
	wire 									stream_init_done;
	
	reg 	[11:0]							cmr_1_x_count;
	reg 	[11:0]							cmr_1_y_count;
	reg 	[11:0]							cmr_2_x_count;
	reg 	[11:0]							cmr_2_y_count;
	
	reg  	[15:0]							cmr_1_h_cnt;
	reg  	[15:0]							cmr_2_h_cnt;
	reg  	[15:0]							cmr_1_v_cnt;
	reg  	[15:0]							cmr_2_v_cnt;
	wire 	[15:0]							cmr_1_d_cnt = cmr_1_h_cnt + cmr_1_v_cnt;
	wire 	[15:0]							cmr_2_d_cnt = cmr_2_h_cnt + cmr_2_v_cnt;
	// ----------------------------------- hardware template definition for simulation -----------------------------------
	GTP_GRS GRS_INST (
		.GRS_N(rst_n) // INPUT  
	);
	
	// ---------------------------------------- DDR3 verification model ----------------------------------------
	always @ (*)
	begin
		mem_ck_dly[0]   <=  mem_ck;
		mem_ck_n_dly[0] <=  mem_ck_n;
	end
	wire [15:0] mem_addr;
	assign mem_addr = {{(ADDR_BITS-MEM_ADDR_WIDTH){1'b0}},{mem_a}};
	genvar gen_mem;                                                    
	generate                                                         
	for(gen_mem=0; gen_mem<MEM_NUM; gen_mem=gen_mem+1) begin   : i_mem 
		
		always @ (*)
		begin
			mem_ck_dly[gen_mem+1] <=`DDR_CLK_SKEW_PS mem_ck_dly[gen_mem];
			mem_ck_n_dly[gen_mem+1] <=`DDR_CLK_SKEW_PS mem_ck_n_dly[gen_mem];
		end
	 
		ddr3 mem_core (	
			.rst_n             (mem_rst_n	  				     ),
			.ck                (mem_ck_dly[gen_mem+1]            ),
			.ck_n              (mem_ck_n_dly[gen_mem+1]          ),
			.cs_n              (mem_cs_n                         ),
			.addr              (mem_addr                         ),
			.dq                (mem_dq[16*gen_mem+15:16*gen_mem] ),
			.dqs               (mem_dqs[2*gen_mem+1:2*gen_mem]   ),
			.dqs_n             (mem_dqs_n[2*gen_mem+1:2*gen_mem] ),
			.dm_tdqs           (mem_dm[2*gen_mem+1:2*gen_mem]    ),
			.tdqs_n            (                                 ),
			.cke               (mem_cke		  		 			 ),
			.odt               (mem_odt                          ),
			.ras_n             (mem_ras_n                        ),
			.cas_n             (mem_cas_n                        ),
			.we_n              (mem_we_n                         ),
			.ba                (mem_ba                           )
		);
	end     
	endgenerate
	
	// ---------------------------------------- DUT ----------------------------------------
	OV_DDR_HDMI_v_2_0 #(
		// 可配置参数 - 根据实际需求调整
		.DDR_CTRL_RST_TIME     (505000),           // DDR控制器复位时间，默认505us
		.MEM_ROW_ADDR_WIDTH    (MEM_ROW_ADDR_WIDTH),               // 内存行地址宽度
		.MEM_COL_ADDR_WIDTH    (MEM_COL_ADDR_WIDTH),               // 内存列地址宽度
		.MEM_BADDR_WIDTH       (MEM_BADDR_WIDTH),                // 内存bank地址宽度
		.MEM_DQ_WIDTH          (MEM_DQ_WIDTH),               // 内存数据总线宽度
		.MEM_DQS_WIDTH         (MEM_DQS_WIDTH),                // 内存DQS信号宽度 (32/8)
		.MEM_DM_WIDTH          (MEM_DM_WIDTH),                // 内存数据掩码宽度
		.CAMERA_WIDTH          (12'd640),          // 摄像头图像宽度
		.CAMERA_HEIGHT         (12'd480),          // 摄像头图像高度
		.AXI_ID_WIDTH          (4),                // AXI ID宽度
		.AXI_BURST_LEN_WIDTH   (4)                 // AXI突发长度宽度
	) dut (
		// 全局信号
		.clk_in_50m        (clk_in_50m),           // 50MHz系统时钟输入
		.rst_n             (rst_n),                // 低电平复位
		
		// UART信号
		.uart_rx           (),              // UART接收
		.uart_tx           (),              // UART发送
		
		// OV5640摄像头1信号
		.cmr_1_pclk        (cmr_1_pclk),           // 摄像头1像素时钟
		.cmr_1_din         (cmr_1_din),            // 摄像头1数据输入[7:0]
		.cmr_1_href        (cmr_1_href),           // 摄像头1行同步
		.cmr_1_vref        (cmr_1_vref),           // 摄像头1场同步
		.cmr_1_i2c_scl     (cmr_1_i2c_scl),        // 摄像头1 I2C SCL
		.cmr_1_i2c_sda     (cmr_1_i2c_sda),        // 摄像头1 I2C SDA
		.cmr_1_rst         (cmr_1_rst),            // 摄像头1复位
		
		// OV5640摄像头2信号
		.cmr_2_pclk        (cmr_2_pclk),           // 摄像头2像素时钟
		.cmr_2_din         (cmr_2_din),            // 摄像头2数据输入[7:0]
		.cmr_2_href        (cmr_2_href),           // 摄像头2行同步
		.cmr_2_vref        (cmr_2_vref),           // 摄像头2场同步
		.cmr_2_i2c_scl     (cmr_2_i2c_scl),        // 摄像头2 I2C SCL
		.cmr_2_i2c_sda     (cmr_2_i2c_sda),        // 摄像头2 I2C SDA
		.cmr_2_rst         (cmr_2_rst),            // 摄像头2复位
		
		// DDR SDRAM信号
		.mem_rst_n         (mem_rst_n),            // 内存复位（低有效）
		.mem_ck            (mem_ck),               // 内存时钟正相
		.mem_ck_n          (mem_ck_n),             // 内存时钟反相
		.mem_cke           (mem_cke),              // 内存时钟使能
		.mem_cs_n          (mem_cs_n),             // 内存片选（低有效）
		.mem_ras_n         (mem_ras_n),            // 内存行地址选通（低有效）
		.mem_cas_n         (mem_cas_n),            // 内存列地址选通（低有效）
		.mem_we_n          (mem_we_n),             // 内存写使能（低有效）
		.mem_odt           (mem_odt),              // 内存片上终端
		.mem_a             (mem_a),                // 内存地址总线
		.mem_ba            (mem_ba),               // 内存bank地址
		.mem_dqs           (mem_dqs),              // 内存数据选通
		.mem_dqs_n         (mem_dqs_n),            // 内存数据选通反相
		.mem_dq            (mem_dq),               // 内存数据总线
		.mem_dm            (mem_dm),               // 内存数据掩码
		
		// HDMI驱动芯片信号
		.ms_clk            (ms_clk),               // HDMI主时钟
		.ms_hsync          (ms_hsync),             // HDMI行同步
		.ms_vsync          (ms_vsync),             // HDMI场同步
		.ms_de             (ms_de),                // HDMI数据使能
		.ms_r_chn          (ms_r_chn),             // HDMI红色通道[7:0]
		.ms_g_chn          (ms_g_chn),             // HDMI绿色通道[7:0]
		.ms_b_chn          (ms_b_chn),             // HDMI蓝色通道[7:0]
		.ms_rst_n          (ms_rst_n),             // HDMI复位（低有效）
		.ms_i2c_scl        (ms_i2c_scl),           // HDMI I2C SCL
		.ms_i2c_sda        (ms_i2c_sda),           // HDMI I2C SDA
		
		// 调试信号
		.stream_init_done  (stream_init_done),     // 流初始化完成
		.stream_stable     ()         // 流稳定状态
	);
	
	// ---------------------------------------- Clock signal ----------------------------------------
	initial begin
		clk_in_50m = 0;
		forever #10_000 clk_in_50m = ~ clk_in_50m;
	end
	
	initial begin
		cmr_1_pclk = 0;
		`CMR_1_CLK_SKEW_PS;
		forever #CMR_1_PERIOD_PS cmr_1_pclk = ~ cmr_1_pclk;
	end
	
	initial begin
		cmr_2_pclk = 0;
		`CMR_2_CLK_SKEW_PS;
		forever #CMR_2_PERIOD_PS cmr_2_pclk = ~ cmr_2_pclk;
	end
	
	// ---------------------------------------- Tasks ----------------------------------------
	task generate_camera_frame;
	reg  cmr_1_frame_gene_end;
	reg  cmr_2_frame_gene_end;
    begin
		cmr_1_frame_gene_end = 0;
		cmr_2_frame_gene_end = 0;
		cmr_1_v_cnt = 0;
		cmr_2_v_cnt = 0;
		fork: frame_gene
			begin: cmr_1_frame_gene
				@(posedge cmr_1_pclk) cmr_1_vref = 0;
				#(1000*CMR_1_ROW_INTERVAL_NS);
				$display("@%0d ps, generate single frame for Camera 1", $time);   
				@(posedge cmr_1_pclk) cmr_1_vref = 1;
				#(1000*CMR_1_ROW_INTERVAL_NS);
				@(posedge cmr_1_pclk) cmr_1_vref = 0;	
				#(1000*CMR_1_ROW_INTERVAL_NS);				
				for(cmr_1_y_count = 0; cmr_1_y_count < CMR_1_V_HEIGHT ; cmr_1_y_count = cmr_1_y_count + 1) begin
					#(10*CMR_1_PERIOD_PS);
					cmr_1_h_cnt = 0;
					for(cmr_1_x_count = 0; cmr_1_x_count < CMR_1_V_WIDTH ; cmr_1_x_count = cmr_1_x_count + 1) begin
						@(posedge cmr_1_pclk)begin
							cmr_1_href = 1;
							cmr_1_din = cmr_1_d_cnt[15:8];
						end	
						@(posedge cmr_1_pclk)begin
							cmr_1_href = 1;
							cmr_1_din = cmr_1_d_cnt[7:0];
						end	
						cmr_1_h_cnt = cmr_1_h_cnt + 1;
					end	
					@(posedge cmr_1_pclk)begin
						cmr_1_href = 0;
						cmr_1_din = 8'hff;
						cmr_1_v_cnt = cmr_1_v_cnt + 1;
					end	
					#(1000*CMR_1_ROW_INTERVAL_NS);
				end
				cmr_1_frame_gene_end = 1;
			end			
			begin: cmr_2_frame_gene
				@(posedge cmr_2_pclk) cmr_2_vref = 0;
				#(1000*CMR_2_ROW_INTERVAL_NS);
				$display("@%0d ps, generate single frame for Camera 2", $time);        
				@(posedge cmr_2_pclk) cmr_2_vref = 1;
				#(1000*CMR_2_ROW_INTERVAL_NS);
				@(posedge cmr_2_pclk) cmr_2_vref = 0;
				#(1000*CMR_2_ROW_INTERVAL_NS);
				for(cmr_2_y_count = 0; cmr_2_y_count < CMR_2_V_HEIGHT ; cmr_2_y_count = cmr_2_y_count + 1) begin
					#(10*CMR_2_PERIOD_PS);	
					cmr_2_h_cnt = 0;
					for(cmr_2_x_count = 0; cmr_2_x_count < CMR_2_V_WIDTH ; cmr_2_x_count = cmr_2_x_count + 1) begin
						@(posedge cmr_2_pclk)begin
							cmr_2_href = 1;
							cmr_2_din = cmr_2_d_cnt[15:8];							
						end		
						@(posedge cmr_2_pclk)begin
							cmr_2_href = 1;
							cmr_2_din = cmr_2_d_cnt[7:0];								
						end	
						cmr_2_h_cnt = cmr_2_h_cnt + 1;
					end		
					@(posedge cmr_2_pclk)begin
						cmr_2_href = 0;
						cmr_2_din = 8'hff;
						cmr_2_v_cnt = cmr_2_v_cnt + 1;
					end	
					#(1000*CMR_2_ROW_INTERVAL_NS);
				end
				cmr_2_frame_gene_end = 1;
			end
			
			begin: exit_function
				wait(cmr_1_frame_gene_end && cmr_2_frame_gene_end) begin
					disable frame_gene;
				end
			end
		join
		$display("@%0d ps , single frame generation completed",$time);		
    end
	endtask
	// ---------------------------------------- Stimulus ----------------------------------------
	
	initial begin
		rst_n = 0;
		cmr_1_vref = 0;
		cmr_2_vref = 0;
		cmr_1_href = 0;
		cmr_2_href = 0;
		#100_000 rst_n = 1;
		$display("@%0d ps , reset was released",$time);
	end
	pulldown(cmr_1_i2c_scl);
	pulldown(cmr_1_i2c_sda);
	pulldown(cmr_2_i2c_scl);
	pulldown(cmr_2_i2c_sda);
	pulldown(ms_i2c_scl);
	pulldown(ms_i2c_sda);
	
	initial begin
		wait(stream_init_done) generate_camera_frame();
		#(1000*CMR_1_ROW_INTERVAL_NS);
		#(1000*CMR_1_ROW_INTERVAL_NS);
		#(1000*CMR_1_ROW_INTERVAL_NS);
		generate_camera_frame();
		#(1000*CMR_1_ROW_INTERVAL_NS);
		#(1000*CMR_1_ROW_INTERVAL_NS);
		#(1000*CMR_1_ROW_INTERVAL_NS);
		generate_camera_frame();
		#(1000*CMR_1_ROW_INTERVAL_NS);
		#(1000*CMR_1_ROW_INTERVAL_NS);
		#(1000*CMR_1_ROW_INTERVAL_NS);
		generate_camera_frame();
		#(1000*CMR_1_ROW_INTERVAL_NS);
		#(1000*CMR_1_ROW_INTERVAL_NS);
		#(1000*CMR_1_ROW_INTERVAL_NS);
		generate_camera_frame();
		#(1000*CMR_1_ROW_INTERVAL_NS);
		#(1000*CMR_1_ROW_INTERVAL_NS);
		#(1000*CMR_1_ROW_INTERVAL_NS);
		generate_camera_frame();
		$stop;
	end
	
	initial begin
		$dumpfile("waveform.vcd");
		$dumpvars(0, tb_OV_DDR_HDMI_v_2_0.dut.cmr_1_dvp_axi);  // 0表示记录所有层次
		$dumpvars(0, tb_OV_DDR_HDMI_v_2_0.dut.cmr_2_dvp_axi);  // 0表示记录所有层次 
		$dumpvars(0, tb_OV_DDR_HDMI_v_2_0.dut.u_axi_arbiter_v_2_0);  // 0表示记录所有层次
		$dumpvars(0, tb_OV_DDR_HDMI_v_2_0.dut.double_camera_disp_inst);  // 0表示记录所有层次
	end
	
	
endmodule