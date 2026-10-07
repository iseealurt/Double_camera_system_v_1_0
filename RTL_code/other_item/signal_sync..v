// ========== 顶层：三采样器表决 ==========
module signal_sync #(
    parameter SIG_RATE = 4'd5  // 脉冲展宽周期
)(
    input  wire sys_clk,
    input  wire rst_n,
    input  wire signal_clk,
    input  wire sig_unsync,
    output reg  sig_synced
);

    wire sig_synced_1, sig_synced_2, sig_synced_3;
    
    // 三个采样器，使用不同的时钟相位
    signal_sync_single #(
        .SIG_RATE  (SIG_RATE),
        .PHASE_SEL (0)         // 在sys_clk的上升沿采样
    ) sync_1 (
        .sys_clk    (sys_clk),
        .rst_n      (rst_n),
        .signal_clk (signal_clk),
        .sig_unsync (sig_unsync),
        .sig_synced (sig_synced_1)
    );
    
    signal_sync_single #(
        .SIG_RATE  (SIG_RATE),
        .PHASE_SEL (1)         // 延迟半个周期采样
    ) sync_2 (
        .sys_clk    (sys_clk),
        .rst_n      (rst_n),
        .signal_clk (signal_clk),
        .sig_unsync (sig_unsync),
        .sig_synced (sig_synced_2)
    );
    
    signal_sync_single #(
        .SIG_RATE  (SIG_RATE),
        .PHASE_SEL (2)         // 再延迟半个周期采样
    ) sync_3 (
        .sys_clk    (sys_clk),
        .rst_n      (rst_n),
        .signal_clk (signal_clk),
        .sig_unsync (sig_unsync),
        .sig_synced (sig_synced_3)
    );
    
    // ========== 多数表决逻辑 ==========
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            sig_synced <= 1'b0;
        end else begin
            // 三选二表决（容忍一个采样器出错）
            case ({sig_synced_1, sig_synced_2, sig_synced_3})
                3'b000, 3'b001, 3'b010, 3'b100: sig_synced <= 1'b0;
                3'b011, 3'b101, 3'b110, 3'b111: sig_synced <= 1'b1;
                default: sig_synced <= sig_synced;  // 保持
            endcase
        end
    end

endmodule


// ========== 单个采样器：标准CDC + 脉冲展宽 ==========
module signal_sync_single #(
    parameter SIG_RATE  = 4'd5,
    parameter PHASE_SEL = 0     // 0/1/2 对应不同采样相位
)(
    input  wire sys_clk,
    input  wire rst_n,
    input  wire signal_clk,
    input  wire sig_unsync,
    output reg  sig_synced
);

    // ========== Stage 1: 脉冲展宽（在signal_clk域）==========
    reg [3:0] pulse_cnt;
    reg       pulse_stretched;
    
    always @(posedge signal_clk or negedge rst_n) begin
        if (!rst_n) begin
            pulse_cnt       <= 4'd0;
            pulse_stretched <= 1'b0;
        end else begin
            if (sig_unsync) begin
                // 检测到输入脉冲，启动计数器
                pulse_cnt       <= SIG_RATE;
                pulse_stretched <= 1'b1;
            end else if (pulse_cnt > 0) begin
                // 保持展宽期间
                pulse_cnt       <= pulse_cnt - 1'b1;
                pulse_stretched <= 1'b1;
            end else begin
                pulse_stretched <= 1'b0;
            end
        end
    end
    
    // ========== Stage 2: CDC双寄存器同步链 ==========
    (* ASYNC_REG = "TRUE" *) reg sync_ff1;
    (* ASYNC_REG = "TRUE" *) reg sync_ff2;
    
    // 根据PHASE_SEL选择不同的时钟沿
    generate
        if (PHASE_SEL == 0) begin : phase0
            // 标准同步：sys_clk上升沿采样
            always @(posedge sys_clk or negedge rst_n) begin
                if (!rst_n) begin
                    sync_ff1 <= 1'b0;
                    sync_ff2 <= 1'b0;
                end else begin
                    sync_ff1 <= pulse_stretched;
                    sync_ff2 <= sync_ff1;
                end
            end
        end else if (PHASE_SEL == 1) begin : phase1
            // 延迟半周期：用反相时钟
            always @(negedge sys_clk or negedge rst_n) begin
                if (!rst_n) begin
                    sync_ff1 <= 1'b0;
                end else begin
                    sync_ff1 <= pulse_stretched;
                end
            end
            always @(posedge sys_clk or negedge rst_n) begin
                if (!rst_n) begin
                    sync_ff2 <= 1'b0;
                end else begin
                    sync_ff2 <= sync_ff1;
                end
            end
        end else begin : phase2
            // 再延迟一级
            reg sync_ff0;
            always @(posedge sys_clk or negedge rst_n) begin
                if (!rst_n) begin
                    sync_ff0 <= 1'b0;
                    sync_ff1 <= 1'b0;
                    sync_ff2 <= 1'b0;
                end else begin
                    sync_ff0 <= pulse_stretched;
                    sync_ff1 <= sync_ff0;
                    sync_ff2 <= sync_ff1;
                end
            end
        end
    endgenerate
    
    // ========== Stage 3: 输出 ==========
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            sig_synced <= 1'b0;
        end else begin
            sig_synced <= sync_ff2;
        end
    end

endmodule
