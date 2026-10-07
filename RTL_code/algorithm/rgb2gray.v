module rgb2gray#(
    parameter   PIPELINE_STAGES   =   4
)(
    input   wire                    clk                 ,
    input   wire                    rst_n               ,
    
    input   wire                    per_vga_vsync       ,
    input   wire                    per_vga_hsync       ,
    input   wire    [7:0]           per_vga_r           ,
    input   wire    [7:0]           per_vga_g           ,
    input   wire    [7:0]           per_vga_b           ,
    
    output  wire                    post_vga_vsync      ,
    output  wire                    post_vga_hsync      ,
    output  wire    [7:0]           post_vga_gray       
);

    reg [PIPELINE_STAGES-1:0]   vsync_pipe;
    reg [PIPELINE_STAGES-1:0]   hsync_pipe;

    reg     [23:0]      r_temp[2:0];
    reg     [23:0]      g_temp[1:0];
    reg     [23:0]      b_temp;
    reg     [23:0]      gray_sum;

    always @(posedge clk) begin : sync_pipeline
        if(!rst_n) begin
            vsync_pipe <= {PIPELINE_STAGES{1'b0}};
            hsync_pipe <= {PIPELINE_STAGES{1'b0}};
        end
        else begin
            vsync_pipe <= {vsync_pipe[PIPELINE_STAGES-2:0], per_vga_vsync};
            hsync_pipe <= {hsync_pipe[PIPELINE_STAGES-2:0], per_vga_hsync};
        end
    end

    always @(posedge clk) begin : stage1_r_multiply
        if(!rst_n) begin
            r_temp[0] <= 24'd0;
        end
        else begin
            r_temp[0] <= per_vga_r * 19595;
        end
    end

    always @(posedge clk) begin : stage2_g_multiply
        if(!rst_n) begin
            g_temp[0] <= 24'd0;
            r_temp[1] <= 24'd0;
        end
        else begin
            g_temp[0] <= per_vga_g * 38470;
            r_temp[1] <= r_temp[0];
        end
    end

    always @(posedge clk) begin : stage3_b_multiply
        if(!rst_n) begin
            b_temp <= 24'd0;
            r_temp[2] <= 24'd0;
            g_temp[1] <= 24'd0;
        end
        else begin
            b_temp <= per_vga_b * 7471;
            r_temp[2] <= r_temp[1];
            g_temp[1] <= g_temp[0];
        end
    end

    always @(posedge clk) begin : stage4_sum_and_shift
        if(!rst_n) begin
            gray_sum <= 24'd0;
        end
        else begin
            gray_sum <= r_temp[2] + g_temp[1] + b_temp;
        end
    end

    assign post_vga_vsync = vsync_pipe[PIPELINE_STAGES-1];
    assign post_vga_hsync = hsync_pipe[PIPELINE_STAGES-1];
    assign post_vga_gray = gray_sum[23:16];

endmodule
