//============================================================================
// Testbench Template for FPGA Module Verification
// Description: 标准化模块验证平台模板
//============================================================================
`timescale 1ns/1ps

module bench_template();

//=============================================================================
//                           一、参数定义区
//=============================================================================
parameter 	CLK_PERIOD_PS			= 	6734;				// 默认148.5MHz
parameter 	RST_HOLD_NS				= 	100;				// 复位保持时间
parameter 	TEST_INTERVAL_CYCLES	= 	50;					// 测试间隔
parameter 	DEFAULT_TIMEOUT			= 	10000;				// 默认超时
parameter 	MAX_TASK_NUM			= 	64;					// 最大任务数

// -------------------------- 待测模块参数 --------------------------
// 在此添加DUT参数
// parameter DUT_PARAM = VALUE;

//=============================================================================
//                           二、信号定义区
//=============================================================================
reg 							clk;
reg 							rst_n;

// -------------------------- DUT输入输出 --------------------------
// 在此声明DUT输入输出信号
// 示例:
// reg     [7:0]       din;
// wire    [7:0]       dout;
// wire                valid;

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

//=============================================================================
//                           四、时钟复位
//=============================================================================
// GTP_GRS GRS_INST (.GRS_N(rst_n));  // 紫光全局复位IP（可选）

initial begin
	clk = 0;
	forever #(CLK_PERIOD_PS/2) clk = ~ clk;
end

//=============================================================================
//                           五、通用任务框架（核心！）
//=============================================================================
//=============================================================================
// Task: run_test
// Description: 所有测试任务的通用骨架，只需专注实现test_logic内部逻辑
// 
// 使用方法：
//   1. 调用时传入task_id和超时
//   2. 在test_logic_begin和test_logic_end之间编写测试代码
//   3. 测试通过时设置success = 1
//
// 示例：
//   run_test(1, 1000, task_success_flag, begin
//       repeat(10) @(posedge clk);       // 测试代码
//       if(dout == expected) success = 1;    // 判据
//   end);
//=============================================================================
task run_test;
	input 	integer 				task_id;
	input 	integer 				timeout;
	output 	reg 					success;
	
	integer i;
begin
	success = 0;
	$display("@ %0t , [Task %0d] Start", $time, task_id);
	
	fork: task_exec
		begin
			// --------------------------
			// 用户测试逻辑在此执行
			// --------------------------;
			disable task_exec;
		end
		begin
			repeat(timeout) @(posedge clk);
			$display("@ %0t , [Task %0d] *** TIMEOUT ***", $time, task_id);
			success = 0;
			disable task_exec;
		end
	join
	
	if(success)
		$display("@ %0t , [Task %0d] PASS", $time, task_id);
	else
		$display("@ %0t , [Task %0d] FAIL", $time, task_id);
end
endtask

//=============================================================================
//                           六、DUT实例化
//=============================================================================
/*
module_name #(
	.PARAM1(VALUE1)
) u_dut (
	.clk        (clk),
	.rst_n      (rst_n),
	.din        (din),
	.dout       (dout)
);
*/

//=============================================================================
//                           七、主测试流程
//=============================================================================
initial begin
	// -------------------------- 初始化 --------------------------
	if($value$plusargs("DUMP_WAVE=%d", dump_wave_en) && dump_wave_en) begin
		$dumpfile("waveform.vcd");
		$dumpvars(0, bench_template);
	end

	rst_n = 0;
	#(RST_HOLD_NS * 1000);
	rst_n = 1;
	
	total_task_count = 0;
	passed_task_count = 0;
	failed_task_count = 0;
	passed_idx = 0;
	failed_idx = 0;
	repeat(20) @(posedge clk);

	$display("\n===== TEST START =====\n");

	// =====================================================================
	//                        在此添加测试任务
	//               复制下面模板，修改任务名和测试逻辑即可
	// =====================================================================

	// -------------------- Task 1: 测试项目1 --------------------
    // ===== 测试逻辑开始 =====
    repeat(100) @(posedge clk);
	total_task_count = total_task_count + 1;
	run_test(total_task_count, DEFAULT_TIMEOUT, task_success_flag);
	task_success_flag = 1;  // 设置成功标志
	// ===== 测试逻辑结束 =====
	task_result_record(total_task_count, task_success_flag);
	repeat(TEST_INTERVAL_CYCLES) @(posedge clk);

	// -------------------- Task 2: 测试项目2 --------------------
	repeat(100) @(posedge clk);
	total_task_count = total_task_count + 1;
	run_test(total_task_count, DEFAULT_TIMEOUT, task_success_flag);
	task_success_flag = 1;  // 设置成功标志
	// ===== 测试逻辑结束 =====
	task_result_record(total_task_count, task_success_flag);
	repeat(TEST_INTERVAL_CYCLES) @(posedge clk);

	// -------------------- Task 3: 测试项目3 --------------------
	repeat(100) @(posedge clk);
	total_task_count = total_task_count + 1;
	run_test(total_task_count, DEFAULT_TIMEOUT, task_success_flag);
	task_success_flag = 1;  // 设置成功标志
	// ===== 测试逻辑结束 =====
	task_result_record(total_task_count, task_success_flag);
	repeat(TEST_INTERVAL_CYCLES) @(posedge clk);
	// =====================================================================
	//                              测试结束
	// =====================================================================
	print_test_report();
	
	#10000;
	if(failed_task_count == 0) begin
		$display("\n@@@@@@@@@@@@@@@@@@@@@@@@@@");
		$display("@@    ALL TEST PASS     @@");
		$display("@@@@@@@@@@@@@@@@@@@@@@@@@@\n");
		$finish;
	end
	else begin
		$display("\n##########################");
		$display("##    TESTS FAILED!     ##");
		$display("##########################\n");
		$stop;
	end
end

//=============================================================================
//                           八、辅助函数
//=============================================================================
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
	integer i;
begin
	$display("\n===== TEST REPORT =====");
	$display("  Total:   %0d", total_task_count);
	$display("  Passed:  %0d", passed_task_count);
	$display("  Failed:  %0d", failed_task_count);
	$display("  Rate:    %0.1f%%", (passed_task_count*100.0)/total_task_count);
	
	if(passed_idx > 0) begin
		$write("  Pass ID: ");
		for(i=0;i<passed_idx;i=i+1) $write("%0d ", passed_task_id[i]);
		$display("");
	end
	if(failed_idx > 0) begin
		$write("  Fail ID: ");
		for(i=0;i<failed_idx;i=i+1) $write("%0d ", failed_task_id[i]);
		$display("");
	end
	$display("=======================\n");
end
endtask

endmodule
