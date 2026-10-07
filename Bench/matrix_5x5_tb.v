`timescale 1ps/1ps
module tb_matrix_5x5();

	//------------------------------ parameter ------------------------------
	parameter 	CLOCK_PERIOD_NS 	= 	6734				;	// 148.5MHz时钟周期
	parameter	IMG_HDISP			=	11'd640				;
	parameter	IMG_VDISP			=	11'd480				;
	parameter	DELAY_NUM			=	11'd10				;
	parameter	TEST_TIMEOUT		=	100000				;	// 测试超时周期数
	parameter	TEST_INTERVAL_CYCLES=	100					;	// 测试间隔周期数
	parameter	CYCLE_BETWEEN_ROW	=	100					;	
	//------------------------------ signal ------------------------------
	reg 							clk							;
	reg 							rst_n						;
	
	reg 							per_img_vsync				;
	reg 							per_img_href				;
	reg 			[7:0]			per_img_gray				;
	
	wire 							matrix_img_vsync			;
	wire 							matrix_img_href				;
	wire 							matrix_top_edge_flag		;
	wire 							matrix_bottom_edge_flag		;
	wire 							matrix_left_edge_flag		;
	wire 							matrix_right_edge_flag		;
	
	wire 			[7:0]			matrix_p11					;
	wire 			[7:0]			matrix_p12					;
	wire 			[7:0]			matrix_p13					;
	wire 			[7:0]			matrix_p14					;
	wire 			[7:0]			matrix_p15					;
	wire 			[7:0]			matrix_p21					;
	wire 			[7:0]			matrix_p22					;
	wire 			[7:0]			matrix_p23					;
	wire 			[7:0]			matrix_p24					;
	wire 			[7:0]			matrix_p25					;
	wire 			[7:0]			matrix_p31					;
	wire 			[7:0]			matrix_p32					;
	wire 			[7:0]			matrix_p33					;
	wire 			[7:0]			matrix_p34					;
	wire 			[7:0]			matrix_p35					;
	wire 			[7:0]			matrix_p41					;
	wire 			[7:0]			matrix_p42					;
	wire 			[7:0]			matrix_p43					;
	wire 			[7:0]			matrix_p44					;
	wire 			[7:0]			matrix_p45					;
	wire 			[7:0]			matrix_p51					;
	wire 			[7:0]			matrix_p52					;
	wire 			[7:0]			matrix_p53					;
	wire 			[7:0]			matrix_p54					;
	wire 			[7:0]			matrix_p55					;
	
	//----------------------------------------------------------------------
	// 矩阵验证专用信号和计数器
	//----------------------------------------------------------------------
	reg 	[10:0]		verify_col_cnt						;
	reg 	[10:0]		verify_row_cnt						;
	reg 				matrix_img_href_dly1				;
	reg 				matrix_img_href_dly2				;
	reg 				matrix_img_href_dly3				;
	reg 				matrix_img_vsync_dly1				;
	reg 				matrix_img_vsync_dly2				;
	wire 	[10:0]		expected_base						;
	wire 	[7:0]		expected_p11						;
	wire 	[7:0]		expected_p12						;
	wire 	[7:0]		expected_p13						;
	wire 	[7:0]		expected_p14						;
	wire 	[7:0]		expected_p15						;
	wire 	[7:0]		expected_p21						;
	wire 	[7:0]		expected_p22						;
	wire 	[7:0]		expected_p23						;
	wire 	[7:0]		expected_p24						;
	wire 	[7:0]		expected_p25						;
	wire 	[7:0]		expected_p31						;
	wire 	[7:0]		expected_p32						;
	wire 	[7:0]		expected_p33						;
	wire 	[7:0]		expected_p34						;
	wire 	[7:0]		expected_p35						;
	wire 	[7:0]		expected_p41						;
	wire 	[7:0]		expected_p42						;
	wire 	[7:0]		expected_p43						;
	wire 	[7:0]		expected_p44						;
	wire 	[7:0]		expected_p45						;
	wire 	[7:0]		expected_p51						;
	wire 	[7:0]		expected_p52						;
	wire 	[7:0]		expected_p53						;
	wire 	[7:0]		expected_p54						;
	wire 	[7:0]		expected_p55						;
	wire 				boundary_flag						;
	wire 				row1_match, row2_match, row3_match, row4_match, row5_match	;
	wire 				matrix_all_match					;
	
	// 计数器和边沿检测逻辑 - 独立模块专门处理
	always @(posedge clk or negedge rst_n) begin
		if(!rst_n) begin
			verify_col_cnt <= 11'd0;
			verify_row_cnt <= 11'd0;
			matrix_img_href_dly1 <= 1'b0;
			matrix_img_href_dly2 <= 1'b0;
			matrix_img_href_dly3 <= 1'b0;
			matrix_img_vsync_dly1 <= 1'b0;
			matrix_img_vsync_dly2 <= 1'b0;
		end
		else begin
			matrix_img_vsync_dly1 <= matrix_img_vsync;
			matrix_img_vsync_dly2 <= matrix_img_vsync_dly1;
			matrix_img_href_dly3 <= matrix_img_href_dly2;
			matrix_img_href_dly2 <= matrix_img_href_dly1;
			matrix_img_href_dly1 <= matrix_img_href;
			
			if(!matrix_img_href_dly2 && matrix_img_href_dly3) begin
				verify_col_cnt <= 11'd0;
				
			end
			else if(matrix_img_href) begin
				verify_col_cnt <= verify_col_cnt + 1'b1;
			end
			
			
			if(matrix_img_vsync_dly1 && !matrix_img_vsync_dly2) begin
				verify_row_cnt <= 11'd0;
			end
			
			else if(!matrix_img_href_dly2 && matrix_img_href_dly3) begin
				verify_row_cnt <= verify_row_cnt + 1'b1;
			end
		end
	end
	
	// 期望值计算 - 使用assign语句提前计算好
	// 注意：测试图像每一行都是从1开始独立计数，所以5行同一列的值完全相同！
	assign expected_base = verify_col_cnt;   // verify_col_cnt = 0-639
	assign expected_p33 = expected_base[7:0];
	
	// 所有行的同一列值都相同，因为每一行像素都是0-639
	assign expected_p11 = (expected_base - 2);
	assign expected_p12 = (expected_base - 1);
	assign expected_p13 = expected_base;
	assign expected_p14 = (expected_base + 1);
	assign expected_p15 = (expected_base + 2);
	
	assign expected_p21 = (expected_base - 2);
	assign expected_p22 = (expected_base - 1);
	assign expected_p23 = expected_base;
	assign expected_p24 = (expected_base + 1);
	assign expected_p25 = (expected_base + 2);
	
	assign expected_p31 = (expected_base - 2);
	assign expected_p32 = (expected_base - 1);
	assign expected_p34 = (expected_base + 1);
	assign expected_p35 = (expected_base + 2);
	
	assign expected_p41 = (expected_base - 2);
	assign expected_p42 = (expected_base - 1);
	assign expected_p43 = expected_base;
	assign expected_p44 = (expected_base + 1);
	assign expected_p45 = (expected_base + 2);
	
	assign expected_p51 = (expected_base - 2);
	assign expected_p52 = (expected_base - 1);
	assign expected_p53 = expected_base;
	assign expected_p54 = (expected_base + 1);
	assign expected_p55 = (expected_base + 2);
	
	// 边界标志计算
	assign boundary_flag = matrix_top_edge_flag || matrix_bottom_edge_flag || 
	                       matrix_left_edge_flag || matrix_right_edge_flag;
	
	// 逐行比较
	assign row1_match = (matrix_p11 == expected_p11) && (matrix_p12 == expected_p12) &&
	                    (matrix_p13 == expected_p13) && (matrix_p14 == expected_p14) &&
	                    (matrix_p15 == expected_p15);
	assign row2_match = (matrix_p21 == expected_p21) && (matrix_p22 == expected_p22) &&
	                    (matrix_p23 == expected_p23) && (matrix_p24 == expected_p24) &&
	                    (matrix_p25 == expected_p25);
	assign row3_match = (matrix_p31 == expected_p31) && (matrix_p32 == expected_p32) &&
	                    (matrix_p33 == expected_p33) && (matrix_p34 == expected_p34) &&
	                    (matrix_p35 == expected_p35);
	assign row4_match = (matrix_p41 == expected_p41) && (matrix_p42 == expected_p42) &&
	                    (matrix_p43 == expected_p43) && (matrix_p44 == expected_p44) &&
	                    (matrix_p45 == expected_p45);
	assign row5_match = (matrix_p51 == expected_p51) && (matrix_p52 == expected_p52) &&
	                    (matrix_p53 == expected_p53) && (matrix_p54 == expected_p54) &&
	                    (matrix_p55 == expected_p55);
	assign matrix_all_match = row1_match && row2_match && row3_match && row4_match && row5_match;
	
	// 测试统计变量
	integer 						total_task_count			;
	integer 						passed_task_count		;
	integer 						failed_task_count		;
	integer 						passed_task_id	[0:99]		;
	integer 						failed_task_id	[0:99]		;
	integer 						passed_idx					;
	integer 						failed_idx					;
	reg 							task_success_flag			;
	reg 							verification_done_flag		;
	reg 							verification_success_flag	;
	
	integer 						i							;
	integer 						j							;
	integer 						row							;
	integer 						col							;
	
	//------------------------------ module instantiation ------------------------------
	GTP_GRS GRS_INST (
		.GRS_N(rst_n)
	);
	
	matrix_5x5 #(
		.IMG_HDISP		(IMG_HDISP		),
		.IMG_VDISP		(IMG_VDISP		),
		.DELAY_NUM		(DELAY_NUM		)
	) uut (
		.clk					(clk					),
		.rst_n					(rst_n					),
		.per_img_vsync			(per_img_vsync			),
		.per_img_href			(per_img_href			),
		.per_img_gray			(per_img_gray			),
		.matrix_img_vsync		(matrix_img_vsync		),
		.matrix_img_href		(matrix_img_href		),
		.matrix_top_edge_flag	(matrix_top_edge_flag	),
		.matrix_bottom_edge_flag(matrix_bottom_edge_flag),
		.matrix_left_edge_flag	(matrix_left_edge_flag	),
		.matrix_right_edge_flag	(matrix_right_edge_flag	),
		.matrix_p11				(matrix_p11				),
		.matrix_p12				(matrix_p12				),
		.matrix_p13				(matrix_p13				),
		.matrix_p14				(matrix_p14				),
		.matrix_p15				(matrix_p15				),
		.matrix_p21				(matrix_p21				),
		.matrix_p22				(matrix_p22				),
		.matrix_p23				(matrix_p23				),
		.matrix_p24				(matrix_p24				),
		.matrix_p25				(matrix_p25				),
		.matrix_p31				(matrix_p31				),
		.matrix_p32				(matrix_p32				),
		.matrix_p33				(matrix_p33				),
		.matrix_p34				(matrix_p34				),
		.matrix_p35				(matrix_p35				),
		.matrix_p41				(matrix_p41				),
		.matrix_p42				(matrix_p42				),
		.matrix_p43				(matrix_p43				),
		.matrix_p44				(matrix_p44				),
		.matrix_p45				(matrix_p45				),
		.matrix_p51				(matrix_p51				),
		.matrix_p52				(matrix_p52				),
		.matrix_p53				(matrix_p53				),
		.matrix_p54				(matrix_p54				),
		.matrix_p55				(matrix_p55				)
	);
	
	//------------------------------ CLock signal ------------------------------
	initial begin
		clk = 0;
		forever #(CLOCK_PERIOD_NS/2) clk = ~clk;
	end
	
	//------------------------------ task ------------------------------
	task generate_single_frame;
		input 	integer 			task_id					;
		input 	integer 			start_value				;
		output 	reg 				success					;
		integer 					pixel_value				;
		integer 					col_cnt					;
		integer 					row_cnt					;
		reg 						matrix_img_href_dly1	;
		reg 						matrix_img_href_dly2	;
		reg 						matrix_img_vsync_dly1	;
		reg 						matrix_img_vsync_dly2	;
		reg 						matrix_img_href_dly3	;
		reg 						matrix_img_vsync_dly3	;
		integer 					timeout_threshold		;
		begin
			success = 0;
			col_cnt = 0;
			row_cnt = 0;
			matrix_img_href_dly1 = 1'b0;
			matrix_img_href_dly2 = 1'b0;
			matrix_img_vsync_dly1 = 1'b0;
			matrix_img_vsync_dly2 = 1'b0;
			matrix_img_href_dly3 = 1'b0;
			matrix_img_vsync_dly3 = 1'b0;
			timeout_threshold = (IMG_VDISP + 15) * (IMG_HDISP + CYCLE_BETWEEN_ROW);
			
			fork: frame_gen_task
				begin: frame_generate
					@(posedge clk);
					per_img_vsync = 1'b1;
					
					for (row = 0; row < IMG_VDISP; row = row + 1) begin
						repeat(CYCLE_BETWEEN_ROW/2) @(posedge clk);
						per_img_href = 1'b1;
						pixel_value = 0;
						for (col = 0; col < IMG_HDISP; col = col + 1) begin
							per_img_gray = pixel_value[7:0];
							pixel_value =  pixel_value + 1;
							@(posedge clk);
						end
						
						per_img_href = 1'b0;
						per_img_gray = 0;
						repeat(CYCLE_BETWEEN_ROW/2) @(posedge clk);
					end			
					repeat(CYCLE_BETWEEN_ROW) @(posedge clk);
					per_img_vsync = 1'b0;
				end
				
				begin: frame_monitor
					while(1) begin
						@(posedge clk) begin
							matrix_img_href_dly3 <= matrix_img_href_dly2;
							matrix_img_href_dly2 <= matrix_img_href_dly1;
							matrix_img_href_dly1 <= matrix_img_href;
							matrix_img_vsync_dly3 <= matrix_img_vsync_dly2;
							matrix_img_vsync_dly2 <= matrix_img_vsync_dly1;
							matrix_img_vsync_dly1 <= matrix_img_vsync;
							
							if(matrix_img_href) begin
								col_cnt = col_cnt + 1;
							end
							
							if(!matrix_img_href_dly2 && matrix_img_href_dly3) begin
								row_cnt = row_cnt + 1;
								if(col_cnt != IMG_HDISP) begin
									$display("@ %0t , [FrameGen] ERROR: href duration mismatch", $time);
									success = 0;
									disable frame_gen_task;
								end
								col_cnt = 0;
							end
							
							if(!matrix_img_vsync_dly2 && matrix_img_vsync_dly3) begin
								if(row_cnt == IMG_VDISP) begin
									success = 1;
									disable frame_gen_task;
								end
								else begin
									$display("@ %0t , [FrameGen] ERROR: vsync row count mismatch", $time);
									success = 0;
									disable frame_gen_task;
								end
							end
						end
					end
				end
				
				begin: timeout_monitor
					repeat(timeout_threshold) @(posedge clk);
					$display("@ %0t , [FrameGen] ERROR: Frame generation timeout", $time);
					success = 0;
					disable frame_gen_task;
				end
			join
		end
	endtask
	
	task verify_matrix_output;
		input 	integer 			task_id					;
		input 	integer 			start_value				;
		output 	reg 				success					;
		integer 					timeout_threshold		;
		begin
			success = 0;
			timeout_threshold = (IMG_VDISP + 100) * (IMG_HDISP + 2);
			
			fork: verify_matrix_task
				begin: matrix_monitor
					while(1) begin
						@(posedge clk) begin
							//----------------------------------------------------------------------
							// 所有计算在模块级别独立完成，这里只检查结果
							//----------------------------------------------------------------------
							if(matrix_img_href) begin
								//------------------------------------------------------------------
								// 边界区域只验证中心像素
								//------------------------------------------------------------------
								if(boundary_flag) begin
									if(matrix_p33 != expected_p33) begin
										$display("@ %0t , [MatrixVerify] ERROR: Boundary pixel mismatch (row=%0d, col=%0d)", 
											$time, verify_row_cnt, verify_col_cnt);
										$display("  Center pixel - Expected: %0d, Got: %0d", expected_p33, matrix_p33);
										success = 0;
										disable verify_matrix_task;
									end
								end
								//------------------------------------------------------------------
								// 非边界区域 - 使用模块级别预计算的逐行比较结果
								//------------------------------------------------------------------
								else begin
									if(!matrix_all_match) begin
										$display("@ %0t , [MatrixVerify] ERROR: Mismatch at (row=%0d, col=%0d)", 
											$time, verify_row_cnt, verify_col_cnt);
										$display("  Expected:       Actual:");
										$display("  %3d %3d %3d %3d %3d   %3d %3d %3d %3d %3d",
											expected_p11, expected_p12, expected_p13, expected_p14, expected_p15,
											matrix_p11, matrix_p12, matrix_p13, matrix_p14, matrix_p15);
										$display("  %3d %3d %3d %3d %3d   %3d %3d %3d %3d %3d",
											expected_p21, expected_p22, expected_p23, expected_p24, expected_p25,
											matrix_p21, matrix_p22, matrix_p23, matrix_p24, matrix_p25);
										$display("  %3d %3d %3d %3d %3d   %3d %3d %3d %3d %3d",
											expected_p31, expected_p32, expected_p33, expected_p34, expected_p35,
											matrix_p31, matrix_p32, matrix_p33, matrix_p34, matrix_p35);
										$display("  %3d %3d %3d %3d %3d   %3d %3d %3d %3d %3d",
											expected_p41, expected_p42, expected_p43, expected_p44, expected_p45,
											matrix_p41, matrix_p42, matrix_p43, matrix_p44, matrix_p45);
										$display("  %3d %3d %3d %3d %3d   %3d %3d %3d %3d %3d",
											expected_p51, expected_p52, expected_p53, expected_p54, expected_p55,
											matrix_p51, matrix_p52, matrix_p53, matrix_p54, matrix_p55);
										success = 0;
										disable verify_matrix_task;
									end
								end
								
							end
							
							//----------------------------------------------------------------------
							
							//----------------------------------------------------------------------
						end
					end
				end
				begin : success_judgement
					// 验证完成检测 - 使用模块级别计数器
					// 使用vsync下降沿判断一帧是否结束
					while(1) begin
						@(posedge clk) begin
							if(!matrix_img_vsync_dly1 && matrix_img_vsync_dly2) begin
								$display("@ %0t ,[Matrix Output Verify] one frame finished output",$time);
								repeat(10) begin 
									@(posedge clk); 
								end
								//等待数据清洗完成
								// 检查行数是否足够
								if(verify_row_cnt >= IMG_VDISP) begin
									success = 1;
									$display("@ %0t ,[Matrix Output Verify] task %0d succeeded",$time,task_id);
									disable verify_matrix_task;
								end
								else begin
									$display("@ %0t ,[Matrix Output Verify] error, the number of the row matched was not correct, expected: %0d , actual: %0d ",$time,IMG_VDISP,verify_row_cnt);
									success = 0;
									$display("@ %0t ,[Matrix Output Verify] task %0d failed",$time,task_id);
									disable verify_matrix_task;
								end
							end
						end	
					end
				end
				begin: timeout_monitor
					repeat(timeout_threshold) @(posedge clk);
					$display("@ %0t , [Matrix Output Verify] ERROR: Matrix output verify timeout", $time);
					success = 0;
					disable verify_matrix_task;
				end
			join
		end
	endtask
	

	
	task run_verify_matrix_output;
		input 	integer 			task_id					;
		input 	integer 			start_value				;
		output 	reg 				success					;
		begin
			verify_matrix_output(task_id, start_value, success);
		end
	endtask

	task run_single_frame_test;
		reg 						frame_gen_success		;
		reg 						matrix_verify_success	;
		begin
			$display("\n@ %0t Test 1/3: Single Frame", $time);
			fork
				run_verify_matrix_output(2, 0, matrix_verify_success);
				generate_single_frame(1, 0, frame_gen_success);			
			join
			$display("@ %0t   FrameGen: %s, MatrixVerify: %s", $time,
				frame_gen_success ? "PASS" : "FAIL",
				matrix_verify_success ? "PASS" : "FAIL");
		end
	endtask

	task run_boundary_test;
		reg 						frame_gen_success		;
		reg 						matrix_verify_success	;
		begin
			$display("\n@ %0t Test 2/3: Boundary", $time);
			fork
				run_verify_matrix_output(4, 0, matrix_verify_success);
				generate_single_frame(3, 0, frame_gen_success);
			join
			$display("@ %0t   FrameGen: %s, MatrixVerify: %s", $time,
				frame_gen_success ? "PASS" : "FAIL",
				matrix_verify_success ? "PASS" : "FAIL");
		end
	endtask

	task run_continuous_test;
		input 	integer 			frame_count				;
		reg 						frame_gen_success		;
		reg 						matrix_verify_success	;
		integer 					frame_idx				;
		reg s1;reg s2;
		begin
			$display("\n@ %0t Test 3/3: Continuous (%0d frames)", $time, frame_count);
			frame_gen_success = 1;
			matrix_verify_success = 1;
			for (frame_idx = 0; frame_idx < frame_count; frame_idx = frame_idx + 1) begin
				fork
					begin
						generate_single_frame(5, frame_idx * 100, s1);
						if(!s1) frame_gen_success = 0;
					end
					begin
						run_verify_matrix_output(6, frame_idx * 100, s2);
						if(!s2) matrix_verify_success = 0;
					end
				join
			end
			$display("@ %0t   FrameGen: %s, MatrixVerify: %s", $time,
				frame_gen_success ? "PASS" : "FAIL",
				matrix_verify_success ? "PASS" : "FAIL");
		end
	endtask
	reg frame_gen_success, matrix_verify_success;
	//------------------------------ verification ------------------------------
	initial begin
		
		
		per_img_vsync = 1'b0;
		per_img_href = 1'b0;
		per_img_gray = 8'd0;
		
		rst_n = 1'b0;
		#100000;
		rst_n = 1'b1;
		repeat(10) @(posedge clk);
		
		$display("\n========== Test Start ==========\n");
		
		run_single_frame_test();
		repeat(TEST_INTERVAL_CYCLES) @(posedge clk);
		run_boundary_test();
		repeat(TEST_INTERVAL_CYCLES) @(posedge clk);
		run_continuous_test(3);
		repeat(TEST_INTERVAL_CYCLES) @(posedge clk);
		
		$display("\n========== Test Complete ==========\n");
		
		$finish;	
	end
endmodule
