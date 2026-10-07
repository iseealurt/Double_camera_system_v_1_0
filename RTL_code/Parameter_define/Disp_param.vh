`ifdef Disp_1080P 
localparam 	H_SYNC    =   12'd44  ,   // 行同步
			H_BACK    =   12'd148 ,   // 行时序后沿
			H_LEFT    =   12'd0   ,   // 行时序左边框（通常为0）
			H_VALID   =   12'd1920,   // 行有效数据
			H_RIGHT   =   12'd0   ,   // 行时序右边框（通常为0）
			H_FRONT   =   12'd88  ,   // 行时序前沿
			H_TOTAL   =   12'd2200,   // 行扫描周期

			V_SYNC    =   12'd5   ,   // 场同步
			V_BACK    =   12'd36  ,   // 场时序后沿
			V_TOP     =   12'd0   ,   // 场时序上边框（通常为0）
			V_VALID   =   12'd1080,   // 场有效数据
			V_BOTTOM  =   12'd0   ,   // 场时序下边框（通常为0）
			V_FRONT   =   12'd4   ,   // 场时序前沿
			V_TOTAL   =   12'd1125;   // 场扫描周期
`endif