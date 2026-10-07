//============================================================================
// Module Name: census_5x5
// Description: 5x5 Census变换算法顶层模块
//              - 集成matrix_5x5矩阵生成模块（内部使用，不对外导出）
//              - 标准图像接口输入，Census变换结果输出
//============================================================================
module census_5x5#(
	parameter   [10:0]  IMAGE_WIDTH 	= 11'd640	,
	parameter   [10:0]  IMAGE_HEIGHT 	= 11'd480	,
	parameter   [10:0]  DELAY_NUM    	= 11'd50	,
	parameter           DATA_WIDTH   	= 8			,
	parameter           CENSUS_WIDTH 	= 24
)(
	input 	wire						pix_clk					,
	input 	wire						rst_n					,
	input 	wire 				        per_vga_vsync			,
	input 	wire 				        per_vga_href	   		,
	input 	wire 	[DATA_WIDTH-1:0]	per_vga_gray		    ,
	output 	wire 	[CENSUS_WIDTH-1:0]	census					,
	output 	reg 				        census_vsync			,
	output 	reg 				        census_href		
);
	wire 				        matrix_img_vsync		;
	wire 				        matrix_img_href		    ;
	wire 				        matrix_top_edge_flag	;
	wire 				        matrix_bottom_edge_flag	;
	wire 				        matrix_left_edge_flag	;
	wire 				        matrix_right_edge_flag	;
	wire 	[DATA_WIDTH-1:0]	matrix_p11				;
	wire 	[DATA_WIDTH-1:0]	matrix_p12				;
	wire 	[DATA_WIDTH-1:0]	matrix_p13				;
	wire 	[DATA_WIDTH-1:0]	matrix_p14				;
	wire 	[DATA_WIDTH-1:0]	matrix_p15				;
	wire 	[DATA_WIDTH-1:0]	matrix_p21				;
	wire 	[DATA_WIDTH-1:0]	matrix_p22				;
	wire 	[DATA_WIDTH-1:0]	matrix_p23				;
	wire 	[DATA_WIDTH-1:0]	matrix_p24				;
	wire 	[DATA_WIDTH-1:0]	matrix_p25				;
	wire 	[DATA_WIDTH-1:0]	matrix_p31				;
	wire 	[DATA_WIDTH-1:0]	matrix_p32				;
	wire 	[DATA_WIDTH-1:0]	matrix_p33				;
	wire 	[DATA_WIDTH-1:0]	matrix_p34				;
	wire 	[DATA_WIDTH-1:0]	matrix_p35				;
	wire 	[DATA_WIDTH-1:0]	matrix_p41				;
	wire 	[DATA_WIDTH-1:0]	matrix_p42				;
	wire 	[DATA_WIDTH-1:0]	matrix_p43				;
	wire 	[DATA_WIDTH-1:0]	matrix_p44				;
	wire 	[DATA_WIDTH-1:0]	matrix_p45				;
	wire 	[DATA_WIDTH-1:0]	matrix_p51				;
	wire 	[DATA_WIDTH-1:0]	matrix_p52				;
	wire 	[DATA_WIDTH-1:0]	matrix_p53				;
	wire 	[DATA_WIDTH-1:0]	matrix_p54				;
	wire 	[DATA_WIDTH-1:0]	matrix_p55				;

	// 输入信号打1拍
	reg                         per_vga_vsync_dly       ;
	reg                         per_vga_href_dly        ;
	reg		[DATA_WIDTH-1:0]	per_vga_gray_dly        ;
	
	always @(posedge pix_clk) begin
		if (!rst_n) begin
			per_vga_vsync_dly <= 1'b0;
			per_vga_href_dly  <= 1'b0;
			per_vga_gray_dly  <= {DATA_WIDTH{1'b0}};
		end
		else begin
			per_vga_vsync_dly <= per_vga_vsync;
			per_vga_href_dly  <= per_vga_href;
			per_vga_gray_dly  <= per_vga_gray;
		end
	end
	
	// vsync上升沿和下降沿检测
	wire vsync_rise_edge;
	wire vsync_fall_edge;
	
	assign vsync_rise_edge = per_vga_vsync && !per_vga_vsync_dly;  // 上升沿：当前为1，上一拍为0
	assign vsync_fall_edge = !per_vga_vsync && per_vga_vsync_dly;  // 下降沿：当前为0，上一拍为1
	
	// per_img_vsync时序逻辑变量：下降沿拉高，上升沿拉低
	reg per_img_vsync;
	
	always @(posedge pix_clk) begin
		if (!rst_n) begin
			per_img_vsync <= 1'b0;
		end
		else if (vsync_fall_edge) begin
			per_img_vsync <= 1'b1;  // 下降沿拉高
		end
		else if (vsync_rise_edge) begin
			per_img_vsync <= 1'b0;  // 上升沿拉低
		end
	end
	
	// matrix_5x5模块例化
	matrix_5x5 #(
		.IMG_HDISP				(IMAGE_WIDTH				),
		.IMG_VDISP				(IMAGE_HEIGHT				),
		.DELAY_NUM				(DELAY_NUM					)
	) u_matrix_5x5 (
		.clk					(pix_clk					),
		.rst_n					(rst_n						),
		.per_img_vsync			(per_img_vsync				),	// 场同步信号输入
		.per_img_href			(per_vga_href_dly			),	// 行有效信号输入
		.per_img_gray			(per_vga_gray_dly			),	// 灰度数据输入
		.matrix_img_vsync		(matrix_img_vsync			),
		.matrix_img_href		(matrix_img_href			),
		.matrix_top_edge_flag	(matrix_top_edge_flag		),
		.matrix_bottom_edge_flag(matrix_bottom_edge_flag	),
		.matrix_left_edge_flag	(matrix_left_edge_flag		),
		.matrix_right_edge_flag	(matrix_right_edge_flag		),
		.matrix_p11				(matrix_p11					),
		.matrix_p12				(matrix_p12					),
		.matrix_p13				(matrix_p13					),
		.matrix_p14				(matrix_p14					),
		.matrix_p15				(matrix_p15					),
		.matrix_p21				(matrix_p21					),
		.matrix_p22				(matrix_p22					),
		.matrix_p23				(matrix_p23					),
		.matrix_p24				(matrix_p24					),
		.matrix_p25				(matrix_p25					),
		.matrix_p31				(matrix_p31					),
		.matrix_p32				(matrix_p32					),
		.matrix_p33				(matrix_p33					),
		.matrix_p34				(matrix_p34					),
		.matrix_p35				(matrix_p35					),
		.matrix_p41				(matrix_p41					),
		.matrix_p42				(matrix_p42					),
		.matrix_p43				(matrix_p43					),
		.matrix_p44				(matrix_p44					),
		.matrix_p45				(matrix_p45					),
		.matrix_p51				(matrix_p51					),
		.matrix_p52				(matrix_p52					),
		.matrix_p53				(matrix_p53					),
		.matrix_p54				(matrix_p54					),
		.matrix_p55				(matrix_p55					)
	);

	//----------------------------------------------------------------------
	// Census变换逻辑 - 时序逻辑输出
	// 5x5窗口，共24个周围像素与中心像素p33比较
	// 边界区域（任意边缘标志有效）时，输出全0
	//----------------------------------------------------------------------
	wire boundary_flag;
	assign boundary_flag = matrix_top_edge_flag || matrix_bottom_edge_flag || 
	                       matrix_left_edge_flag || matrix_right_edge_flag;
	
	// 时序逻辑实现Census变换，加1级寄存器改善时序
	reg [CENSUS_WIDTH-1:0] census_reg;
	
	always @(posedge pix_clk) begin
		if(!rst_n) begin
			census_reg <= {CENSUS_WIDTH{1'b0}};
		end
		else if(boundary_flag) begin
			census_reg <= {CENSUS_WIDTH{1'b0}};
		end
		else begin
			census_reg <= {
				// 第1行（排除中心）
				(matrix_p11 > matrix_p33),  // bit23
				(matrix_p12 > matrix_p33),  // bit22
				(matrix_p13 > matrix_p33),  // bit21
				(matrix_p14 > matrix_p33),  // bit20
				(matrix_p15 > matrix_p33),  // bit19
				
				// 第2行（排除中心）
				(matrix_p21 > matrix_p33),  // bit18
				(matrix_p22 > matrix_p33),  // bit17
				(matrix_p23 > matrix_p33),  // bit16
				(matrix_p24 > matrix_p33),  // bit15
				(matrix_p25 > matrix_p33),  // bit14
				
				// 第3行（排除中心p33）
				(matrix_p31 > matrix_p33),  // bit13
				(matrix_p32 > matrix_p33),  // bit12
				(matrix_p34 > matrix_p33),  // bit11
				(matrix_p35 > matrix_p33),  // bit10
				
				// 第4行（排除中心）
				(matrix_p41 > matrix_p33),  // bit9
				(matrix_p42 > matrix_p33),  // bit8
				(matrix_p43 > matrix_p33),  // bit7
				(matrix_p44 > matrix_p33),  // bit6
				(matrix_p45 > matrix_p33),  // bit5
				
				// 第5行（排除中心）
				(matrix_p51 > matrix_p33),  // bit4
				(matrix_p52 > matrix_p33),  // bit3
				(matrix_p53 > matrix_p33),  // bit2
				(matrix_p54 > matrix_p33),  // bit1
				(matrix_p55 > matrix_p33)   // bit0
			};
		end
	end
	
	assign census = census_reg;

	always @(posedge pix_clk) begin
		if(!rst_n) begin
			census_vsync <= 1'b0;
			census_href <= 1'b0;
		end
		else begin
			census_vsync <= matrix_img_vsync;
			census_href <= matrix_img_href;
		end
	end

endmodule
