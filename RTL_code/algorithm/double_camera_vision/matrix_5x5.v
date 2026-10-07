//============================================================================
// Module Name: matrix_5x5
// Description: 5x5矩阵生成模块
//              使用4个FIFO缓存行数据，构建5x5像素窗口
//              支持边界检测和标志输出
//============================================================================
module matrix_5x5
#(
    parameter   [10:0]  IMG_HDISP = 11'd640,            // 图像宽度
    parameter   [10:0]  IMG_VDISP = 11'd480,            // 图像高度
    parameter   [10:0]  DELAY_NUM = 11'd50              // 倒数第二行到最后一行的间隔周期
)
(
    // 全局时钟和复位
    input  wire                 clk                     ,
    input  wire                 rst_n                   ,
    
    // 待处理的图像数据输入
    input  wire                 per_img_vsync           ,   // 输入图像场同步信号
    input  wire                 per_img_href            ,   // 输入图像行有效信号
    input  wire     [7:0]       per_img_gray            ,   // 输入图像灰度值
    
    // 处理后的图像数据输出
    output wire                 matrix_img_vsync        ,   // 输出图像场同步信号
    output wire                 matrix_img_href         ,   // 输出图像行有效信号
    output wire                 matrix_top_edge_flag    ,   // 输出图像上边界标志
    output wire                 matrix_bottom_edge_flag ,   // 输出图像下边界标志
    output wire                 matrix_left_edge_flag   ,   // 输出图像左边界标志
    output wire                 matrix_right_edge_flag  ,   // 输出图像右边界标志
    output reg      [7:0]       matrix_p11              ,   // 5x5矩阵输出
    output reg      [7:0]       matrix_p12              ,
    output reg      [7:0]       matrix_p13              ,
    output reg      [7:0]       matrix_p14              ,
    output reg      [7:0]       matrix_p15              ,
    output reg      [7:0]       matrix_p21              ,
    output reg      [7:0]       matrix_p22              ,
    output reg      [7:0]       matrix_p23              ,
    output reg      [7:0]       matrix_p24              ,
    output reg      [7:0]       matrix_p25              ,
    output reg      [7:0]       matrix_p31              ,  
    output reg      [7:0]       matrix_p32              ,
    output reg      [7:0]       matrix_p33              ,
    output reg      [7:0]       matrix_p34              ,
    output reg      [7:0]       matrix_p35              ,
    output reg      [7:0]       matrix_p41              ,
    output reg      [7:0]       matrix_p42              ,
    output reg      [7:0]       matrix_p43              ,
    output reg      [7:0]       matrix_p44              ,
    output reg      [7:0]       matrix_p45              ,
    output reg      [7:0]       matrix_p51              ,
    output reg      [7:0]       matrix_p52              ,
    output reg      [7:0]       matrix_p53              ,
    output reg      [7:0]       matrix_p54              ,
    output reg      [7:0]       matrix_p55              
);

	//==========================================================================
	// 核心实现原理分析：
	// 1. 使用4个级联FIFO缓存行数据，实现行延迟
	//    - FIFO1: 缓存第N-4行数据
	//    - FIFO2: 缓存第N-3行数据
	//    - FIFO3: 缓存第N-2行数据
	//    - FIFO4: 缓存第N-1行数据
	//    - 当前行: 直接输入per_img_gray
	// 2. 使用移位寄存器构建水平方向的5x5窗口
	// 3. 通过计数器控制FIFO的读写使能，实现正确的行延迟
	// 4. 边界处理：扩展最后两行，确保所有像素都能生成5x5窗口
	//==========================================================================

	//----------------------------------------------------------------------
	// 行计数器和列计数器
	// row_cnt: 行计数器，范围0~479 (IMG_VDISP-1)
	// col_cnt: 列计数器，范围0~639 (IMG_HDISP-1)
	//----------------------------------------------------------------------

	reg		[2:0]	per_img_href_dly;

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n)
			per_img_href_dly <= 3'd0;
		else
			per_img_href_dly <= {per_img_href_dly[1:0],per_img_href};
	end


	reg     [10:0]      row_cnt;    // 行计数器，最大值480-1
	reg     [10:0]      row_cnt_dly[2:0];
	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			row_cnt <= 11'b0;
			row_cnt_dly[0] <= 11'b0;
			row_cnt_dly[1] <= 11'b0;
			row_cnt_dly[2] <= 11'b0;
		end
		else begin

			row_cnt_dly[0] <= row_cnt;
			row_cnt_dly[1] <= row_cnt_dly[0];
			row_cnt_dly[2] <= row_cnt_dly[1];

			if(per_img_vsync == 1'b0)
				row_cnt <= 11'b0;
			else if(per_img_href == 1'b0 && per_img_href_dly[0] == 1'b1)  // href下降沿
				row_cnt <= row_cnt + 1'b1;
			else
				row_cnt <= row_cnt;
		end
	end

	reg     [10:0]      col_cnt;    // 列计数器，最大值640-1

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n)
			col_cnt <= 11'b0;
		else begin
			if(per_img_href == 1'b1)
				col_cnt <= col_cnt + 1'b1;
			else
				col_cnt <= 11'b0;
		end
	end



	//----------------------------------------------------------------------
	// 扩展最后两行计数器
	// 用于处理图像底部边界，确保最后两行也能生成完整的5x5窗口
	//----------------------------------------------------------------------
	reg     [11:0]      extend_last_two_row_cnt;

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n)
			extend_last_two_row_cnt <= 12'b0;
		else begin
			if((per_img_href == 1'b1) && (row_cnt == IMG_VDISP - 1'b1) && (col_cnt == IMG_HDISP - 1'b1))
				extend_last_two_row_cnt <= 12'd1;
			else if((extend_last_two_row_cnt > 12'b0) && (extend_last_two_row_cnt < {DELAY_NUM,1'b0} + {IMG_HDISP,1'b0}))
				extend_last_two_row_cnt <= extend_last_two_row_cnt + 1'b1;
			else
				extend_last_two_row_cnt <= 12'b0;
		end
	end

	// 扩展倒数第二行使能
	wire extend_2nd_last_row_en = (extend_last_two_row_cnt > DELAY_NUM) && (extend_last_two_row_cnt <= DELAY_NUM + IMG_HDISP) ? 1'b1 : 1'b0;
	// 扩展最后一行使能
	wire extend_1st_last_row_en = (extend_last_two_row_cnt > {DELAY_NUM,1'b0} + IMG_HDISP) ? 1'b1 : 1'b0;
	// 扩展倒数第二行使能三级延迟
	reg extend_2nd_last_row_en_dly[2:0];
	reg extend_1st_last_row_en_dly[2:0];
	
	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			extend_2nd_last_row_en_dly[0] <= 1'b0;
			extend_2nd_last_row_en_dly[1] <= 1'b0;
			extend_2nd_last_row_en_dly[2] <= 1'b0;
			extend_1st_last_row_en_dly[0] <= 1'b0;
			extend_1st_last_row_en_dly[1] <= 1'b0;
			extend_1st_last_row_en_dly[2] <= 1'b0;
		end
		else begin
			extend_2nd_last_row_en_dly[0] <= extend_2nd_last_row_en;
			extend_2nd_last_row_en_dly[1] <= extend_2nd_last_row_en_dly[0];
			extend_2nd_last_row_en_dly[2] <= extend_2nd_last_row_en_dly[1];
			extend_1st_last_row_en_dly[0] <= extend_1st_last_row_en;
			extend_1st_last_row_en_dly[1] <= extend_1st_last_row_en_dly[0];
			extend_1st_last_row_en_dly[2] <= extend_1st_last_row_en_dly[1];
		end
	end
	//----------------------------------------------------------------------
	// FIFO信号定义
	// 4个FIFO用于缓存行数据，实现行延迟
	//----------------------------------------------------------------------
	wire                fifo1_wenb;
	wire    [7:0]       fifo1_wdata;
	wire                fifo1_renb;
	wire    [7:0]       fifo1_rdata;

	wire                fifo2_wenb;
	wire    [7:0]       fifo2_wdata;
	wire                fifo2_renb;
	wire    [7:0]       fifo2_rdata;

	wire                fifo3_wenb;
	wire    [7:0]       fifo3_wdata;
	wire                fifo3_renb;
	wire    [7:0]       fifo3_rdata;

	wire                fifo4_wenb;
	wire    [7:0]       fifo4_wdata;
	wire                fifo4_renb;
	wire    [7:0]       fifo4_rdata;

	//----------------------------------------------------------------------
	// FIFO读写使能控制逻辑
	// FIFO1: 写入当前行，读出第N-4行
	// FIFO2: 写入FIFO1输出，读出第N-3行
	// FIFO3: 写入FIFO2输出，读出第N-2行
	// FIFO4: 写入FIFO3输出，读出第N-1行
	//----------------------------------------------------------------------
	assign fifo1_wenb  = per_img_href;
	assign fifo1_wdata = per_img_gray;
	assign fifo1_renb  = per_img_href & (row_cnt > 11'd0) | extend_2nd_last_row_en;
	assign fifo2_wenb  = per_img_href_dly[0] & (row_cnt_dly[0] > 11'd0) | extend_2nd_last_row_en_dly[0];
	assign fifo2_wdata = fifo1_rdata;
	assign fifo2_renb  = per_img_href_dly[0] & (row_cnt_dly[0] > 11'd1) | extend_2nd_last_row_en_dly[0] | extend_1st_last_row_en_dly[0];

	assign fifo3_wenb  = per_img_href_dly[1] & (row_cnt_dly[1] > 11'd1) | extend_2nd_last_row_en_dly[1];
	assign fifo3_wdata = fifo2_rdata;
	assign fifo3_renb  = per_img_href_dly[1] & (row_cnt_dly[1] > 11'd2) | extend_2nd_last_row_en_dly[1] | extend_1st_last_row_en_dly[1];

	assign fifo4_wenb  = per_img_href_dly[2] & (row_cnt_dly[2] > 11'd2) | extend_2nd_last_row_en_dly[2];
	assign fifo4_wdata = fifo3_rdata;
	assign fifo4_renb  = per_img_href_dly[2] & (row_cnt_dly[2] > 11'd3) | extend_2nd_last_row_en_dly[2] | extend_1st_last_row_en_dly[2];

	//----------------------------------------------------------------------
	// FIFO实例化
	// 使用FIFO_8w1024d IP核，位宽8bit，深度1024
	//----------------------------------------------------------------------
	FIFO_8w1024d u_fifo_0 (
		.wr_data    (fifo1_wdata),     // input [7:0]
		.wr_en      (fifo1_wenb),      // input
		.wr_full    (),                // output
		.rd_data    (fifo1_rdata),     // output [7:0]
		.rd_en      (fifo1_renb),      // input
		.rd_empty   (),                // output
		.clk        (clk),             // input
		.rst        (~rst_n)           // input
	);

	FIFO_8w1024d u_fifo_1 (
		.wr_data    (fifo2_wdata),     // input [7:0]
		.wr_en      (fifo2_wenb),      // input
		.wr_full    (),                // output
		.rd_data    (fifo2_rdata),     // output [7:0]
		.rd_en      (fifo2_renb),      // input
		.rd_empty   (),                // output
		.clk        (clk),             // input
		.rst        (~rst_n)           // input
	);

	FIFO_8w1024d u_fifo_2 (
		.wr_data    (fifo3_wdata),     // input [7:0]
		.wr_en      (fifo3_wenb),      // input
		.wr_full    (),                // output
		.rd_data    (fifo3_rdata),     // output [7:0]
		.rd_en      (fifo3_renb),      // input
		.rd_empty   (),                // output
		.clk        (clk),             // input
		.rst        (~rst_n)           // input
	);

	FIFO_8w1024d u_fifo_3 (
		.wr_data    (fifo4_wdata),     // input [7:0]
		.wr_en      (fifo4_wenb),      // input
		.wr_full    (),                // output
		.rd_data    (fifo4_rdata),     // output [7:0]
		.rd_en      (fifo4_renb),      // input
		.rd_empty   (),                // output
		.clk        (clk),             // input
		.rst        (~rst_n)           // input
	);

	

	//----------------------------------------------------------------------
	// 5x5矩阵构建和输出
	// 使用移位寄存器实现水平方向的窗口滑动
	// 每行5个像素，共5行，形成5x5窗口
	// 所有行数据经过相同的4拍总延迟，确保时序完全对齐
	//----------------------------------------------------------------------
	reg [7:0] row_5_d_reg	[3:0]	;
	reg [7:0] row_4_d_reg	[2:0]	;
	reg [7:0] row_3_d_reg	[1:0]	;
	reg [7:0] row_2_d_reg	 		;

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			row_5_d_reg[0] <= 8'h0;
			row_5_d_reg[1] <= 8'h0;
			row_5_d_reg[2] <= 8'h0;
			row_5_d_reg[3] <= 8'h0;
			row_4_d_reg[0] <= 8'h0;
			row_4_d_reg[1] <= 8'h0;
			row_4_d_reg[2] <= 8'h0;
			row_3_d_reg[0] <= 8'h0;
			row_3_d_reg[1] <= 8'h0;
			row_2_d_reg    <= 8'h0;
		end
		else begin
			row_5_d_reg[0] <= per_img_gray;
			row_5_d_reg[1] <= row_5_d_reg[0];
			row_5_d_reg[2] <= row_5_d_reg[1];
			row_5_d_reg[3] <= row_5_d_reg[2];
			row_4_d_reg[0] <= fifo1_rdata;
			row_4_d_reg[1] <= row_4_d_reg[0];
			row_4_d_reg[2] <= row_4_d_reg[1];
			row_3_d_reg[0] <= fifo2_rdata;
			row_3_d_reg[1] <= row_3_d_reg[0];
			row_2_d_reg    <= fifo3_rdata;
		end
	end
	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			{matrix_p11, matrix_p12, matrix_p13, matrix_p14, matrix_p15} <= 40'h0;
			{matrix_p21, matrix_p22, matrix_p23, matrix_p24, matrix_p25} <= 40'h0;
			{matrix_p31, matrix_p32, matrix_p33, matrix_p34, matrix_p35} <= 40'h0;
			{matrix_p41, matrix_p42, matrix_p43, matrix_p44, matrix_p45} <= 40'h0;
			{matrix_p51, matrix_p52, matrix_p53, matrix_p54, matrix_p55} <= 40'h0;
		end
		else begin
			{matrix_p51, matrix_p52, matrix_p53, matrix_p54, matrix_p55} <= {matrix_p52, matrix_p53, matrix_p54, matrix_p55,row_5_d_reg[3]};
			{matrix_p41, matrix_p42, matrix_p43, matrix_p44, matrix_p45} <= {matrix_p42, matrix_p43, matrix_p44, matrix_p45,row_4_d_reg[2]};
			{matrix_p31, matrix_p32, matrix_p33, matrix_p34, matrix_p35} <= {matrix_p32, matrix_p33, matrix_p34, matrix_p35,row_3_d_reg[1]};
			{matrix_p21, matrix_p22, matrix_p23, matrix_p24, matrix_p25} <= {matrix_p22, matrix_p23, matrix_p24, matrix_p25,row_2_d_reg};
			{matrix_p11, matrix_p12, matrix_p13, matrix_p14, matrix_p15} <= {matrix_p12, matrix_p13, matrix_p14, matrix_p15,fifo4_rdata};
		end
	end

	//----------------------------------------------------------------------
	// 输出信号延迟匹配
	//----------------------------------------------------------------------
	reg     [3:0]       int_vsync;
	reg     [2:0]       int_href;
	reg     [2:0]       int_top_edge_flag;
	reg     [2:0]       int_bottom_edge_flag;
	reg     [2:0]       int_left_edge_flag;
	reg     [2:0]       int_right_edge_flag;

	// vsync信号延迟
	always @(posedge clk or negedge rst_n) begin
		if(!rst_n)
			int_vsync <= 4'b0;
		else begin
			if((per_img_href == 1'b1) && (row_cnt == 11'd2) && (col_cnt == 11'b0))
				int_vsync[0] <= 1'b1;
			else if(extend_last_two_row_cnt == {DELAY_NUM,1'b0} + {IMG_HDISP,1'b0})
				int_vsync[0] <= 1'b0;
			else
				int_vsync[0] <= int_vsync[0];
			int_vsync[3:1] <= int_vsync[2:0];
		end
	end

	// href和边界标志延迟
	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			int_href             <= 3'b0;
			int_top_edge_flag    <= 3'b0;
			int_bottom_edge_flag <= 3'b0;
			int_left_edge_flag   <= 3'b0;
			int_right_edge_flag  <= 3'b0;
		end
		else begin
			// href信号延迟
			int_href[0]               <= per_img_href & (row_cnt > 11'd1) | extend_2nd_last_row_en | extend_1st_last_row_en;
			int_href[2:1]             <= int_href[1:0];
			
			// 上边界标志：第2-3行
			int_top_edge_flag[0]      <= per_img_href & ((row_cnt == 11'd2) | (row_cnt == 11'd3));
			int_top_edge_flag[2:1]    <= int_top_edge_flag[1:0];
			
			// 下边界标志：扩展的最后两行
			int_bottom_edge_flag[0]   <= extend_2nd_last_row_en | extend_1st_last_row_en;
			int_bottom_edge_flag[2:1] <= int_bottom_edge_flag[1:0];
			
			// 左边界标志：前2列
			int_left_edge_flag[0]     <= per_img_href & (row_cnt > 11'd1) & (col_cnt <= 11'd1) 
									| (extend_last_two_row_cnt == DELAY_NUM + 1'b1) 
									| (extend_last_two_row_cnt == DELAY_NUM + 2'd2) 
									| (extend_last_two_row_cnt == {DELAY_NUM,1'b0} + IMG_HDISP + 1'b1) 
									| (extend_last_two_row_cnt == {DELAY_NUM,1'b0} + IMG_HDISP + 2'd2);
			int_left_edge_flag[2:1]   <= int_left_edge_flag[1:0];
			
			// 右边界标志：后2列
			int_right_edge_flag[0]    <= per_img_href & (row_cnt > 11'd1) & (col_cnt >= IMG_HDISP - 2'd2) 
									| (extend_last_two_row_cnt == DELAY_NUM + IMG_HDISP - 1'b1) 
									| (extend_last_two_row_cnt == DELAY_NUM + IMG_HDISP) 
									| (extend_last_two_row_cnt == {DELAY_NUM,1'b0} + {IMG_HDISP,1'b0} - 1'b1) 
									| (extend_last_two_row_cnt == {DELAY_NUM,1'b0} + {IMG_HDISP,1'b0});
			int_right_edge_flag[2:1]  <= int_right_edge_flag[1:0];
		end
	end

	//----------------------------------------------------------------------
	// 同步信号额外延迟2个时钟周期，与像素数据的4拍总延迟对齐
	//----------------------------------------------------------------------
	reg     [3:0]   vsync_dly,hsync_dly,top_edge_dly,bottom_edge_dly,left_edge_dly,right_edge_dly;

	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			vsync_dly <= 4'd0;
			hsync_dly <= 4'd0;
			top_edge_dly <= 4'd0;
			bottom_edge_dly <= 4'd0;
			left_edge_dly <= 4'd0;
			right_edge_dly <= 4'd0;
		end
		else begin
			vsync_dly <= {vsync_dly[2:0],int_vsync[2] || int_vsync[3]};
			hsync_dly <= {hsync_dly[2:0],int_href[2]};
			top_edge_dly <= {top_edge_dly[2:0],int_top_edge_flag[2]};
			bottom_edge_dly <= {bottom_edge_dly[2:0],int_bottom_edge_flag[2]};
			left_edge_dly <= {left_edge_dly[2:0],int_left_edge_flag[2]};
			right_edge_dly <= {right_edge_dly[2:0],int_right_edge_flag[2]};
		end
	end

	//----------------------------------------------------------------------
	// 输出赋值
	//----------------------------------------------------------------------
	assign matrix_img_vsync        = vsync_dly[3];
	assign matrix_img_href         = hsync_dly[3];
	assign matrix_top_edge_flag    = top_edge_dly[3];
	assign matrix_bottom_edge_flag = bottom_edge_dly[3];
	assign matrix_left_edge_flag   = left_edge_dly[3];
	assign matrix_right_edge_flag  = right_edge_dly[3];
endmodule
