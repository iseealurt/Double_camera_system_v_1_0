`timescale 1ns / 1ps

module tb_ov5640_config();

// 时钟和复位信号
reg         clk;
reg         rst_n;

// 用户接口信号
reg         wr_valid;
wire        wr_ready;
reg  [15:0] wr_addr;
reg  [7:0]  wr_data;

reg         rd_valid;
wire        rd_ready;
reg  [15:0] rd_addr;
wire [7:0]  rd_data;

// 摄像头初始化信号
reg         cmr_init_en;
wire        cmr_init_done;

// I2C接口信号
wire        i2c_scl;
wire        i2c_sda;
wire        i2c_busy;

// 内部信号监测
wire [6:0]  cur_state;
wire        init_start;
wire [23:0] init_data;
wire        i2c_end;
wire        i2c_rw_ctrl;
wire        i2c_trans_en;

// 时钟参数
parameter CLK_PERIOD = 10; // 100MHz

// 实例化被测模块
ov5640_config #(
    .SYS_CLK_FREQ_HZ  (100_000_000),
    .DEVICE_ID        (7'h3C),
    .I2C_CLK_FREQ_HZ  (400_000)
) uut (
    .clk            (clk),
    .rst_n          (rst_n),
    
    .wr_valid       (wr_valid),
    .wr_ready       (wr_ready),
    .wr_addr        (wr_addr),
    .wr_data        (wr_data),
    
    .rd_valid       (rd_valid),
    .rd_ready       (rd_ready),
    .rd_addr        (rd_addr),
    .rd_data        (rd_data),
    
    .cmr_init_en    (cmr_init_en),
    .cmr_init_done  (cmr_init_done),
    
    .i2c_scl        (i2c_scl),
    .i2c_sda        (i2c_sda),
    .i2c_busy       (i2c_busy)
);

// 时钟生成
always #(CLK_PERIOD/2) clk = ~clk;

// 内部信号连接用于监测
assign cur_state = uut.cur_state;
assign init_start = uut.init_start;
assign init_data = uut.init_data;
assign i2c_end = uut.i2c_end;
assign i2c_rw_ctrl = uut.i2c_rw_ctrl;
assign i2c_trans_en = uut.i2c_trans_en;


// 测试任务：等待N个时钟周期
task wait_cycles;
    input [31:0] cycles;
    begin
        repeat(cycles) @(posedge clk);
    end
endtask
pulldown(i2c_sda);
// 测试序列
initial begin
    // 初始化信号
	
    initialize();
    
    // 测试1：基本初始化功能
    $display("=== 测试1：摄像头初始化 ===");
    test_camera_init();
    

    // 完成测试
    wait_cycles(100);
    $display("=== 所有测试完成 ===");
    $finish;
end

// 初始化任务
task initialize;
    begin
		
        clk = 0;
        rst_n = 0;
        wr_valid = 0;
        wr_addr = 16'h0;
        wr_data = 8'h0;
        rd_valid = 0;
        rd_addr = 16'h0;
        cmr_init_en = 0;
        
        // 复位
        wait_cycles(5);
        rst_n = 1;
        wait_cycles(10);
        
        $display("初始化完成");
    end
endtask

// 测试摄像头初始化
task test_camera_init;
    begin
        $display("开始摄像头初始化测试...");
        
        // 使能初始化
        cmr_init_en = 1;
        @(posedge clk);
        
        // 等待初始化开始
        
        // 监控初始化过程
   
        $display("摄像头初始化测试完成");
    end
endtask





// 测试初始化期间的读写操作
task test_read_write_during_init;
    begin
        $display("在初始化期间尝试读写操作...");
        
        // 在初始化过程中尝试写操作
        @(posedge clk);
        wr_valid = 1;
        wr_addr = 16'h1234;
        wr_data = 8'hAA;
        
        wait_cycles(5);
        
        // 检查写操作是否被正确处理（应该被忽略或等待）
        if (wr_ready) begin
            $display("警告：初始化期间写操作被接受");
        end else begin
            $display("正常：初始化期间写操作被挂起");
        end
        
        // 在初始化过程中尝试读操作
        rd_valid = 1;
        rd_addr = 16'h5678;
        
        wait_cycles(5);
        
        // 检查读操作是否被正确处理
        if (rd_ready) begin
            $display("警告：初始化期间读操作被接受");
        end else begin
            $display("正常：初始化期间读操作被挂起");
        end
        
        // 清除读写信号
        wr_valid = 0;
        rd_valid = 0;
    end
endtask



// 超时保护
initial begin
    #5_000_000; // 5ms超时
    $display("错误：测试超时！");
    $finish;
end

endmodule