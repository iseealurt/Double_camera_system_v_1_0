//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer: DC-CVS
// 
// Create Date: 2025-11-20 11:04 
// Module Name: OV_DDR_HDMI_v_2_0
// Design Name: Double-Camera Computer Vision System (DC-CVS)  
// Project Name: Double-Camera Computer Vision System (DC-CVS)
// Target Devices: MES50HP Dev Board
// Tool Versions: Pango Design Suite 2022.2-SP6.4
// Description: 
//      
// Dependencies: IP core : DDR3 controller , FIFO  
// 
// Revision 1.0
// 支持双目摄像头输入，系统架构大幅优化
// Revision 2.0  
// 添加了双写通道/读通道的仲裁器
// 参数化配置功能优化
// 简化了采集层的代码，提升了其参数化配置效果
// 优化三重缓冲模块的缓冲区规划
// Revision 3.0 @20251208
// 解决了缓冲区分配重叠带来的显示问题                   
// 改用 BRAM 作为FIFO载体，解决了相关的显示问题      
// Revision 4.0 @20260313       
// 修改了双目视觉模块的时序，解决了相关的像素显示问题           
// Revision 5.0 @20260416
// AXI互连拓展器与新增的算法模块即将完成，需要上系统进行调试    
// Revision 6.0 @20260511
// SGM算法模块集成到SoC中
// Revision 7.0 @20260514
// 仲裁器更新为基于信用流控和固定优先级的4主机1从机的多路仲裁器
//////////////////////////////////////////////////////////////////////////////////

/*
// ----------------------------------- DEV log -----------------------------------
	@2025-11-24	17:17 第二版系统平台搭建完成
	@2025-12-08 22:55 数据链路完全通畅
	@2026-03-13 22:20 视觉平台采集部分工作正常
*/
module OV_DDR_HDMI_v_2_0#(
	// ----------------------------------- configurable parameter definition ----------------------------------- 
	parameter DDR_CTRL_RST_TIME		=	505000		, //505000: 505 us
	parameter MEM_ROW_ADDR_WIDTH	= 	15			,
	parameter MEM_COL_ADDR_WIDTH	= 	10			,
	parameter MEM_BADDR_WIDTH		= 	3			,
	parameter MEM_DQ_WIDTH			= 	32			,
	parameter MEM_DQS_WIDTH        	= 	32/8		,
	parameter MEM_DM_WIDTH			=	4			,
	parameter CAMERA_WIDTH			=	12'd640		,
	parameter CAMERA_HEIGHT			=	12'd480		,
	parameter AXI_ID_WIDTH			=	4			,
	parameter AXI_BURST_LEN_WIDTH	=	4			
)(
	// global signal
	input	wire 								clk_in_50m		,	//sys clk
	input 	wire 								rst_n			,
	// uart signal
	input 	wire 								uart_rx			,
	output 	wire 								uart_tx			,
	
	//ov5640 camera_1 signal
	input 	wire 								cmr_1_pclk		,
	input 	wire 	[7:0]						cmr_1_din		,	
	input 	wire 								cmr_1_href		,
	input 	wire 								cmr_1_vref		,
	inout 	wire 								cmr_1_i2c_scl	,
	inout 	wire 								cmr_1_i2c_sda	,	
	output 	wire								cmr_1_rst		,
	//ov5640 camera_1 signal
	input 	wire 								cmr_2_pclk		,
	input 	wire 	[7:0]						cmr_2_din		,	
	input 	wire 								cmr_2_href		,
	input 	wire 								cmr_2_vref		,
	inout 	wire 								cmr_2_i2c_scl	,
	inout 	wire 								cmr_2_i2c_sda	,	
	output 	wire 								cmr_2_rst		,
	//DDR SDRAM signal
	output 	wire 								mem_rst_n		,
	output 	wire 								mem_ck			,
	output 	wire 								mem_ck_n		,
	output 	wire 								mem_cke			,
	output 	wire 								mem_cs_n		,
	output  wire                              	mem_ras_n		,
	output  wire                              	mem_cas_n		,
	output  wire                              	mem_we_n		, 
	output  wire                              	mem_odt			,
	output  wire  	[MEM_ROW_ADDR_WIDTH-1:0	]  	mem_a			,   
	output  wire  	[MEM_BADDR_WIDTH-1:0	]	mem_ba			,   
	inout 	wire 	[MEM_DQS_WIDTH-1:0	]       mem_dqs			,
	inout	wire	[MEM_DQS_WIDTH-1:0	]      	mem_dqs_n		,
	inout 	wire	[MEM_DQ_WIDTH-1:0	]       mem_dq			,
	output  wire  	[MEM_DM_WIDTH-1:0	]       mem_dm			, 
	//HDMI driver chip signal
	output 	wire 								ms_clk			,
	output 	wire 								ms_hsync		,
	output 	wire 								ms_vsync		,
	output 	wire 								ms_de			,
	output 	wire 	[7:0]						ms_r_chn		,
	output 	wire 	[7:0]						ms_g_chn		,
	output 	wire 	[7:0]						ms_b_chn		,
	output 	wire 								ms_rst_n		,
	inout 	wire 								ms_i2c_scl		,
	inout 	wire 								ms_i2c_sda		,
	//debug signal
	output 	wire 								stream_init_done,
	output 	wire 								stream_stable	
);
// ----------------------------------- global parameter difine -----------------------------------
	`define Disp_1080P
	
// ----------------------------------- included parameter documents -----------------------------------
	`include "../RTL_code/Parameter_define/Disp_param.vh"
	
	
// ----------------------------------- Uncofigrable local parameter define -----------------------------------
	localparam	CMR1_AXI_ID 	= 	4'b0001	;
	localparam	CMR2_AXI_ID 	= 	4'b0010	;
	localparam	DISP_CMR1_AXI_ID= 	4'b0110	;
	localparam	DISP_CMR2_AXI_ID= 	4'b0111	;
	localparam	SGM_CMR1_AXI_ID = 	4'b0100	;
	localparam	SGM_CMR2_AXI_ID = 	4'b0101	;
	localparam  SGM_WR_AXI_ID   =   4'b0011 ;
	localparam 	UART_BODE_RATE	=	115200	;
	localparam	AXI_LEN_WIDTH	=	4		;
	localparam 	AXI_ADDR_WIDTH	=	MEM_BADDR_WIDTH + MEM_ROW_ADDR_WIDTH + MEM_COL_ADDR_WIDTH;
	localparam 	CMR_DATA_WIDTH	=	16		;
	localparam	DVP_AXI_WLEN	=	8		;
	localparam	CMR_1_WR_BUFFER	=	28'd0	;
	localparam 	CMR_2_WR_BUFFER = 	{3'b001,25'd0};
	localparam 	SGM_WR_BUFFER 	= 	{4'b0001,24'd0};
	localparam	AXI_D_WIDTH		=	MEM_DQ_WIDTH * 8;
	localparam  FRAME_EN_VALUE  = 	4'd0 	;
	localparam  MUX_CREDIT_MAX  =  	4'd10   ;

// ----------------------------------- wire variable define -----------------------------------
	// DDR SDRAM CONTROLLER 
	wire 								ddr_clk						;
	wire								controller_init_done		;
	wire 								pix_clk						;
	wire 								sgm_clk						;
	// Initialization 
	wire 								cmr_1_init_done				;	
	wire 								cmr_2_init_done				;
	wire 								cmr_1_init_en				;
	wire 								cmr_2_init_en				;	
	wire 								ms_init_en					;
	wire 								ms_init_end					;
	wire 								stream_rst_n				;
	wire 								ddr_rst_n					;	
	
	// AXI bus 
	wire 	[AXI_ADDR_WIDTH-1:0]		master_0_araddr				;
	wire 	[3:0]						master_0_ar_id				;
	wire 	[3:0]						master_0_ar_len				;
	wire 								master_0_araddr_valid		;
	wire 								master_0_araddr_ready		;	

	wire 	[AXI_ADDR_WIDTH-1:0]		master_0_awaddr				;
	wire 	[3:0]						master_0_aw_id				;
	wire 	[3:0]						master_0_aw_len				;
	wire 								master_0_awaddr_valid		;
	wire 								master_0_awaddr_ready		;
	
	wire 	[AXI_D_WIDTH-1:0]			master_0_wr_data			;
	wire 								master_0_wr_data_valid		;
	wire 	[MEM_DQ_WIDTH-1:0]			master_0_wstrb				;
	wire 								master_0_wr_data_ready		;
	wire 	[AXI_ID_WIDTH-1:0]			master_0_wr_id				;
	wire								master_0_wr_data_last		;
	
	wire 	[AXI_D_WIDTH-1:0]			master_0_rd_data			;
	wire 								master_0_rd_data_valid		;
	wire 								master_0_rd_data_ready		;
	wire 	[AXI_ID_WIDTH-1:0]			master_0_rd_id				;
	wire								master_0_rd_data_last		;
	
	// axi_arbiter_v_2_0 user_1 (CMR2写通道)
	wire 	[AXI_ADDR_WIDTH-1:0]		mux_u0_awaddr				;
	wire 	[3:0]						mux_u0_aw_id				;
	wire 	[3:0]						mux_u0_aw_len				;
	wire 								mux_u0_awaddr_valid			;
	wire 								mux_u0_awaddr_ready			;
	wire 	[AXI_D_WIDTH-1:0]			mux_u0_wr_data				;
	wire 	[MEM_DQ_WIDTH-1:0]			mux_u0_wstrb				;
	wire 								mux_u0_wr_data_ready		;
	wire 	[AXI_ID_WIDTH-1:0]			mux_u0_wr_id				;
	wire 								mux_u0_wr_data_last			;
	
	// axi_arbiter_v_2_0 user_2 (SGM_TOP 读+写通道)
	wire 	[AXI_ADDR_WIDTH-1:0]		mux_u1_araddr				;
	wire 	[3:0]						mux_u1_ar_id				;
	wire 	[3:0]						mux_u1_ar_len				;
	wire 								mux_u1_araddr_valid			;
	wire 								mux_u1_araddr_ready			;
	wire 	[AXI_ADDR_WIDTH-1:0]		mux_u1_awaddr				;
	wire 	[3:0]						mux_u1_aw_id				;
	wire 	[3:0]						mux_u1_aw_len				;
	wire 								mux_u1_awaddr_valid			;
	wire 								mux_u1_awaddr_ready			;
	wire 	[AXI_D_WIDTH-1:0]			mux_u1_wr_data				;
	wire 	[MEM_DQ_WIDTH-1:0]			mux_u1_wstrb				;
	wire 								mux_u1_wr_data_ready		;
	wire 	[AXI_ID_WIDTH-1:0]			mux_u1_wr_id				;
	wire 								mux_u1_wr_data_last			;
	wire 	[AXI_D_WIDTH-1:0]			mux_u1_rd_data				;
	wire 								mux_u1_rd_data_valid		;
	wire 								mux_u1_rd_data_ready		;
	wire 	[AXI_ID_WIDTH-1:0]			mux_u1_rd_id				;
	wire 								mux_u1_rd_data_last			;
	
	// axi_arbiter_v_2_0 arbiter 信号 (连接 DDR 控制器)
	wire 	[AXI_ADDR_WIDTH-1:0]		arb0_araddr					;
	wire 	[3:0]						arb0_ar_id					;
	wire 	[3:0]						arb0_ar_len					;
	wire 								arb0_araddr_valid			;
	wire 								arb0_araddr_ready			;
	wire 	[AXI_ADDR_WIDTH-1:0]		arb0_awaddr					;
	wire 	[3:0]						arb0_aw_id					;
	wire 	[3:0]						arb0_aw_len					;
	wire 								arb0_awaddr_valid			;
	wire 								arb0_awaddr_ready			;
	wire 	[AXI_D_WIDTH-1:0]			arb0_wr_data				;
	wire 	[MEM_DQ_WIDTH-1:0]			arb0_wstrb					;
	wire 								arb0_wr_data_ready			;
	wire 	[AXI_ID_WIDTH-1:0]			arb0_wr_id					;
	wire 								arb0_wr_data_last			;
	wire 	[AXI_D_WIDTH-1:0]			arb0_rd_data				;
	wire 								arb0_rd_data_valid			;
	wire 	[AXI_ID_WIDTH-1:0]			arb0_rd_id					;
	wire 								arb0_rd_data_last			;
	
	//trible-buffer
	wire 	[AXI_ADDR_WIDTH-1:0]		cmr_1_write_buffer_offset	;
	wire 	[AXI_ADDR_WIDTH-1:0]		cmr_2_write_buffer_offset	;
	wire 	[AXI_ADDR_WIDTH-1:0]		cmr_1_read_buffer_offset	;
	wire 	[AXI_ADDR_WIDTH-1:0]		cmr_2_read_buffer_offset	;
	
	wire 								dis_rd_end					;
	
	// frame_switch_v_2_0 aggregated read buffer offset vectors (2 users: display + SGM)
	wire 	[2*AXI_ADDR_WIDTH-1:0]		cmr1_rd_buf_vec				;
	wire 	[2*AXI_ADDR_WIDTH-1:0]		cmr2_rd_buf_vec				;
	
	// frame_switch_v_2_0 CMR1 SGM读通道独立输入连线 (rd_user_1)
	wire 	[AXI_ADDR_WIDTH-1:0]		fs1_sgm_araddr				;
	wire 	[AXI_ID_WIDTH-1:0]			fs1_sgm_arid				;
	wire 	[AXI_LEN_WIDTH-1:0]			fs1_sgm_arlen				;
	wire 								fs1_sgm_araddr_valid		;
	wire 								fs1_sgm_araddr_ready		;
	
	// frame_switch_v_2_0 CMR2 SGM读通道独立输入连线 (rd_user_1)
	wire 	[AXI_ADDR_WIDTH-1:0]		fs2_sgm_araddr				;
	wire 	[AXI_ID_WIDTH-1:0]			fs2_sgm_arid				;
	wire 	[AXI_LEN_WIDTH-1:0]			fs2_sgm_arlen				;
	wire 								fs2_sgm_araddr_valid		;
	wire 								fs2_sgm_araddr_ready		;
	
	wire 								cmr_1_pix_fifo_rst			;
	wire 								cmr_2_pix_fifo_rst			;
	
	wire 	[MEM_DQ_WIDTH*8-1:0]		cmr_1_pix_fifo_din			;
	wire 	[MEM_DQ_WIDTH*8-1:0]		cmr_2_pix_fifo_din			;
	
	wire 	[MEM_DQ_WIDTH*8-1:0]		cmr_1_pix_fifo_dout			;
	wire 	[MEM_DQ_WIDTH*8-1:0]		cmr_2_pix_fifo_dout			;
	
	wire 	[8:0]						cmr_1_pix_fifo_wr_wl		;
	wire 	[8:0]						cmr_2_pix_fifo_wr_wl		;
	
	wire 								cmr_1_pix_fifo_wr_req		;
	wire 								cmr_2_pix_fifo_wr_req		;
	
	wire 								cmr_1_pix_fifo_rd_req		;
	wire 								cmr_2_pix_fifo_rd_req		;
	
	wire 								cmr_1_pix_fifo_empty		;
	wire 								cmr_2_pix_fifo_empty		;
	
	wire 								dis_vsync					;
	wire 								dis_hsync					;
	wire 								dis_de						;
	wire 	[7:0]						dis_r_chn					;
	wire 	[7:0]						dis_g_chn					;
	wire 	[7:0]						dis_b_chn					;
	
	wire 								l_disp_valid				;
	wire 								r_disp_valid				;
	
	// sgm_disp overlay: VESA pass-through signals
	wire 								sgm_disp_vsync				;
	wire 								sgm_disp_hsync				;
	wire 								sgm_disp_de					;
	wire 	[7:0]						sgm_disp_r_chn				;
	wire 	[7:0]						sgm_disp_g_chn				;
	wire 	[7:0]						sgm_disp_b_chn				;
	
	// sgm_disp AXI read address channel (connected to arbiter user_3)
	wire 	[AXI_ID_WIDTH-1:0]			sgm_disp_axi_ar_id			;
	wire 	[AXI_LEN_WIDTH-1:0]			sgm_disp_axi_ar_len			;
	wire 	[AXI_ADDR_WIDTH-1:0]		sgm_disp_axi_araddr			;
	wire 								sgm_disp_axi_araddr_valid	;
	wire 								sgm_disp_axi_araddr_ready	;
	
	wire	[AXI_ADDR_WIDTH-1:0]		cmr_1_sgm_rd_buf_ofst		;
	wire	[AXI_ADDR_WIDTH-1:0]		cmr_2_sgm_rd_buf_ofst		;
	// sgm_disp AXI read data channel (from arbiter user_3)
	wire 	[AXI_D_WIDTH-1:0]			sgm_disp_axi_rdata			;
	wire 								sgm_disp_axi_rvalid			;
	wire 	[AXI_ID_WIDTH-1:0]			sgm_disp_axi_rid			;
	wire 								sgm_disp_axi_rlast			;
	
	// ----------------------------------- External module initialization -----------------------------------
	video_init #(
		.CLK_PERIOD					(20							),	// 50M hz clock input
		.DDR_RST_TIME				(DDR_CTRL_RST_TIME			)	// hold at least 500 us
	) video_init_inst(
		.clk_in         			(clk_in_50m					),	// 
		.ext_rst_n      			(rst_n						),	// 
		.ddr_init_done  			(controller_init_done		),	// 
		.cmr1_init_done 			(1'b1			),	// 
		.cmr2_init_done 			(1'b1			),	//
		.ms_init_done   			(1'b1				),	// 
		.ddr_rst_n      			(ddr_rst_n					),	// 
		.cmr1_init_en   			(cmr_1_init_en				),	// 
		.cmr2_init_en   			(cmr_2_init_en				),	// 
		.ms_init_en     			(ms_init_en					),	// 
		.stream_rst_n   			(stream_rst_n				)	// 
	);
	assign cmr_1_rst = controller_init_done;
	assign cmr_2_rst = controller_init_done;
	
	//ov5640 camera configration module
	uart_cfg cmr_1_uart_cfg_inst(
		.clk						(ddr_clk					),	//系统时钟
		.rst_n						(controller_init_done		),	//复位信号
		.uart_rx					(uart_rx					),
		.uart_tx					(uart_tx					),
		.cmr_init_en				(cmr_1_init_en				),
		.cmr_init_done				(cmr_1_init_done			),	//寄存器配置完成
		.i2c_scl					(cmr_1_i2c_scl				),  //SCL
		.i2c_sda					(cmr_1_i2c_sda				)   //SDA	
	);
	
	//ov5640 camera configration module
	uart_cfg cmr_2_uart_cfg_inst(
		.clk						(ddr_clk					),	//系统时钟
		.rst_n						(controller_init_done		),	//复位信号
		.uart_rx					(uart_rx					),
		.uart_tx					(							),
		.cmr_init_en				(cmr_2_init_en				),
		.cmr_init_done				(cmr_2_init_done			),	//寄存器配置完成
		.i2c_scl					(cmr_2_i2c_scl				),  //SCL
		.i2c_sda					(cmr_2_i2c_sda				)   //SDA	
	);
	
	//HDMI driver chip's initialization
	ms72xx_ctl ms_init_module(
		.clk						(clk_in_50m					),
		.rst_n						(ms_init_en					),    
		.init_over_tx				(ms_init_end				),
		.iic_tx_scl					(ms_i2c_scl					),
		.iic_tx_sda					(ms_i2c_sda					)
	);
	assign ms_rst_n = rst_n;
	
	// ----------------------------------- Video data acquisition layer -----------------------------------
	PLL pix_clk_gene (
		.clkin1						(clk_in_50m					),	// input
		.pll_lock					(PLL_lock					),	// output
		.clkout0					(pix_clk					),	// output
		.clkout1					(sgm_clk					)
	);
	
	DVP_AXI #(
		.AXI_ADDR_WIDTH				(AXI_ADDR_WIDTH				),
		.MEM_DQ_WIDTH				(MEM_DQ_WIDTH				),
		.WIDTH              		(CAMERA_WIDTH				),	// 可根据需要修改参数值
		.HEIGHT             		(CAMERA_HEIGHT				),	// 可根据需要修改参数值
		.PIXEL_DATA_WIDTH   		(CMR_DATA_WIDTH				),	// 可根据需要修改参数值
		.AXI_WLEN           		(DVP_AXI_WLEN				),	// 可根据需要修改参数值
		.FRAME_EN_VALUE     		(FRAME_EN_VALUE				),	// 可根据需要修改参数值
		.AXI_ID             		(CMR1_AXI_ID				)	// 可根据需要修改参数值
	) cmr_1_dvp_axi (
		.rst_n                  	(stream_rst_n				),	// input
		.dvp_pclk               	(cmr_1_pclk					),	// input
		.dvp_din                	(cmr_1_din					),	// input [7:0]
		.dvp_href               	(cmr_1_href					),	// input
		.dvp_vref               	(cmr_1_vref					),	// input
		.write_buffer_offset    	(cmr_1_write_buffer_offset	),	// input [AXI_ADDR_WIDTH-1:0]
		.axi_clk                	(ddr_clk					),	// input
		.axi_awaddr             	(master_0_awaddr			),	// output reg [AXI_ADDR_WIDTH-1:0]
		.axi_awready            	(master_0_awaddr_ready		),	// input
		.axi_awvalid            	(master_0_awaddr_valid		),	// output reg
		.axi_awid               	(master_0_aw_id				),	// output reg [3:0]
		.axi_awlen              	(master_0_aw_len			),	// output reg [3:0]
		.axi_wid                	(master_0_wr_id				),	// input [3:0]
		.axi_wready             	(master_0_wr_data_ready		),	// input
		.axi_wlast              	(master_0_wr_data_last		),	// input
		.axi_wdata              	(master_0_wr_data			),	// output wire [MEM_DQ_WIDTH*8-1:0]
		.axi_wstrb              	(master_0_wstrb				)	// output wire [MEM_DQ_WIDTH-1:0]
	);
	
	DVP_AXI #(
		.AXI_ADDR_WIDTH				(AXI_ADDR_WIDTH				),
		.MEM_DQ_WIDTH				(MEM_DQ_WIDTH				),
		.WIDTH              		(CAMERA_WIDTH				),	// 可根据需要修改参数值
		.HEIGHT             		(CAMERA_HEIGHT				),	// 可根据需要修改参数值
		.PIXEL_DATA_WIDTH   		(CMR_DATA_WIDTH				),	// 可根据需要修改参数值
		.AXI_WLEN           		(DVP_AXI_WLEN				),	// 可根据需要修改参数值
		.FRAME_EN_VALUE     		(FRAME_EN_VALUE				),	// 可根据需要修改参数值
		.AXI_ID             		(CMR2_AXI_ID				)	// 可根据需要修改参数值
	) cmr_2_dvp_axi (
		.rst_n                  	(stream_rst_n				),	// input
		.dvp_pclk               	(cmr_2_pclk					),	// input
		.dvp_din                	(cmr_2_din					),	// input [7:0]
		.dvp_href               	(cmr_2_href					),	// input
		.dvp_vref               	(cmr_2_vref					),	// input
		.write_buffer_offset    	(cmr_2_write_buffer_offset	),	// input [AXI_ADDR_WIDTH-1:0]
		.axi_clk                	(ddr_clk					),	// input
		.axi_awaddr             	(mux_u0_awaddr				),	// output reg [AXI_ADDR_WIDTH-1:0]
		.axi_awready            	(mux_u0_awaddr_ready		),	// input
		.axi_awvalid            	(mux_u0_awaddr_valid		),	// output reg
		.axi_awid               	(mux_u0_aw_id				),	// output reg [3:0]
		.axi_awlen              	(mux_u0_aw_len				),	// output reg [3:0]
		.axi_wid                	(mux_u0_wr_id				),	// input [3:0]
		.axi_wready             	(mux_u0_wr_data_ready		),	// input
		.axi_wlast              	(mux_u0_wr_data_last		),	// input
		.axi_wdata              	(mux_u0_wr_data				),	// output wire [MEM_DQ_WIDTH*8-1:0]
		.axi_wstrb              	(mux_u0_wstrb				)	// output wire [MEM_DQ_WIDTH-1:0]
	);
	
	
	// ----------------------------------- SGM 立体匹配算法顶层 -----------------------------------
	SGM_TOP #(
		.IMG_WIDTH				(CAMERA_WIDTH				),
		.IMG_HEIGHT				(CAMERA_HEIGHT				),
		.IMG_PIX_WIDTH			(16							),
		.AXI_ADDR_WIDTH			(AXI_ADDR_WIDTH				),
		.AXI_DATA_WIDTH			(AXI_D_WIDTH				),
		.AXI_ID_WIDTH			(AXI_ID_WIDTH				),
		.AXI_LEN_WIDTH			(AXI_LEN_WIDTH				),
		.MEM_DQ_WIDTH			(MEM_DQ_WIDTH				),
		.AXI_WLEN				(8							),
		.MAX_MATCH_DEPTH		(48							),
		.CENSUS_WIDTH			(24							),
		.DISPARITY_WIDTH		(8							),
		.SGM_P1					(3							),
		.SGM_P2					(24							),
		.SGM_LR_WIDTH			(12							),
		.CMR1_AXI_ID			(SGM_CMR1_AXI_ID			),
		.CMR2_AXI_ID			(SGM_CMR2_AXI_ID			),
		.WRITE_AXI_ID			(SGM_WR_AXI_ID				)
	) u_sgm_top (
		.pix_clk				(sgm_clk					),
		.sgm_clk				(sgm_clk					),
		.axi_clk				(ddr_clk					),
		.rst_n					(stream_rst_n				),				
		
		.axi_araddr				(mux_u1_araddr				),
		.axi_arid				(mux_u1_ar_id				),
		.axi_arlen				(mux_u1_ar_len				),
		.axi_arvalid			(mux_u1_araddr_valid		),
		.axi_arready			(mux_u1_araddr_ready		),
		
		.axi_rdata				(mux_u1_rd_data				),
		.axi_rid				(mux_u1_rd_id				),
		.axi_rvalid				(mux_u1_rd_data_valid		),
		.axi_rlast				(mux_u1_rd_data_last		),
		
		.axi_awaddr				(mux_u1_awaddr				),
		.axi_awid				(mux_u1_aw_id				),
		.axi_awlen				(mux_u1_aw_len				),
		.axi_awvalid			(mux_u1_awaddr_valid		),
		.axi_awready			(mux_u1_awaddr_ready		),
		
		.axi_wid  				(mux_u1_wr_id				),
		.axi_wdata				(mux_u1_wr_data				),
		.axi_wstrb				(mux_u1_wstrb				),
		.axi_wready				(mux_u1_wr_data_ready		),
		.axi_wlast				(mux_u1_wr_data_last		),
		
		.cmr_1_rd_buf_ofst		(cmr_1_sgm_rd_buf_ofst		),
		.cmr_2_rd_buf_ofst		(cmr_2_sgm_rd_buf_ofst		),
		.write_buffer_offset	(SGM_WR_BUFFER				)
	);
	
	// ----------------------------------- AXI 仲裁器 (4-user, 扁平化架构) -----------------------------------
	// user_0: CMR1写 + Display读    user_1: CMR2写    user_2: SGM    user_3: 预留
	axi_arbiter_v_2_0 #(
		.AXI_ADDR_WIDTH         (AXI_ADDR_WIDTH         ),
		.AXI_DATA_WIDTH         (AXI_D_WIDTH            ),
		.AXI_ID_WIDTH           (AXI_ID_WIDTH           ),
		.AXI_LEN_WIDTH          (AXI_LEN_WIDTH          ),
		.DDR_DATA_MASK_WIDTH    (MEM_DQ_WIDTH           ),
		.DATA_BACKPRESSURE_EN   (1'b0                   ),
		.CREDIT_DIGITS          (4                      ),
		.CREDIT_MAX_NUM         (MUX_CREDIT_MAX         )
	) u_axi_arbiter_v_2_0 (
		.axi_clk                (ddr_clk                ),
		.rst_n                  (stream_rst_n           ),
		.grant_busy             (                       ),
		
		// User 0: CMR1写通道 + Display读通道
		.user_0_araddr          (master_0_araddr        ),
		.user_0_ar_id           (master_0_ar_id         ),
		.user_0_ar_len          (master_0_ar_len        ),
		.user_0_araddr_valid    (master_0_araddr_valid  ),
		.user_0_araddr_ready    (master_0_araddr_ready  ),
		.user_0_awaddr          (master_0_awaddr        ),
		.user_0_aw_id           (master_0_aw_id         ),
		.user_0_aw_len          (master_0_aw_len        ),
		.user_0_awaddr_valid    (master_0_awaddr_valid  ),
		.user_0_awaddr_ready    (master_0_awaddr_ready  ),
		.user_0_wr_data         (master_0_wr_data       ),
		.user_0_wr_data_valid   (1'b1                   ),
		.user_0_wstrb           (master_0_wstrb         ),
		.user_0_wr_data_ready   (master_0_wr_data_ready ),
		.user_0_wr_id           (master_0_wr_id         ),
		.user_0_wr_data_last    (master_0_wr_data_last  ),
		.user_0_rd_data         (master_0_rd_data       ),
		.user_0_rd_data_valid   (master_0_rd_data_valid ),
		.user_0_rd_data_ready   (1'b1                   ),
		.user_0_rd_id           (master_0_rd_id         ),
		.user_0_rd_data_last    (master_0_rd_data_last  ),
		
		// User 1: CMR2写通道
		.user_1_araddr          ({AXI_ADDR_WIDTH{1'b0}} ),
		.user_1_ar_id           ({AXI_ID_WIDTH{1'b0}}   ),
		.user_1_ar_len          ({AXI_LEN_WIDTH{1'b0}}  ),
		.user_1_araddr_valid    (1'b0                   ),
		.user_1_araddr_ready    (                       ),
		.user_1_awaddr          (mux_u0_awaddr          ),
		.user_1_aw_id           (mux_u0_aw_id           ),
		.user_1_aw_len          (mux_u0_aw_len          ),
		.user_1_awaddr_valid    (mux_u0_awaddr_valid    ),
		.user_1_awaddr_ready    (mux_u0_awaddr_ready    ),
		.user_1_wr_data         (mux_u0_wr_data         ),
		.user_1_wr_data_valid   (1'b1                   ),
		.user_1_wstrb           (mux_u0_wstrb           ),
		.user_1_wr_data_ready   (mux_u0_wr_data_ready   ),
		.user_1_wr_id           (mux_u0_wr_id           ),
		.user_1_wr_data_last    (mux_u0_wr_data_last    ),
		.user_1_rd_data         (                       ),
		.user_1_rd_data_valid   (                       ),
		.user_1_rd_data_ready   (1'b1                   ),
		.user_1_rd_id           (                       ),
		.user_1_rd_data_last    (                       ),
		
		// User 2: SGM_TOP (读+写)
		.user_2_araddr          (mux_u1_araddr          ),
		.user_2_ar_id           (mux_u1_ar_id           ),
		.user_2_ar_len          (mux_u1_ar_len          ),
		.user_2_araddr_valid    (mux_u1_araddr_valid    ),
		.user_2_araddr_ready    (mux_u1_araddr_ready    ),
		.user_2_awaddr          (mux_u1_awaddr          ),
		.user_2_aw_id           (mux_u1_aw_id           ),
		.user_2_aw_len          (mux_u1_aw_len          ),
		.user_2_awaddr_valid    (mux_u1_awaddr_valid    ),
		.user_2_awaddr_ready    (mux_u1_awaddr_ready    ),
		.user_2_wr_data         (mux_u1_wr_data         ),
		.user_2_wr_data_valid   (1'b1                   ),
		.user_2_wstrb           (mux_u1_wstrb           ),
		.user_2_wr_data_ready   (mux_u1_wr_data_ready   ),
		.user_2_wr_id           (mux_u1_wr_id           ),
		.user_2_wr_data_last    (mux_u1_wr_data_last    ),
		.user_2_rd_data         (mux_u1_rd_data         ),
		.user_2_rd_data_valid   (mux_u1_rd_data_valid   ),
		.user_2_rd_data_ready   (1'b1                   ),
		.user_2_rd_id           (mux_u1_rd_id           ),
		.user_2_rd_data_last    (mux_u1_rd_data_last    ),
		
		// User 3: sgm_disp 读通道 (SGM视差图叠加显示)
		.user_3_araddr          (sgm_disp_axi_araddr       ),
		.user_3_ar_id           (sgm_disp_axi_ar_id        ),
		.user_3_ar_len          (sgm_disp_axi_ar_len       ),
		.user_3_araddr_valid    (sgm_disp_axi_araddr_valid ),
		.user_3_araddr_ready    (sgm_disp_axi_araddr_ready ),
		.user_3_awaddr          ({AXI_ADDR_WIDTH{1'b0}}    ),
		.user_3_aw_id           ({AXI_ID_WIDTH{1'b0}}      ),
		.user_3_aw_len          ({AXI_LEN_WIDTH{1'b0}}     ),
		.user_3_awaddr_valid    (1'b0                      ),
		.user_3_awaddr_ready    (                          ),
		.user_3_wr_data         ({AXI_D_WIDTH{1'b0}}       ),
		.user_3_wr_data_valid   (1'b0                      ),
		.user_3_wstrb           ({MEM_DQ_WIDTH{1'b0}}      ),
		.user_3_wr_data_ready   (                          ),
		.user_3_wr_id           (                          ),
		.user_3_wr_data_last    (                          ),
		.user_3_rd_data         (sgm_disp_axi_rdata        ),
		.user_3_rd_data_valid   (sgm_disp_axi_rvalid       ),
		.user_3_rd_data_ready   (1'b1                      ),
		.user_3_rd_id           (sgm_disp_axi_rid          ),
		.user_3_rd_data_last    (sgm_disp_axi_rlast        ),
		
		// Arbiter 侧: DDR3 控制器 (私有协议)
		.arbiter_araddr         (arb0_araddr            ),
		.arbiter_ar_id          (arb0_ar_id             ),
		.arbiter_ar_len         (arb0_ar_len            ),
		.arbiter_araddr_valid   (arb0_araddr_valid      ),
		.arbiter_araddr_ready   (arb0_araddr_ready      ),
		.arbiter_awaddr         (arb0_awaddr            ),
		.arbiter_aw_id          (arb0_aw_id             ),
		.arbiter_aw_len         (arb0_aw_len            ),
		.arbiter_awaddr_valid   (arb0_awaddr_valid      ),
		.arbiter_awaddr_ready   (arb0_awaddr_ready      ),
		.arbiter_wr_data        (arb0_wr_data           ),
		.arbiter_wr_data_valid  (                       ),	// NC - DDR私有协议
		.arbiter_wstrb          (arb0_wstrb             ),
		.arbiter_wr_data_ready  (arb0_wr_data_ready     ),
		.arbiter_wr_id          (arb0_wr_id             ),
		.arbiter_wr_data_last   (arb0_wr_data_last      ),
		.arbiter_rd_data        (arb0_rd_data           ),
		.arbiter_rd_data_valid  (arb0_rd_data_valid     ),
		.arbiter_rd_data_ready  (                       ),	// NC - DDR私有协议
		.arbiter_rd_id          (arb0_rd_id             ),
		.arbiter_rd_data_last   (arb0_rd_data_last      )
	);
	
	//DDR controller IP core
	ddr3_50h ddr3_50h_inst (
		.ref_clk					(clk_in_50m					),	// input
		.resetn						(ddr_rst_n					),	// input
		.ddr_init_done				(controller_init_done		),	// output
		.ddrphy_clkin				(ddr_clk					),	// output
		.pll_lock					(ddr_pll_lock				),	// output
		.axi_awaddr					(arb0_awaddr				),	// input [27:0]
		.axi_awuser_ap				(1'b0						),	// input
		.axi_awuser_id				(arb0_aw_id					),	// input [3:0]
		.axi_awlen					(arb0_aw_len				),	// input [3:0]
		.axi_awready				(arb0_awaddr_ready			),	// output
		.axi_awvalid				(arb0_awaddr_valid			),	// input
		.axi_wdata             		(arb0_wr_data             	),	// input [255:0]
		.axi_wstrb					(arb0_wstrb					),	// input [31:0]
		.axi_wready					(arb0_wr_data_ready			),	// output
		.axi_wusero_id				(arb0_wr_id					),	// output [3:0]
		.axi_wusero_last			(arb0_wr_data_last			),	// output
		.axi_araddr					(arb0_araddr				),	// input [27:0]
		.axi_aruser_ap				(1'b0						),	// input
		.axi_aruser_id				(arb0_ar_id					),	// input [3:0]
		.axi_arlen					(arb0_ar_len				),	// input [3:0]
		.axi_arready				(arb0_araddr_ready			),	// output
		.axi_arvalid				(arb0_araddr_valid			),	// input
		.axi_rdata					(arb0_rd_data				),	// output [255:0]
		.axi_rid					(arb0_rd_id					),	// output [3:0]
		.axi_rlast					(arb0_rd_data_last			),	// output
		.axi_rvalid					(arb0_rd_data_valid			),	// output
		.apb_clk					(1'b0						),	// input
		.apb_rst_n					(1'b1						),	// input
		.apb_sel					(1'b0						),	// input
		.apb_enable					(1'b0						),	// input
		.apb_addr					(8'd0						),	// input [7:0]
		.apb_write					(1'b0						),	// input
		.apb_ready					(							),	// output
		.apb_wdata					(16'd0						),	// input [15:0]
		.apb_rdata					(							),	// output [15:0]
		.apb_int					(							),	// output
		.debug_data					(							),	// output [135:0]
		.debug_slice_state			(							),	// output [51:0]
		.debug_calib_ctrl			(							),	// output [23:0]
		.ck_dly_set_bin				(							),	// output [7:0]
		.ck_dly_en					(1'b0						),	// input
		.init_ck_dly_step			(8'd0						),	// input [7:0]
		.wl_step_ov_warning			(							),	// output [3:0]
		.dll_step					(							),	// output [7:0]
		.dll_lock					(							),	// output
		.init_read_clk_ctrl			(8'd0						),	// input [7:0]
		.init_slip_step				(16'd0						),	// input [15:0]
		.force_read_clk_ctrl		(1'b0						),	// input
		.ddrphy_gate_update_en		(1'b0						),	// input
		.update_com_val_err_flag	(							),	// output [3:0]
		.rd_fake_stop				(1'b0						),	// input
		.mem_rst_n					(mem_rst_n					),	// output
		.mem_ck						(mem_ck						),	// output
		.mem_ck_n					(mem_ck_n					),	// output
		.mem_cke					(mem_cke					),	// output
		.mem_cs_n					(mem_cs_n					),	// output
		.mem_ras_n					(mem_ras_n					),	// output
		.mem_cas_n					(mem_cas_n					),	// output
		.mem_we_n					(mem_we_n					),	// output
		.mem_odt					(mem_odt					),	// output
		.mem_a						(mem_a						),	// output [14:0]
		.mem_ba						(mem_ba						),	// output [2:0]
		.mem_dqs					(mem_dqs					),	// inout [3:0]
		.mem_dqs_n					(mem_dqs_n					),	// inout [3:0]
		.mem_dq						(mem_dq						),	// inout [31:0]
		.mem_dm						(mem_dm						)	// output [3:0]
	);
		
	assign stream_init_done = stream_rst_n;
	
	// frame_switch_v_2_0 SGM读通道信号传递（通过独立中间连线避免直接端口拼接的隐式网表问题）
	assign fs1_sgm_araddr   = mux_u1_araddr;
	assign fs1_sgm_arvalid  = mux_u1_araddr_valid;
	assign fs1_sgm_arready  = mux_u1_araddr_ready;
	assign fs1_sgm_arid     = mux_u1_ar_id;
	assign fs1_sgm_arlen    = mux_u1_ar_len;
	
	assign fs2_sgm_araddr   = mux_u1_araddr;
	assign fs2_sgm_arvalid  = mux_u1_araddr_valid;
	assign fs2_sgm_arready  = mux_u1_araddr_ready;
	assign fs2_sgm_arid     = mux_u1_ar_id;
	assign fs2_sgm_arlen    = mux_u1_ar_len;
	
	// ----------------------------------- Frame Switch v2.0 (基于AXI地址的缓冲区管理) -----------------------------------
	// frame_switch_v_2_0 for Camera 1: write = CMR1, rd_user_0 = Display, rd_user_1 = SGM
	frame_switch_v_2_0 #(
		.AXI_ADDR_WIDTH				(AXI_ADDR_WIDTH				),
		.AXI_ID_WIDTH				(AXI_ID_WIDTH				),
		.AXI_LEN_WIDTH				(AXI_LEN_WIDTH				),
		.DDR_DQ_WIDTH				(MEM_DQ_WIDTH				),
		.PIX_DATA_WIDTH				(CMR_DATA_WIDTH				),
		.FRAME_WIDTH				(CAMERA_WIDTH				),
		.FRAME_HEIGHT				(CAMERA_HEIGHT				),
		.BUFFER_OFFSET				(CMR_1_WR_BUFFER			),
		.BUFFER_INTERVAL			(MEM_COL_ADDR_WIDTH			),
		.RD_USER_VAL				(2							)
	) cmr1_frame_switch_v_2_0 (
		.clk						(ddr_clk					),
		.rst_n						(stream_rst_n				),
		.wr_user_id					(CMR1_AXI_ID				),
		.rd_user_id					({SGM_CMR1_AXI_ID, DISP_CMR1_AXI_ID}),
		
		.wr_user_awaddr				(master_0_awaddr			),
		.wr_user_awvalid			(master_0_awaddr_valid		),
		.wr_user_awready			(master_0_awaddr_ready		),
		.wr_user_awid				(master_0_aw_id				),
		.wr_user_awlen				(master_0_aw_len			),
		
		.rd_user_araddr				({fs1_sgm_araddr, master_0_araddr}),
		.rd_user_arvalid			({fs1_sgm_arvalid, master_0_araddr_valid}),
		.rd_user_arready			({fs1_sgm_arready, master_0_araddr_ready}),
		.rd_user_arid				({fs1_sgm_arid, master_0_ar_id}),
		.rd_user_arlen				({fs1_sgm_arlen, master_0_ar_len}),
		
		.write_buffer_offset		(cmr_1_write_buffer_offset	),
		.read_buffer_offset			(cmr1_rd_buf_vec			)
	);
	
	// frame_switch_v_2_0 for Camera 2: write = CMR2, rd_user_0 = Display, rd_user_1 = SGM
	frame_switch_v_2_0 #(
		.AXI_ADDR_WIDTH				(AXI_ADDR_WIDTH				),
		.AXI_ID_WIDTH				(AXI_ID_WIDTH				),
		.AXI_LEN_WIDTH				(AXI_LEN_WIDTH				),
		.DDR_DQ_WIDTH				(MEM_DQ_WIDTH				),
		.PIX_DATA_WIDTH				(CMR_DATA_WIDTH				),
		.FRAME_WIDTH				(CAMERA_WIDTH				),
		.FRAME_HEIGHT				(CAMERA_HEIGHT				),
		.BUFFER_OFFSET				(CMR_2_WR_BUFFER			),
		.BUFFER_INTERVAL			(MEM_COL_ADDR_WIDTH			),
		.RD_USER_VAL				(2							)
	) cmr2_frame_switch_v_2_0 (
		.clk						(ddr_clk					),
		.rst_n						(stream_rst_n				),
		.wr_user_id					(CMR2_AXI_ID				),
		.rd_user_id					({SGM_CMR2_AXI_ID, DISP_CMR2_AXI_ID}),
		
		.wr_user_awaddr				(mux_u0_awaddr				),
		.wr_user_awvalid			(mux_u0_awaddr_valid		),
		.wr_user_awready			(mux_u0_awaddr_ready		),
		.wr_user_awid				(mux_u0_aw_id				),
		.wr_user_awlen				(mux_u0_aw_len				),
		
		.rd_user_araddr				({fs2_sgm_araddr, master_0_araddr}),
		.rd_user_arvalid			({fs2_sgm_arvalid, master_0_araddr_valid}),
		.rd_user_arready			({fs2_sgm_arready, master_0_araddr_ready}),
		.rd_user_arid				({fs2_sgm_arid, master_0_ar_id}),
		.rd_user_arlen				({fs2_sgm_arlen, master_0_ar_len}),
		
		.write_buffer_offset		(cmr_2_write_buffer_offset	),
		.read_buffer_offset			(cmr2_rd_buf_vec			)
	);
	
	// Decompose read_buffer_offset vectors: rd_user_0 -> Display, rd_user_1 -> SGM
	assign cmr_1_read_buffer_offset = cmr1_rd_buf_vec[0*AXI_ADDR_WIDTH+:AXI_ADDR_WIDTH];
	assign cmr_1_sgm_rd_buf_ofst = cmr1_rd_buf_vec[1*AXI_ADDR_WIDTH+:AXI_ADDR_WIDTH];
	assign cmr_2_read_buffer_offset = cmr2_rd_buf_vec[0*AXI_ADDR_WIDTH+:AXI_ADDR_WIDTH];
	assign cmr_2_sgm_rd_buf_ofst = cmr2_rd_buf_vec[1*AXI_ADDR_WIDTH+:AXI_ADDR_WIDTH];
	
	//用于FIFO复位的rd_end信号（与frame_switch无关）
	signal_sync#(
	.	SIG_RATE					(4'd10						)
	)dis_vref_sync(
		.sys_clk					(ddr_clk					),
		.rst_n						(stream_rst_n				),
		.signal_clk					(pix_clk					),
		.sig_unsync					(dis_vsync					),
		.sig_synced					(dis_rd_end					)	
	);
	
	drm_fifo_256b_8d cmr_1_pix_fifo (
		.wr_clk						(ddr_clk					),	// input
		.wr_rst						(cmr_1_pix_fifo_rst			),	// input
		.wr_en						(cmr_1_pix_fifo_wr_req		),	// input
		.wr_data					(cmr_1_pix_fifo_din			),	// input [255:0]
		.wr_full					(							),	// output
		.wr_water_level				(cmr_1_pix_fifo_wr_wl		),	// output [8:0]
		.almost_full				(							),	// output
		.rd_clk						(pix_clk					),	// input
		.rd_rst						(cmr_1_pix_fifo_rst			),	// input
		.rd_en						(cmr_1_pix_fifo_rd_req		),	// input
		.rd_data					(cmr_1_pix_fifo_dout		),	// output [255:0]
		.rd_empty					(cmr_1_pix_fifo_empty		),	// output
		.almost_empty				(							)	// output
	);
	//pix fifo instance 
	
	assign cmr_1_pix_fifo_din =  master_0_rd_data;
	assign cmr_1_pix_fifo_wr_req = master_0_rd_data_valid && master_0_rd_id == DISP_CMR1_AXI_ID;
	assign cmr_1_pix_fifo_rst = !stream_rst_n || dis_rd_end;
	
	drm_fifo_256b_8d cmr_2_pix_fifo (
		.wr_clk						(ddr_clk					),	// input
		.wr_rst						(cmr_2_pix_fifo_rst			),	// input
		.wr_en						(cmr_2_pix_fifo_wr_req		),	// input
		.wr_data					(cmr_2_pix_fifo_din			),	// input [255:0]
		.wr_full					(							),	// output
		.wr_water_level				(cmr_2_pix_fifo_wr_wl		),	// output [8:0]
		.almost_full				(							),	// output
		.rd_clk						(pix_clk					),	// input
		.rd_rst						(cmr_2_pix_fifo_rst			),	// input
		.rd_en						(cmr_2_pix_fifo_rd_req		),	// input
		.rd_data					(cmr_2_pix_fifo_dout		),	// output [255:0]
		.rd_empty					(cmr_2_pix_fifo_empty		),	// output
		.almost_empty				(							)	// output
	);
	//pix fifo instance 
	assign cmr_2_pix_fifo_din =  master_0_rd_data;
	assign cmr_2_pix_fifo_wr_req = master_0_rd_data_valid && master_0_rd_id == DISP_CMR2_AXI_ID;
	assign cmr_2_pix_fifo_rst = !stream_rst_n || dis_rd_end;
	
	//display driver 
	double_camera_disp #(
		// 视频时序参数
		.H_SYNC         			(H_SYNC     				),
		.H_BACK         			(H_BACK     				),
		.H_LEFT         			(H_LEFT     				),
		.H_VALID        			(H_VALID    				),
		.H_RIGHT        			(H_RIGHT    				),
		.H_FRONT        			(H_FRONT    				),
		.H_TOTAL        			(H_TOTAL    				),
		.V_SYNC         			(V_SYNC     				),
		.V_BACK         			(V_BACK     				),
		.V_TOP          			(V_TOP      				),
		.V_VALID        			(V_VALID    				),
		.V_BOTTOM       			(V_BOTTOM   				),
		.V_FRONT        			(V_FRONT    				),
		.V_TOTAL        			(V_TOTAL    				),
		.CMR_1_AXI_ID   			(DISP_CMR1_AXI_ID           ),
		.CMR_2_AXI_ID   			(DISP_CMR2_AXI_ID           ),
		.DDR_DQ_WIDTH   			(MEM_DQ_WIDTH				),
		.PIX_DWIDTH     			(CMR_DATA_WIDTH				),
		.CMR_1_VWIDTH   			(CAMERA_WIDTH           	),
		.CMR_2_VWIDTH   			(CAMERA_WIDTH           	),
		.CMR_1_VHEIGHT  			(CAMERA_HEIGHT           	),
		.CMR_2_VHEIGHT  			(CAMERA_HEIGHT				),
		.DISP_WIDTH     			(8           				),
		.AXI_ADDR_WIDTH 			(AXI_ADDR_WIDTH				),
		.AXI_DATA_WIDTH 			(MEM_DQ_WIDTH*8           	),
		.AXI_R_LEN_BASE 			(4'b0111           			),
		.AXI_ID_WIDTH   			(AXI_ID_WIDTH				),
		.AXI_LEN_WIDTH  			(AXI_BURST_LEN_WIDTH		)
	) double_camera_disp_inst (
		// 基础信号
		.rst_n                 		(stream_rst_n				),
		.pix_clk                	(pix_clk                	),
		.cmr_1_pix_fifo_wr_wl   	(cmr_1_pix_fifo_wr_wl[7:0]	),
		.cmr_2_pix_fifo_wr_wl   	(cmr_2_pix_fifo_wr_wl[7:0]	),
		.camera_1_rd_de         	(!cmr_1_pix_fifo_empty		),
		.camera_1_rd_data       	(cmr_1_pix_fifo_dout		),
		.camera_1_rd_req        	(cmr_1_pix_fifo_rd_req		),
		.camera_2_rd_de         	(!cmr_2_pix_fifo_empty		),
		.camera_2_rd_data       	(cmr_2_pix_fifo_dout		),
		.camera_2_rd_req        	(cmr_2_pix_fifo_rd_req		),
		.vsync                  	(dis_vsync                  ),
		.hsync                  	(dis_hsync                  ),
		.de                     	(dis_de                     ),
		.r_chn                  	(dis_r_chn                  ),
		.g_chn                  	(dis_g_chn                  ),
		.b_chn                  	(dis_b_chn                  ),
		.cmr_1_rd_buf_ofst      	(cmr_1_read_buffer_offset	),
		.cmr_2_rd_buf_ofst      	(cmr_2_read_buffer_offset	),
		.axi_clk                	(ddr_clk                	),
		.axi_ar_id              	(master_0_ar_id				),
		.axi_ar_len             	(master_0_ar_len			),
		.axi_araddr             	(master_0_araddr			),
		.axi_araddr_valid       	(master_0_araddr_valid		),
		.axi_araddr_ready       	(master_0_araddr_ready		),
		.l_disp_valid				(l_disp_valid				),
		.r_disp_valid				(r_disp_valid				)
	);
	
	sgm_disp #(
		.IMG_WIDTH				(CAMERA_WIDTH				),
		.IMG_HEIGHT				(CAMERA_HEIGHT				),
		.SGM_DISP_AXI_ID		(4'd8						),
		.DISP_H_OFFSET			(160						),
		.DISP_V_OFFSET			(562						),
		.DDR_DQ_WIDTH			(MEM_DQ_WIDTH				),
		.PIX_DWIDTH				(8							),
		.DISP_WIDTH				(8							),
		.AXI_ADDR_WIDTH			(AXI_ADDR_WIDTH				),
		.AXI_DATA_WIDTH			(MEM_DQ_WIDTH*8				),
		.AXI_ID_WIDTH			(AXI_ID_WIDTH				),
		.AXI_LEN_WIDTH			(AXI_LEN_WIDTH				)
	) u_sgm_disp (
		.rst_n					(stream_rst_n				),
		.pix_clk				(pix_clk					),
		.vsync_in				(dis_vsync					),
		.hsync_in				(dis_hsync					),
		.de_in					(dis_de						),
		.r_chn_in				(dis_r_chn					),
		.g_chn_in				(dis_g_chn					),
		.b_chn_in				(dis_b_chn					),
		.vsync_out				(sgm_disp_vsync				),
		.hsync_out				(sgm_disp_hsync				),
		.de_out					(sgm_disp_de				),
		.r_chn_out				(sgm_disp_r_chn				),
		.g_chn_out				(sgm_disp_g_chn				),
		.b_chn_out				(sgm_disp_b_chn				),
		.axi_clk				(ddr_clk					),
		.rd_buf_offset			(SGM_WR_BUFFER				),
		.axi_ar_id				(sgm_disp_axi_ar_id			),
		.axi_ar_len				(sgm_disp_axi_ar_len		),
		.axi_araddr				(sgm_disp_axi_araddr		),
		.axi_araddr_valid		(sgm_disp_axi_araddr_valid	),
		.axi_araddr_ready		(sgm_disp_axi_araddr_ready	),
		.axi_rvalid				(sgm_disp_axi_rvalid		),
		.axi_rlast				(sgm_disp_axi_rlast			),
		.axi_rdata				(sgm_disp_axi_rdata			),
		.axi_rid				(sgm_disp_axi_rid			)
	);
	
	assign ms_clk	= pix_clk;
	assign ms_vsync = sgm_disp_vsync;
	assign ms_hsync = sgm_disp_hsync;
	assign ms_de 	= sgm_disp_de;
	assign ms_r_chn = sgm_disp_r_chn;
	assign ms_g_chn = sgm_disp_g_chn;
	assign ms_b_chn = sgm_disp_b_chn;
	
endmodule