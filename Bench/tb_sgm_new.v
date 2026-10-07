//============================================================================
// Testbench for SGM Stereo Matching Algorithm Verification
// Description: 双目立体匹配算法验证平台
//              - 双摄像头像素数据FIFO缓冲
//              - RGB转灰度
//              - Census变换
//              - SGM半全局匹配
//============================================================================
`timescale  1ps/1ps

module tb_sgm_new();

//=============================================================================
//                           一、参数定义区
//=============================================================================
parameter 	PIX_CLK_PERIOD_PS		= 	50000;			// 20MHz (period = 50000ps, half = 25000ps)
parameter 	SGM_CLK_PERIOD_PS		=   50000;			// 20MHz (period = 50000ps, half = 25000ps)
parameter 	AXI_CLK_PERIOD_PS		=   10000;			// 100 MHz
parameter 	RST_HOLD_NS				= 	100;			// 复位保持时间
parameter 	TEST_INTERVAL_CYCLES	= 	50;				// 测试间隔
parameter 	DEFAULT_TIMEOUT			= 	1000000;		// 默认超时
parameter 	MAX_TASK_NUM			= 	64;				// 最大任务数

// -------------------------- DUT参数: 图像配置 --------------------------
parameter 	IMG_WIDTH           	= 	640;
parameter 	IMG_HEIGHT          	= 	480;
parameter 	IMG_PIX_WIDTH			= 	16;
// -------------------------- DUT参数: AXI总线 --------------------------
parameter 	AXI_ADDR_WIDTH      	= 	28;
parameter 	AXI_DATA_WIDTH      	= 	256;
parameter 	AXI_ID_WIDTH        	= 	4;
parameter 	AXI_LEN_WIDTH       	= 	4;
parameter 	DDR_DATA_MASK_WIDTH 	= 	32;

// -------------------------- DUT参数: SGM算法 --------------------------
parameter 	MAX_MATCH_DEPTH       	= 	96;
parameter 	GRAY_WIDTH            	= 	8;
parameter 	CENSUS_WIDTH          	= 	24;
parameter 	DISPARITY_WIDTH       	= 	16;

// -------------------------- 缓冲区偏移量设置 --------------------------
parameter   BUFFER_INTERVAL 		= 	28'h000_0010;	
parameter   RD_BUFFER_0_OFFSET 		=   28'h000_0000;
parameter   RD_BUFFER_1_OFFSET 		=   RD_BUFFER_0_OFFSET + BUFFER_INTERVAL + IMG_WIDTH * IMG_HEIGHT * IMG_PIX_WIDTH / 32;
// -------------------------- 内部常量 --------------------------
localparam 	CMR1_AXI_ID 			= 	4'b0001;		// 左摄像头AXI ID
localparam 	CMR2_AXI_ID 			= 	4'b0010;		// 右摄像头AXI ID
localparam 	SGM_LR_WIDTH 			= 	6;				// SGM代价聚合位宽
localparam 	LR_MAX_VAL 				= 	(1 << SGM_LR_WIDTH) - 1; // 63
localparam 	SGM_P1 					= 	8'd3;			// SGM P1 惩罚参数
localparam 	SGM_P2 					= 	8'd24;			// SGM P2 惩罚参数

//=============================================================================
//                           二、信号定义区
//=============================================================================
reg 							pix_clk;
reg 							axi_clk;
reg 							sgm_clk;
reg 							rst_n;

// -------------------------- AXI存储器接口 --------------------------
wire                            mem_ready;

wire    [AXI_ADDR_WIDTH-1:0]    disp_araddr;
wire    [AXI_ID_WIDTH-1:0]      disp_ar_id;
wire    [AXI_LEN_WIDTH-1:0]     disp_ar_len;
wire                            disp_araddr_valid;
wire                            disp_araddr_ready;
wire    [AXI_DATA_WIDTH-1:0]    disp_rd_data;
wire                            disp_rd_data_valid;
wire    [AXI_ID_WIDTH-1:0]      disp_rd_id;
wire                            disp_rd_data_last;

// -------------------------- 像素FIFO信号 --------------------------
wire                            cmr_1_pix_fifo_wr_en;
wire    [AXI_DATA_WIDTH-1:0]    cmr_1_pix_fifo_wr_data;
wire    [8:0]                   cmr_1_pix_fifo_wr_wl;
wire                            cmr_1_pix_fifo_rd_en;
wire    [AXI_DATA_WIDTH-1:0]    cmr_1_pix_fifo_rd_data;
wire                            cmr_1_pix_fifo_empty;

wire                            cmr_2_pix_fifo_wr_en;
wire    [AXI_DATA_WIDTH-1:0]    cmr_2_pix_fifo_wr_data;
wire    [8:0]                   cmr_2_pix_fifo_wr_wl;
wire                            cmr_2_pix_fifo_rd_en;
wire    [AXI_DATA_WIDTH-1:0]    cmr_2_pix_fifo_rd_data;
wire                            cmr_2_pix_fifo_empty;

// -------------------------- 显示模块输出 --------------------------
wire                            disp_vsync;
wire                            disp_href;
wire    [7:0]                   l_disp_r_chn;
wire    [7:0]                   l_disp_g_chn;
wire    [7:0]                   l_disp_b_chn;
wire    [7:0]                   r_disp_r_chn;
wire    [7:0]                   r_disp_g_chn;
wire    [7:0]                   r_disp_b_chn;

// -------------------------- 灰度化输出 --------------------------
wire                            l_gray_vsync;
wire                            l_gray_hsync;
wire    [7:0]                   l_gray_data;
wire                            r_gray_vsync;
wire                            r_gray_hsync;
wire    [7:0]                   r_gray_data;

// -------------------------- Census变换输出 --------------------------
wire    [23:0]                  l_census_data;
wire                            l_census_vsync;
wire                            l_census_href;
wire    [23:0]                  r_census_data;
wire                            r_census_vsync;
wire                            r_census_href;

// -------------------------- Census FIFO 接口 (sgm_new_3 前端) --------------------------
wire                            cmr_vsync_fifo_empty;
wire                            cmr_vsync_fifo_rd_en;
wire                            cmr_census_fifo_rd_en;
wire                            cmr1_line_fifo_empty;
wire    [CENSUS_WIDTH-1:0]      cmr1_census_fifo_dout;
wire                            cmr2_line_fifo_empty;
wire    [CENSUS_WIDTH-1:0]      cmr2_census_fifo_dout;

// -------------------------- SGM视差输出 --------------------------
wire                            disparity_vsync;
wire                            disparity_href;
wire    [15:0]                  disparity;

// -------------------------- vsync token 上升沿检测 (sgm_vsync_fifo 写入脉冲) --------------------------
wire                            vsync_combined;
reg                             vsync_combined_dly;
wire                            vsync_fifo_wr_en;

assign vsync_combined = l_census_vsync && r_census_vsync;
always @(posedge pix_clk) begin
    if(!rst_n)
        vsync_combined_dly <= 1'b0;
    else
        vsync_combined_dly <= vsync_combined;
end
assign vsync_fifo_wr_en = vsync_combined && !vsync_combined_dly;

// -------------------------- FIFO数据路由 --------------------------
assign cmr_1_pix_fifo_wr_en = disp_rd_data_valid && (disp_rd_id == CMR1_AXI_ID);
assign cmr_2_pix_fifo_wr_en = disp_rd_data_valid && (disp_rd_id == CMR2_AXI_ID);
assign cmr_1_pix_fifo_wr_data = disp_rd_data;
assign cmr_2_pix_fifo_wr_data = disp_rd_data;

//=============================================================================
//                           三、测试统计变量
//=============================================================================
integer 							total_task_count;
integer 							passed_task_count;
integer 							failed_task_count;
reg 								task_success_flag;

integer 							passed_task_id	[0:MAX_TASK_NUM-1];
integer 							failed_task_id	[0:MAX_TASK_NUM-1];
integer 							passed_idx;
integer 							failed_idx;
integer 							dump_wave_en;

integer 							frame_cnt;			// 帧计数器
integer 							disparity_sum;		// 视差统计
real 								disparity_avg;		// 平均视差
integer 							i;



//=============================================================================
//                           四、时钟复位
//=============================================================================
GTP_GRS GRS_INST (
	.GRS_N(rst_n)
);

initial begin
	pix_clk = 0;
	forever #(PIX_CLK_PERIOD_PS/2) pix_clk = ~pix_clk;
end

initial begin
	axi_clk = 0;
	forever #(AXI_CLK_PERIOD_PS/2) axi_clk = ~axi_clk;
end

initial begin
	sgm_clk = 0;
	forever #(SGM_CLK_PERIOD_PS/2) sgm_clk = ~sgm_clk;
end
//=============================================================================
//                           五、通用任务框架
//=============================================================================
// ----------------------------------------------------------
// 任务3: collect_left_census (sgm_new_3 输入端口截取)
// 触发: sgm_vsync posedge (SGM 读取 vsync FIFO 后进入 FRAME_BUSY)
// 数据源: u_sgm_new.cmr1_census, 有效标志: cmr_census_fifo_rd_en
// 时钟域: sgm_clk
// ----------------------------------------------------------
task collect_left_census;
	output 	reg 					success;
	reg                             sgm_vsync_raw;
	reg                             valid_raw;
	reg     [CENSUS_WIDTH-1:0]     data_raw;
	reg                             sgm_vsync_dly;
	reg                             valid_dly;
	reg     [CENSUS_WIDTH-1:0]     data_dly;
	integer 						col_cnt;
	integer 						row_cnt;
	integer 						timeout_cycle;
	integer 						fd;
	reg 	[7:0]					byte_buf;
	reg								frame_start;
begin
	success = 0;
	col_cnt = 0;
	row_cnt = 0;
	frame_start = 0;
	sgm_vsync_raw = 0;
	valid_raw = 0;
	data_raw = 0;
	sgm_vsync_dly = 0;
	valid_dly = 0;
	data_dly = 0;
	timeout_cycle = 2200 * 1125 * 20;
	total_task_count = total_task_count + 1;

	fd = $fopen("../Bench/tb_sgm_new_task_3.dat", "w");
	if(fd == 0) begin
		$display("@ %0t , [Left Census] ERROR: Cannot create file!", $time);
		success = 0;
	end
	else begin
		$display("@ %0t , [Left Census] File created, header written", $time);
		byte_buf = IMG_WIDTH[15:8];  $fwrite(fd, "%02h ", byte_buf);
		byte_buf = IMG_WIDTH[7:0];   $fwrite(fd, "%02h ", byte_buf);
		byte_buf = IMG_HEIGHT[15:8]; $fwrite(fd, "%02h ", byte_buf);
		byte_buf = IMG_HEIGHT[7:0];  $fwrite(fd, "%02h ", byte_buf);
		byte_buf = 8'h02;            $fwrite(fd, "%02h", byte_buf);

		fork: collect_exec
			begin : frame_collect
				while(1) begin
					@(posedge sgm_clk) begin
						sgm_vsync_dly = sgm_vsync_raw;
						valid_dly = valid_raw;
						data_dly = data_raw;

						sgm_vsync_raw = u_sgm_new.sgm_vsync;
						valid_raw = u_sgm_new.cmr_census_fifo_rd_en;
						data_raw = u_sgm_new.cmr1_census;

						if(!sgm_vsync_dly && sgm_vsync_raw) begin
							$display("@ %0t , [Left Census] sgm_vsync RISING EDGE, SGM enters FRAME_BUSY", $time);
							frame_start = 1;
							col_cnt = 0;
							row_cnt = 0;
						end

						if(frame_start && valid_dly) begin
							col_cnt = col_cnt + 1;
							byte_buf = data_dly[23:16]; $fwrite(fd, " %02h", byte_buf);
							byte_buf = data_dly[15:8];  $fwrite(fd, " %02h", byte_buf);
							byte_buf = data_dly[7:0];   $fwrite(fd, " %02h", byte_buf);
						end

						if(!valid_raw && valid_dly && frame_start) begin
							if(col_cnt > 0) begin
								col_cnt = 0;
								row_cnt = row_cnt + 1;
							end
						end

						if(sgm_vsync_dly && !sgm_vsync_raw && frame_start) begin
							$fclose(fd);
							$display("@ %0t , [Left Census] DONE: %0d rows x %0d cols", $time, row_cnt, col_cnt);
							success = 1;
							disable collect_exec;
						end
					end
				end
			end
			begin : timeout_monitor
				repeat(timeout_cycle) @(posedge sgm_clk);
				$display("@ %0t , [Left Census] TIMEOUT", $time);
				if(fd != 0) $fclose(fd);
				success = 0;
				disable collect_exec;
			end
		join
		$display("@ %0t , [Left Census] %s", $time, success ? "PASS" : "FAIL");
	end
end
endtask

// ----------------------------------------------------------
// 任务4: collect_right_census (sgm_new_3 输入端口截取)
// ----------------------------------------------------------
task collect_right_census;
	output 	reg 					success;
	reg                             sgm_vsync_raw;
	reg                             valid_raw;
	reg     [CENSUS_WIDTH-1:0]     data_raw;
	reg                             sgm_vsync_dly;
	reg                             valid_dly;
	reg     [CENSUS_WIDTH-1:0]     data_dly;
	integer 						col_cnt;
	integer 						row_cnt;
	integer 						timeout_cycle;
	integer 						fd;
	reg 	[7:0]					byte_buf;
	reg								frame_start;
begin
	success = 0;
	col_cnt = 0;
	row_cnt = 0;
	frame_start = 0;
	sgm_vsync_raw = 0;
	valid_raw = 0;
	data_raw = 0;
	sgm_vsync_dly = 0;
	valid_dly = 0;
	data_dly = 0;
	timeout_cycle = 2200 * 1125 * 20;
	total_task_count = total_task_count + 1;

	fd = $fopen("../Bench/tb_sgm_new_task_4.dat", "w");
	if(fd == 0) begin
		$display("@ %0t , [Right Census] ERROR: Cannot create file!", $time);
		success = 0;
	end
	else begin
		$display("@ %0t , [Right Census] File created, header written", $time);
		byte_buf = IMG_WIDTH[15:8];  $fwrite(fd, "%02h ", byte_buf);
		byte_buf = IMG_WIDTH[7:0];   $fwrite(fd, "%02h ", byte_buf);
		byte_buf = IMG_HEIGHT[15:8]; $fwrite(fd, "%02h ", byte_buf);
		byte_buf = IMG_HEIGHT[7:0];  $fwrite(fd, "%02h ", byte_buf);
		byte_buf = 8'h02;            $fwrite(fd, "%02h", byte_buf);

		fork: collect_exec
			begin : frame_collect
				while(1) begin
					@(posedge sgm_clk) begin
						sgm_vsync_dly = sgm_vsync_raw;
						valid_dly = valid_raw;
						data_dly = data_raw;

						sgm_vsync_raw = u_sgm_new.sgm_vsync;
						valid_raw = u_sgm_new.cmr_census_fifo_rd_en;
						data_raw = u_sgm_new.cmr2_census;

						if(!sgm_vsync_dly && sgm_vsync_raw) begin
							$display("@ %0t , [Right Census] sgm_vsync RISING EDGE, SGM enters FRAME_BUSY", $time);
							frame_start = 1;
							col_cnt = 0;
							row_cnt = 0;
						end

						if(frame_start && valid_dly) begin
							col_cnt = col_cnt + 1;
							byte_buf = data_dly[23:16]; $fwrite(fd, " %02h", byte_buf);
							byte_buf = data_dly[15:8];  $fwrite(fd, " %02h", byte_buf);
							byte_buf = data_dly[7:0];   $fwrite(fd, " %02h", byte_buf);
						end

						if(!valid_raw && valid_dly && frame_start) begin
							if(col_cnt > 0) begin
								col_cnt = 0;
								row_cnt = row_cnt + 1;
							end
						end

						if(sgm_vsync_dly && !sgm_vsync_raw && frame_start) begin
							$fclose(fd);
							$display("@ %0t , [Right Census] DONE: %0d rows x %0d cols", $time, row_cnt, col_cnt);
							success = 1;
							disable collect_exec;
						end
					end
				end
			end
			begin : timeout_monitor
				repeat(timeout_cycle) @(posedge sgm_clk);
				$display("@ %0t , [Right Census] TIMEOUT", $time);
				if(fd != 0) $fclose(fd);
				success = 0;
				disable collect_exec;
			end
		join
		$display("@ %0t , [Right Census] %s", $time, success ? "PASS" : "FAIL");
	end
end
endtask

task collect_disparity;
	output 	reg 					success;
	reg                             vsync_raw;
	reg                             href_raw;
	reg     [15:0]                 data_raw;
	reg                             vsync_dly;
	reg                             href_dly;
	reg     [15:0]                 data_dly;
	integer 						col_cnt;
	integer 						row_cnt;
	integer 						timeout_cycle;
	integer 						fd;
	reg 	[7:0]					byte_buf;
	reg								frame_start;
begin
	success = 0;
	col_cnt = 0;
	row_cnt = 0;
	frame_start = 0;
	vsync_raw = 0;
	href_raw = 0;
	data_raw = 0;
	vsync_dly = 0;
	href_dly = 0;
	data_dly = 0;
	timeout_cycle = 2200 * 1125 * 20;
	total_task_count = total_task_count + 1;
	
	fd = $fopen("../Bench/tb_sgm_new_task_5.dat", "w");
	if(fd == 0) begin
		$display("@ %0t , [Disparity] ERROR: Cannot create file!", $time);
		success = 0;
	end
	else begin
		$display("@ %0t , [Disparity] File created, header written", $time);
		byte_buf = IMG_WIDTH[15:8];  $fwrite(fd, "%02h ", byte_buf);
		byte_buf = IMG_WIDTH[7:0];   $fwrite(fd, "%02h ", byte_buf);
		byte_buf = IMG_HEIGHT[15:8]; $fwrite(fd, "%02h ", byte_buf);
		byte_buf = IMG_HEIGHT[7:0];  $fwrite(fd, "%02h ", byte_buf);
		byte_buf = 8'h04;            $fwrite(fd, "%02h", byte_buf);
		
		fork: collect_exec
			begin : frame_collect
				while(1) begin
					@(posedge sgm_clk) begin
						vsync_dly = vsync_raw;
						href_dly = href_raw;
						data_dly = data_raw;

						vsync_raw = disparity_vsync;
						href_raw = disparity_href;
						data_raw = disparity[15:0];
						
						if(!vsync_dly && vsync_raw) begin
							$display("@ %0t , [Disparity] vsync RISING EDGE, href_dly=%0d", $time, href_dly);
							frame_start = 1;
						end				
						
						if(href_dly && !frame_start) begin
							$display("@ %0t , [ERROR] [Disparity] HREF IS ACTIVE BUT VSYNC NOT DETECTED!", $time);
							$display("@ %0t , [ERROR] Check vsync/href alignment or vsync detection logic!", $time);
							$fclose(fd);
							success = 0;
							$stop;
							disable collect_exec;
						end
						
						if(frame_start && href_dly) begin
							col_cnt = col_cnt + 1;
							byte_buf = data_dly[15:8]; $fwrite(fd, " %02h", byte_buf);
							byte_buf = data_dly[7:0];  $fwrite(fd, " %02h", byte_buf);
						end						
						
						if(!href_raw && href_dly && frame_start) begin
							col_cnt = 0;
							row_cnt = row_cnt + 1;
						end						
						
						if(vsync_dly && !vsync_raw && frame_start) begin
							$fclose(fd);
							$display("@ %0t , [Disparity] DONE: %0d rows x %0d cols", $time, row_cnt, col_cnt);
							success = 1;
							disable collect_exec;
						end
					end
				end	
			end
			begin : timeout_monitor
				repeat(timeout_cycle) @(posedge sgm_clk);
				$display("@ %0t , [Disparity] TIMEOUT", $time);
				if(fd != 0) $fclose(fd);
				success = 0;
				disable collect_exec;
			end
		join
		$display("@ %0t , [Disparity] %s", $time, success ? "PASS" : "FAIL");
	end
end
endtask

task collect_left_gray;
	output 	reg 					success;
	reg                             vsync_raw;
	reg                             hsync_raw;
	reg     [GRAY_WIDTH-1:0]        data_raw;
	reg                             vsync_dly;
	reg                             hsync_dly;
	reg     [GRAY_WIDTH-1:0]        data_dly;
	integer 						col_cnt;
	integer 						row_cnt;
	integer 						timeout_cycle;
	integer 						fd;
	reg 	[7:0]					byte_buf;
	reg								frame_start;
begin
	success = 0;
	col_cnt = 0;
	row_cnt = 0;
	frame_start = 0;
	vsync_raw = 0;
	hsync_raw = 0;
	data_raw = 0;
	vsync_dly = 0;
	hsync_dly = 0;
	data_dly = 0;
	timeout_cycle = 2200 * 1125 * 20;
	total_task_count = total_task_count + 1;
	
	fd = $fopen("../Bench/tb_sgm_new_task_1.dat", "w");
	if(fd == 0) begin
		$display("@ %0t , [Left Gray] ERROR: Cannot create file!", $time);
		success = 0;
	end
	else begin
		$display("@ %0t , [Left Gray] File created, header written", $time);
		byte_buf = IMG_WIDTH[15:8];  $fwrite(fd, "%02h ", byte_buf);
		byte_buf = IMG_WIDTH[7:0];   $fwrite(fd, "%02h ", byte_buf);
		byte_buf = IMG_HEIGHT[15:8]; $fwrite(fd, "%02h ", byte_buf);
		byte_buf = IMG_HEIGHT[7:0];  $fwrite(fd, "%02h ", byte_buf);
		byte_buf = 8'h01;            $fwrite(fd, "%02h", byte_buf);
		
		fork: collect_exec
			begin : frame_collect
				while(1) begin
					@(posedge pix_clk) begin
						vsync_dly = vsync_raw;
						hsync_dly = hsync_raw;
						data_dly = data_raw;
						
						vsync_raw = l_gray_vsync;
						hsync_raw = l_gray_hsync;
						data_raw = l_gray_data;
						
						if(vsync_dly && !vsync_raw) begin
							$display("@ %0t , [Left Gray] VESA vsync FALLING EDGE detected", $time);
							frame_start = 1;
							row_cnt = 0;
							col_cnt = 0;
						end				
						
						if(hsync_dly && !frame_start) begin
							$display("@ %0t , [ERROR] [Left Gray] HSYNC IS ACTIVE BUT VSYNC NOT DETECTED!", $time);
							$display("@ %0t , [ERROR] VESA timing: vsync should occur BEFORE hsync!", $time);
							$fclose(fd);
							success = 0;
							$stop;
							disable collect_exec;
						end
						
						if(frame_start && hsync_dly) begin
							col_cnt = col_cnt + 1;
							byte_buf = data_dly[7:0]; $fwrite(fd, " %02h", byte_buf);
						end						
						
						if(!hsync_raw && hsync_dly && frame_start) begin
							col_cnt = 0;
							row_cnt = row_cnt + 1;
							$display("@ %0t , [Left Gray] Row %0d done", $time, row_cnt);
							
							if(row_cnt >= IMG_HEIGHT) begin
								$fclose(fd);
								$display("@ %0t , [Left Gray] DONE: %0d rows (counter-based stop)", $time, row_cnt);
								success = 1;
								disable collect_exec;
							end
						end						
					end
				end	
			end
			begin : timeout_monitor
				repeat(timeout_cycle) @(posedge pix_clk);
				$display("@ %0t , [Left Gray] TIMEOUT", $time);
				if(fd != 0) $fclose(fd);
				success = 0;
				disable collect_exec;
			end
		join
		$display("@ %0t , [Left Gray] %s", $time, success ? "PASS" : "FAIL");
	end
end
endtask

task collect_right_gray;
	output 	reg 					success;
	reg                             vsync_raw;
	reg                             hsync_raw;
	reg     [GRAY_WIDTH-1:0]        data_raw;
	reg                             vsync_dly;
	reg                             hsync_dly;
	reg     [GRAY_WIDTH-1:0]        data_dly;
	integer 						col_cnt;
	integer 						row_cnt;
	integer 						timeout_cycle;
	integer 						fd;
	reg 	[7:0]					byte_buf;
	reg								frame_start;
begin
	success = 0;
	col_cnt = 0;
	row_cnt = 0;
	frame_start = 0;
	vsync_raw = 0;
	hsync_raw = 0;
	data_raw = 0;
	vsync_dly = 0;
	hsync_dly = 0;
	data_dly = 0;
	timeout_cycle = 2200 * 1125 * 20;
	total_task_count = total_task_count + 1;
	
	fd = $fopen("../Bench/tb_sgm_new_task_2.dat", "w");
	if(fd == 0) begin
		$display("@ %0t , [Right Gray] ERROR: Cannot create file!", $time);
		success = 0;
	end
	else begin
		$display("@ %0t , [Right Gray] File created, header written", $time);
		byte_buf = IMG_WIDTH[15:8];  $fwrite(fd, "%02h ", byte_buf);
		byte_buf = IMG_WIDTH[7:0];   $fwrite(fd, "%02h ", byte_buf);
		byte_buf = IMG_HEIGHT[15:8]; $fwrite(fd, "%02h ", byte_buf);
		byte_buf = IMG_HEIGHT[7:0];  $fwrite(fd, "%02h ", byte_buf);
		byte_buf = 8'h01;            $fwrite(fd, "%02h", byte_buf);
		
		fork: collect_exec
			begin : frame_collect
				while(1) begin
					@(posedge pix_clk) begin
						vsync_dly = vsync_raw;
						hsync_dly = hsync_raw;
						data_dly = data_raw;
						
						vsync_raw = r_gray_vsync;
						hsync_raw = r_gray_hsync;
						data_raw = r_gray_data;
						
						if(vsync_dly && !vsync_raw) begin
							$display("@ %0t , [Right Gray] VESA vsync FALLING EDGE detected", $time);
							frame_start = 1;
							row_cnt = 0;
							col_cnt = 0;
						end				
						
						if(hsync_dly && !frame_start) begin
							$display("@ %0t , [ERROR] [Right Gray] HSYNC IS ACTIVE BUT VSYNC NOT DETECTED!", $time);
							$display("@ %0t , [ERROR] VESA timing: vsync should occur BEFORE hsync!", $time);
							$fclose(fd);
							success = 0;
							$stop;
							disable collect_exec;
						end
						
						if(frame_start && hsync_dly) begin
							col_cnt = col_cnt + 1;
							byte_buf = data_dly[7:0]; $fwrite(fd, " %02h", byte_buf);
						end						
						
						if(!hsync_raw && hsync_dly && frame_start) begin
							col_cnt = 0;
							row_cnt = row_cnt + 1;
							
							if(row_cnt >= IMG_HEIGHT) begin
								$fclose(fd);
								$display("@ %0t , [Right Gray] DONE: %0d rows (counter-based stop)", $time, row_cnt);
								success = 1;
								disable collect_exec;
							end
						end						
					end
				end	
			end
			begin : timeout_monitor
				repeat(timeout_cycle) @(posedge pix_clk);
				$display("@ %0t , [Right Gray] TIMEOUT", $time);
				if(fd != 0) $fclose(fd);
				success = 0;
				disable collect_exec;
			end
		join
		$display("@ %0t , [Right Gray] %s", $time, success ? "PASS" : "FAIL");
	end
end
endtask

//=============================================================================
//                   中间数据采集任务 (Pipeline Stage 4/10/11)
//=============================================================================

// ----------------------------------------------------------
// 任务6: collect_hamming_dist
// 功能: 采集 Stage 4 输出的汉明距离 hamming_dist[0:95]
// 触发: pipeline_dly_chain[4] (sgm_new_3)
// 文件: tb_sgm_new_task_6.dat (二进制格式)
// 格式: 5-byte头(W_MSB,W_LSB,H_MSB,H_LSB,TYPE=0x05)
//        + 96×8bit/pixel, 行优先
// ----------------------------------------------------------
task collect_hamming_dist;
    output  reg                     success;
    reg                             vsync_raw;
    reg                             href_raw;
    reg                             vsync_dly;
    reg                             href_dly;
    integer                         col_cnt;
    integer                         row_cnt;
    integer                         timeout_cycle;
    integer                         fd;
    integer                         d;
    reg                             frame_start;
begin
    success = 0;
    col_cnt = 0;
    row_cnt = 0;
    frame_start = 0;
    vsync_raw = 0;
    href_raw = 0;
    vsync_dly = 0;
    href_dly = 0;
    timeout_cycle = 2200 * 1125 * 20;
    total_task_count = total_task_count + 1;

    fd = $fopen("../Bench/tb_sgm_new_task_6.dat", "wb");
    if(fd == 0) begin
        $display("@ %0t , [HammingDist] ERROR: Cannot create file!", $time);
        success = 0;
    end
    else begin
        $display("@ %0t , [HammingDist] File created, binary header written", $time);
        // 5-byte binary header: W_MSB, W_LSB, H_MSB, H_LSB, TYPE=0x05
        $fwrite(fd, "%c%c%c%c%c", IMG_WIDTH[15:8], IMG_WIDTH[7:0],
                IMG_HEIGHT[15:8], IMG_HEIGHT[7:0], 8'h05);

        fork: collect_exec
            begin : frame_collect
                while(1) begin
                    @(posedge sgm_clk) begin
                        vsync_dly = vsync_raw;
                        href_dly = href_raw;

                        vsync_raw = u_sgm_new.vsync_delay_chain[4];
                        href_raw  = u_sgm_new.pipeline_dly_chain[4];

                        if(!vsync_dly && vsync_raw) begin
                            $display("@ %0t , [HammingDist] vsync RISING EDGE", $time);
                            frame_start = 1;
                        end

                        if(href_dly && !frame_start) begin
                            $display("@ %0t , [ERROR] [HammingDist] HREF ACTIVE BEFORE VSYNC!", $time);
                            $fclose(fd);
                            success = 0;
                            $stop;
                            disable collect_exec;
                        end

                        if(frame_start && href_dly) begin
                            col_cnt = col_cnt + 1;
                            for(d=0; d<MAX_MATCH_DEPTH; d=d+1) begin
                                $fwrite(fd, "%c", u_sgm_new.hamming_dist[d]);
                            end
                        end

                        if(!href_raw && href_dly && frame_start) begin
                            col_cnt = 0;
                            row_cnt = row_cnt + 1;
                        end

                        if(vsync_dly && !vsync_raw && frame_start) begin
                            $fclose(fd);
                            $display("@ %0t , [HammingDist] DONE: %0d rows x %0d cols",
                                     $time, row_cnt, col_cnt);
                            success = 1;
                            disable collect_exec;
                        end
                    end
                end
            end
            begin : timeout_monitor
                repeat(timeout_cycle) @(posedge sgm_clk);
                $display("@ %0t , [HammingDist] TIMEOUT", $time);
                if(fd != 0) $fclose(fd);
                success = 0;
                disable collect_exec;
            end
        join
        $display("@ %0t , [HammingDist] %s", $time, success ? "PASS" : "FAIL");
    end
end
endtask





//=============================================================================
//                           六、DUT层级实例化
//=============================================================================
//=============================================================================
// 层级1: AXI存储器模型
//=============================================================================
axi_mem_test_module#(
	.AXI_ADDR_WIDTH         (AXI_ADDR_WIDTH     ),
	.AXI_DATA_WIDTH         (AXI_DATA_WIDTH     ),
	.AXI_ID_WIDTH           (AXI_ID_WIDTH       ),
	.AXI_LEN_WIDTH          (AXI_LEN_WIDTH      ),
	.DDR_DATA_MASK_WIDTH    (DDR_DATA_MASK_WIDTH),
	.DATA_BACKPRESSURE_EN   (1'b0               ),
	.MEM_READY_DLY_CYCLES   (100                ),
	.AXI_TRADE_BUFFER_DEPTH (16					),
	.MEM_ADDRESS_WIDTH      (20                 ),
	.MEM_UNIT_WIDTH         (32                 ),
	.MEM_MIN_DATA_DELAY     (3                  ),
	.MEM_MAX_DATA_DELAY     (10                 )
) u_axi_mem_test_module (
	.axi_clk                (axi_clk),
	.rst_n                  (rst_n),
	.mem_ready              (mem_ready),
	.araddr                 (disp_araddr),
	.ar_id                  (disp_ar_id),
	.ar_len                 (disp_ar_len),
	.araddr_valid           (disp_araddr_valid),
	.araddr_ready           (disp_araddr_ready),
	.awaddr                 (28'd0),
	.aw_id                  (4'd0),
	.aw_len                 (4'd0),
	.awaddr_valid           (1'b0),
	.awaddr_ready           (),
	.wr_data                (256'd0),
	.wstrb                  (32'd0),
	.wr_data_ready          (),
	.wr_id                  (),
	.wr_data_last           (),
	.rd_data                (disp_rd_data),
	.rd_data_valid          (disp_rd_data_valid),
	.rd_id                  (disp_rd_id),
	.rd_data_last           (disp_rd_data_last)
);

//=============================================================================
// 层级2: 双路像素FIFO
//=============================================================================
drm_fifo_256b_8d u_cmr1_pix_fifo (
	.wr_clk                 (axi_clk),
	.wr_rst                 (!rst_n),
	.wr_en                  (cmr_1_pix_fifo_wr_en),
	.wr_data                (cmr_1_pix_fifo_wr_data),
	.wr_full                (),
	.wr_water_level         (cmr_1_pix_fifo_wr_wl),
	.almost_full            (),
	.rd_clk                 (pix_clk),
	.rd_rst                 (!rst_n),
	.rd_en                  (cmr_1_pix_fifo_rd_en),
	.rd_data                (cmr_1_pix_fifo_rd_data),
	.rd_empty               (cmr_1_pix_fifo_empty),
	.almost_empty           ()
);

drm_fifo_256b_8d u_cmr2_pix_fifo (
	.wr_clk                 (axi_clk),
	.wr_rst                 (!rst_n),
	.wr_en                  (cmr_2_pix_fifo_wr_en),
	.wr_data                (cmr_2_pix_fifo_wr_data),
	.wr_full                (),
	.wr_water_level         (cmr_2_pix_fifo_wr_wl),
	.almost_full            (),
	.rd_clk                 (pix_clk),
	.rd_rst                 (!rst_n),
	.rd_en                  (cmr_2_pix_fifo_rd_en),
	.rd_data                (cmr_2_pix_fifo_rd_data),
	.rd_empty               (cmr_2_pix_fifo_empty),
	.almost_empty           ()
);

//=============================================================================
// 层级3: 双目图像采集与显示控制
//=============================================================================
sgm_data_engine#(
	.H_VALID                (IMG_WIDTH),
	.V_VALID                (IMG_HEIGHT),
	.AXI_ADDR_WIDTH         (AXI_ADDR_WIDTH),
	.AXI_DATA_WIDTH         (AXI_DATA_WIDTH),
	.AXI_ID_WIDTH           (AXI_ID_WIDTH),
	.AXI_LEN_WIDTH          (AXI_LEN_WIDTH)
) u_sgm_data_engine (
	.rst_n                  (rst_n),
	.pix_clk                (pix_clk),
	.cmr_1_pix_fifo_wr_wl   (cmr_1_pix_fifo_wr_wl[7:0]),
	.cmr_2_pix_fifo_wr_wl   (cmr_2_pix_fifo_wr_wl[7:0]),
	.camera_1_rd_de         (!cmr_1_pix_fifo_empty),
	.camera_1_rd_data       (cmr_1_pix_fifo_rd_data),
	.camera_1_rd_req        (cmr_1_pix_fifo_rd_en),
	.camera_2_rd_de         (!cmr_2_pix_fifo_empty),
	.camera_2_rd_data       (cmr_2_pix_fifo_rd_data),
	.camera_2_rd_req        (cmr_2_pix_fifo_rd_en),
	.vsync                  (disp_vsync),
	.href                   (disp_href),
	.l_r_chn                (l_disp_r_chn),
	.l_g_chn                (l_disp_g_chn),
	.l_b_chn                (l_disp_b_chn),
	.r_r_chn                (r_disp_r_chn),
	.r_g_chn                (r_disp_g_chn),
	.r_b_chn                (r_disp_b_chn),
	.cmr_1_rd_buf_ofst      (RD_BUFFER_0_OFFSET),
	.cmr_2_rd_buf_ofst      (RD_BUFFER_1_OFFSET),
	.axi_clk                (axi_clk),
	.axi_ar_id              (disp_ar_id),
	.axi_ar_len             (disp_ar_len),
	.axi_araddr             (disp_araddr),
	.axi_araddr_valid       (disp_araddr_valid),
	.axi_araddr_ready       (disp_araddr_ready),
	.axi_rlast 				(disp_rd_data_last),
	.axi_rd_id 				(disp_rd_id)
);

//=============================================================================
// 层级4: RGB转灰度
//=============================================================================
rgb2gray u_rgb2gray_left (
	.clk                    (pix_clk),
	.rst_n                  (rst_n),
	.per_vga_vsync          (disp_vsync),
	.per_vga_hsync          (disp_href),
	.per_vga_r              (l_disp_r_chn),
	.per_vga_g              (l_disp_g_chn),
	.per_vga_b              (l_disp_b_chn),
	.post_vga_vsync         (l_gray_vsync),
	.post_vga_hsync         (l_gray_hsync),
	.post_vga_gray          (l_gray_data)
);

rgb2gray u_rgb2gray_right (
	.clk                    (pix_clk),
	.rst_n                  (rst_n),
	.per_vga_vsync          (disp_vsync),
	.per_vga_hsync          (disp_href),
	.per_vga_r              (r_disp_r_chn),
	.per_vga_g              (r_disp_g_chn),
	.per_vga_b              (r_disp_b_chn),
	.post_vga_vsync         (r_gray_vsync),
	.post_vga_hsync         (r_gray_hsync),
	.post_vga_gray          (r_gray_data)
);

//=============================================================================
// 层级5: Census特征变换
//=============================================================================
census_5x5#(
	.IMAGE_WIDTH            (IMG_WIDTH),
	.IMAGE_HEIGHT           (IMG_HEIGHT)
) u_census_5x5_left (
	.pix_clk                (pix_clk),
	.rst_n                  (rst_n),
	.per_vga_vsync          (l_gray_vsync),
	.per_vga_href           (l_gray_hsync),
	.per_vga_gray           (l_gray_data),
	.census                 (l_census_data),
	.census_vsync           (l_census_vsync),
	.census_href            (l_census_href)
);

census_5x5#(
	.IMAGE_WIDTH            (IMG_WIDTH),
	.IMAGE_HEIGHT           (IMG_HEIGHT)
) u_census_5x5_right (
	.pix_clk                (pix_clk),
	.rst_n                  (rst_n),
	.per_vga_vsync          (r_gray_vsync),
	.per_vga_href           (r_gray_hsync),
	.per_vga_gray           (r_gray_data),
	.census                 (r_census_data),
	.census_vsync           (r_census_vsync),
	.census_href            (r_census_href)
);

//=============================================================================
// 层级5.5: Census → SGM 间 FIFO 缓冲层
//   - cmr_census_fifo ×2 : 左右目 Census 数据行缓冲
//   - sgm_vsync_fifo  ×1 : 帧同步令牌 FIFO
//=============================================================================

cmr_census_fifo u_cmr1_census_fifo (
	.wr_clk         (pix_clk                ),
	.wr_rst         (!rst_n                 ),
	.wr_en          (l_census_href          ),
	.wr_data        (l_census_data          ),
	.wr_full        (                       ),
	.almost_full    (                       ),
	.rd_clk         (sgm_clk                ),
	.rd_rst         (!rst_n                 ),
	.rd_en          (cmr_census_fifo_rd_en  ),
	.rd_data        (cmr1_census_fifo_dout  ),
	.rd_empty       (cmr1_line_fifo_empty   ),
	.almost_empty   (                       )
);

cmr_census_fifo u_cmr2_census_fifo (
	.wr_clk         (pix_clk                ),
	.wr_rst         (!rst_n                 ),
	.wr_en          (r_census_href          ),
	.wr_data        (r_census_data          ),
	.wr_full        (                       ),
	.almost_full    (                       ),
	.rd_clk         (sgm_clk                ),
	.rd_rst         (!rst_n                 ),
	.rd_en          (cmr_census_fifo_rd_en  ),
	.rd_data        (cmr2_census_fifo_dout  ),
	.rd_empty       (cmr2_line_fifo_empty   ),
	.almost_empty   (                       )
);

sgm_vsync_fifo u_sgm_vsync_fifo (
	.wr_data        (1'b1                       ),
	.wr_en          (vsync_fifo_wr_en           ),
	.wr_clk         (pix_clk                    ),
	.full           (                           ),
	.wr_rst         (!rst_n                     ),
	.almost_full    (                           ),
	.rd_data        (                           ),
	.rd_en          (cmr_vsync_fifo_rd_en       ),
	.rd_clk         (sgm_clk                    ),
	.empty          (cmr_vsync_fifo_empty       ),
	.rd_rst         (!rst_n                     ),
	.almost_empty   (                           )
);

//=============================================================================
// 层级6: SGM半全局匹配 (sgm_new_3)
//=============================================================================
sgm_new_3#(
	.IMG_WIDTH              (IMG_WIDTH              ),
	.IMG_HEIGHT             (IMG_HEIGHT             ),
	.MAX_MATCH_DEPTH        (MAX_MATCH_DEPTH        ),
	.CENSUS_WIDTH           (CENSUS_WIDTH           ),
	.DISPARITY_WIDTH        (DISPARITY_WIDTH        ),
	.CONFIDENCE_WIDTH       (8                      ),
	.CONFIDENCE_THRE        (1                      ),
	.SGM_P1                 (SGM_P1                 ),
	.SGM_P2                 (SGM_P2                 ),
	.SGM_LR_WIDTH           (SGM_LR_WIDTH           ),
	.SGM_INVALID_COST       (24                     )
) u_sgm_new (
	.sgm_clk                (sgm_clk                ),
	.rst_n                  (rst_n                  ),
	.cmr_vsync_fifo_empty   (cmr_vsync_fifo_empty   ),
	.cmr1_line_fifo_empty   (cmr1_line_fifo_empty   ),
	.cmr1_census            (cmr1_census_fifo_dout  ),
	.cmr2_line_fifo_empty   (cmr2_line_fifo_empty   ),
	.cmr2_census            (cmr2_census_fifo_dout  ),
	.cmr_vsync_fifo_rd_en   (cmr_vsync_fifo_rd_en   ),
	.cmr_census_fifo_rd_en  (cmr_census_fifo_rd_en  ),
	.disparity_vsync        (disparity_vsync        ),
	.disparity_href         (disparity_href         ),
	.disparity              (disparity              )
);

//=============================================================================
//                           七、主测试流程
//=============================================================================
initial begin
	// -------------------------- 初始化 --------------------------
	rst_n = 0;
	$display("@ %0t , [Verification] Reset asserted", $time);
	
	total_task_count = 0;
	passed_task_count = 0;
	failed_task_count = 0;
	passed_idx = 0;
	failed_idx = 0;
	frame_cnt = 0;
	
	$display("\n===== SGM DATA COLLECTION START =====\n");

	// =====================================================================
	//           Standard Verilog Fork: 5检测任务 + 1控制线程（共6线程并行）
	// =====================================================================
	$display("@ %0t , [INFO] Fork 5 detection tasks + 1 control thread", $time);
	$display("@ %0t , [INFO] All tasks IDLE waiting for vsync BEFORE reset release", $time);

	fork
		// -------------------------- 任务1-5: 并行检测（立刻启动）
		begin
			collect_left_gray(task_success_flag);
			task_result_record(1, task_success_flag);
		end
		begin
			collect_right_gray(task_success_flag);
			task_result_record(2, task_success_flag);
		end
		begin
			collect_left_census(task_success_flag);
			task_result_record(3, task_success_flag);
		end
		begin
			collect_right_census(task_success_flag);
			task_result_record(4, task_success_flag);
		end
		begin
			collect_disparity(task_success_flag);
			task_result_record(5, task_success_flag);
		end
		// -------------------------- 线程6: 采集汉明距离 (Stage 4)
		begin
			collect_hamming_dist(task_success_flag);
			task_result_record(6, task_success_flag);
		end
		// -------------------------- 线程7: 复位释放 + 超时控制
		begin
			#(RST_HOLD_NS * 1000);
			rst_n = 1;
			$display("@ %0t , [Verification] Reset released, DUT start running", $time);
			
			wait(passed_task_count + failed_task_count == 6);
			$display("\n@ %0t , [INFO] All 6 data collection tasks completed", $time);
		end
	join

	// =====================================================================
	//                          文件验证
	// =====================================================================
	$display("\n@ %0t , [Verification] Checking generated data files...", $time);
	verify_data_file(1, "Left Gray");
	verify_data_file(2, "Right Gray");
	verify_data_file(3, "Left Census");
	verify_data_file(4, "Right Census");
	verify_data_file(5, "Disparity Map");

	// 二进制中间数据验证
	verify_binary_file(6, "Hamming Dist",
		IMG_WIDTH * IMG_HEIGHT * MAX_MATCH_DEPTH * 1 + 5);

	// =====================================================================
	//                              测试结束
	// =====================================================================
	print_test_report();
	
	$display(" ");
	if(failed_task_count == 0) begin
		$display("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@");
		$display("@@   ALL 6 DATA FILES GENERATED SUCCESSFULLY!             @@");
		$display("@@                                                        @@");
		$display("@@   Task 1: tb_sgm_new_task_1.dat  (Left Gray)           @@");
		$display("@@   Task 2: tb_sgm_new_task_2.dat  (Right Gray)          @@");
		$display("@@   Task 3: tb_sgm_new_task_3.dat  (Left Census)         @@");
		$display("@@   Task 4: tb_sgm_new_task_4.dat  (Right Census)        @@");
		$display("@@   Task 5: tb_sgm_new_task_5.dat  (Disparity Map)       @@");
		$display("@@   Task 6: tb_sgm_new_task_6.dat  (Hamming Dist)        @@");
		$display("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@");
	end
	else begin
		$display("##########################################################");
		$display("##   SOME DATA RECORDING TASKS FAILED!                  ##");
		$display("##   Please check timeout or vsync/href signals         ##");
		$display("##########################################################");
	end
	$display("@ %0t , [INFO] Simulation stopping to prevent .dat overwrite", $time);
	$finish;
end

//=============================================================================
//                           八、辅助函数
//=============================================================================
task verify_data_file;
	input integer task_id;
	input [8*32:1] name;
	integer fd;
	integer file_size;
	integer byte_count;
	reg [7:0] dummy;
begin
	fd = $fopen($sformatf("../Bench/tb_sgm_new_task_%0d.dat", task_id), "r");
	if(fd == 0) begin
		$display("  [FAIL] %s: File NOT created!", name);
		failed_task_count = failed_task_count + 1;
	end
	else begin
		byte_count = 0;
		while($fscanf(fd, "%02h", dummy) != -1) begin
			byte_count = byte_count + 1;
		end
		$fclose(fd);
		$display("  [OK] %s: %0d bytes written", name, byte_count);
	end
end
endtask

// ----------------------------------------------------------
// verify_binary_file - 验证二进制文件存在性和大小
// ----------------------------------------------------------
task verify_binary_file;
	input integer task_id;
	input [8*32:1] name;
	input integer expected_bytes;
	integer fd;
	integer byte_count;
	integer code;
	reg [7:0] byte_buf;
begin
	fd = $fopen($sformatf("../Bench/tb_sgm_new_task_%0d.dat", task_id), "rb");
	if(fd == 0) begin
		$display("  [FAIL] Binary Task %0d (%s): File NOT created!", task_id, name);
		failed_task_count = failed_task_count + 1;
	end
	else begin
		byte_count = 0;
		code = $fscanf(fd, "%c", byte_buf);
		while(code == 1) begin
			byte_count = byte_count + 1;
			code = $fscanf(fd, "%c", byte_buf);
		end
		$fclose(fd);
		if(byte_count == expected_bytes) begin
			$display("  [OK] Binary %s: %0d bytes (expected %0d)", name, byte_count, expected_bytes);
		end
		else begin
			$display("  [WARN] Binary %s: %0d bytes (expected %0d)", name, byte_count, expected_bytes);
		end
	end
end
endtask

task task_result_record;
	input integer task_id;
	input reg success;
begin
	if(success) begin
		passed_task_count = passed_task_count + 1;
		passed_task_id[passed_idx] = task_id;
		passed_idx = passed_idx + 1;
	end
	else begin
		failed_task_count = failed_task_count + 1;
		failed_task_id[failed_idx] = task_id;
		failed_idx = failed_idx + 1;
	end
end
endtask

task print_test_report;
begin
	$display("\n===== SGM TEST REPORT =====");
	$display("  Total Tasks:   %0d", total_task_count);
	$display("  Passed:        %0d", passed_task_count);
	$display("  Failed:        %0d", failed_task_count);
	$display("  Pass Rate:     %0.1f%%", (passed_task_count*100.0)/total_task_count);
	
	if(passed_idx > 0) begin
		$write("  Pass ID:       ");
		for(i=0;i<passed_idx;i=i+1) $write("%0d ", passed_task_id[i]);
		$display("");
	end
	if(failed_idx > 0) begin
		$write("  Fail ID:       ");
		for(i=0;i<failed_idx;i=i+1) $write("%0d ", failed_task_id[i]);
		$display("");
	end
	$display("===========================\n");
end
endtask

//=============================================================================
//                           九、信号监测模块
//=============================================================================
always@(posedge pix_clk) begin
	if(cmr_1_pix_fifo_empty && cmr_1_pix_fifo_rd_en) begin
		$display("@ %0t , [ERROR] Camera 1 's pixel data FIFO was empty during displaying!",$time);
		$stop;
	end

	if(cmr_2_pix_fifo_empty && cmr_2_pix_fifo_rd_en) begin
		$display("@ %0t , [ERROR] Camera 2 's pixel data FIFO was empty during displaying!",$time);
		$stop;
	end
end 

reg [9:0] disparity_col_cnt;
reg disparity_vsync_dly;
reg disparity_href_dly;
always@(posedge sgm_clk) begin
	disparity_vsync_dly <= disparity_vsync;
	disparity_href_dly <= disparity_href;
	if(disparity_vsync && !disparity_vsync_dly) begin
		disparity_col_cnt <= 0;
	end
	else if(disparity_href) begin
		disparity_col_cnt <= disparity_col_cnt + 1'b1;
	end
	else begin
		disparity_col_cnt <= 0;
	end

	if(!disparity_href && disparity_href_dly) begin
		if(disparity_col_cnt > IMG_WIDTH) begin
			$display("@ %0t , [ERROR] SGM module's href last too long for %0d cycles",$time,disparity_col_cnt);
			$stop;
		end
		else if(disparity_col_cnt < IMG_WIDTH) begin
			$display("@ %0t , [ERROR] SGM module's href last too short for %0d cycles",$time,disparity_col_cnt);
			$stop;
		end
	end
end
endmodule
