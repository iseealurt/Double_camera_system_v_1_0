`timescale 1ps/1ps
module SGM_TOP#(
    // -------------------------- 图像配置 --------------------------
    parameter   IMG_WIDTH            =   640             ,
    parameter   IMG_HEIGHT           =   480             ,
    parameter   IMG_PIX_WIDTH        =   16              ,
    // -------------------------- AXI总线 --------------------------
    parameter   AXI_ADDR_WIDTH       =   28              ,
    parameter   AXI_DATA_WIDTH       =   256             ,
    parameter   AXI_ID_WIDTH         =   4               ,
    parameter   AXI_LEN_WIDTH        =   4               ,
    parameter   MEM_DQ_WIDTH         =   32              ,
    parameter   AXI_WLEN             =   8               ,
    // -------------------------- SGM算法 --------------------------
    parameter   MAX_MATCH_DEPTH      =   48              ,
    parameter   CENSUS_WIDTH         =   24              ,
    parameter   DISPARITY_WIDTH      =   8               ,
    parameter   SGM_P1               =   3               ,
    parameter   SGM_P2               =   24              ,
    parameter   SGM_LR_WIDTH         =   12              ,
    // -------------------------- AXI ID配置 --------------------------
    parameter   CMR1_AXI_ID          =   4'b0001         ,
    parameter   CMR2_AXI_ID          =   4'b0010         ,
    parameter   WRITE_AXI_ID         =   4'b0100         
)(
    // -------------------------- 时钟复位 --------------------------
    input   wire                            pix_clk                 ,
    input   wire                            sgm_clk                 ,
    input   wire                            axi_clk                 ,
    input   wire                            rst_n                   ,

    // -------------------------- AXI读地址通道 --------------------------
    output  wire    [AXI_ADDR_WIDTH-1:0]    axi_araddr              ,
    output  wire    [AXI_ID_WIDTH-1:0]      axi_arid                ,
    output  wire    [AXI_LEN_WIDTH-1:0]     axi_arlen               ,
    output  wire                            axi_arvalid             ,
    input   wire                            axi_arready             ,

    // -------------------------- AXI读数据通道 --------------------------
    input   wire    [AXI_DATA_WIDTH-1:0]    axi_rdata               ,
    input   wire    [AXI_ID_WIDTH-1:0]      axi_rid                 ,
    input   wire                            axi_rvalid              ,
    input   wire                            axi_rlast               ,

    // -------------------------- AXI写地址通道 --------------------------
    output  wire    [AXI_ADDR_WIDTH-1:0]    axi_awaddr              ,
    output  wire    [AXI_ID_WIDTH-1:0]      axi_awid                ,
    output  wire    [AXI_LEN_WIDTH-1:0]     axi_awlen               ,
    output  wire                            axi_awvalid             ,
    input   wire                            axi_awready             ,

    // -------------------------- AXI写数据通道 --------------------------
    input   wire    [AXI_ID_WIDTH-1:0]      axi_wid                 ,
    output  wire    [AXI_DATA_WIDTH-1:0]    axi_wdata               ,
    output  wire    [MEM_DQ_WIDTH-1:0]      axi_wstrb               ,
    output  wire                            axi_wvalid              ,
    input   wire                            axi_wready              ,
    input   wire                            axi_wlast               ,

    // -------------------------- 缓冲区地址配置 --------------------------
    input   wire    [AXI_ADDR_WIDTH-1:0]    cmr_1_rd_buf_ofst       ,
    input   wire    [AXI_ADDR_WIDTH-1:0]    cmr_2_rd_buf_ofst       ,
    input   wire    [AXI_ADDR_WIDTH-1:0]    write_buffer_offset     
);

    // -------------------------- 内部信号定义 --------------------------

    // 像素FIFO信号
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

    // 显示模块输出
    wire                            disp_vsync;
    wire                            disp_href;
    wire    [7:0]                   l_disp_r_chn;
    wire    [7:0]                   l_disp_g_chn;
    wire    [7:0]                   l_disp_b_chn;
    wire    [7:0]                   r_disp_r_chn;
    wire    [7:0]                   r_disp_g_chn;
    wire    [7:0]                   r_disp_b_chn;

    // 灰度化输出
    wire                            l_gray_vsync;
    wire                            l_gray_hsync;
    wire    [7:0]                   l_gray_data;
    wire                            r_gray_vsync;
    wire                            r_gray_hsync;
    wire    [7:0]                   r_gray_data;

    // Census变换输出
    wire    [23:0]                  l_census_data;
    wire                            l_census_vsync;
    wire                            l_census_href;
    wire    [23:0]                  r_census_data;
    wire                            r_census_vsync;
    wire                            r_census_href;

    // Census FIFO 接口
    wire                            cmr_vsync_fifo_empty;
    wire                            cmr_vsync_fifo_rd_en;
    wire                            cmr_census_fifo_rd_en;
    wire                            cmr1_line_fifo_empty;
    wire    [CENSUS_WIDTH-1:0]      cmr1_census_fifo_dout;
    wire                            cmr2_line_fifo_empty;
    wire    [CENSUS_WIDTH-1:0]      cmr2_census_fifo_dout;

    // SGM视差输出
    wire                            disparity_vsync;
    wire                            disparity_href;
    wire    [DISPARITY_WIDTH-1:0]   disparity;

    // vsync token 上升沿检测
    wire                            vsync_combined;
    reg                             vsync_combined_dly;
    wire                            vsync_fifo_wr_en;

    // -------------------------- FIFO数据路由 --------------------------
    assign cmr_1_pix_fifo_wr_en = axi_rvalid && (axi_rid == CMR1_AXI_ID);
    assign cmr_2_pix_fifo_wr_en = axi_rvalid && (axi_rid == CMR2_AXI_ID);
    assign cmr_1_pix_fifo_wr_data = axi_rdata;
    assign cmr_2_pix_fifo_wr_data = axi_rdata;

    // -------------------------- vsync FIFO写入控制 --------------------------
    assign vsync_combined = l_census_vsync && r_census_vsync;
    always @(posedge pix_clk) begin
        if(!rst_n)
            vsync_combined_dly <= 1'b0;
        else
            vsync_combined_dly <= vsync_combined;
    end
    assign vsync_fifo_wr_en = vsync_combined && !vsync_combined_dly;

    wire fifo_rst;
    assign fifo_rst = !rst_n;
    // -------------------------- 层级1: 双路像素FIFO --------------------------
    drm_fifo_256b_8d u_cmr1_pix_fifo (
        .wr_clk                 (axi_clk                    ),
        .wr_rst                 (!rst_n                     ),
        .wr_en                  (cmr_1_pix_fifo_wr_en       ),
        .wr_data                (cmr_1_pix_fifo_wr_data     ),
        .wr_full                (                           ),
        .wr_water_level         (cmr_1_pix_fifo_wr_wl       ),
        .almost_full            (                           ),
        .rd_clk                 (pix_clk                    ),
        .rd_rst                 (fifo_rst                   ),
        .rd_en                  (cmr_1_pix_fifo_rd_en       ),
        .rd_data                (cmr_1_pix_fifo_rd_data     ),
        .rd_empty               (cmr_1_pix_fifo_empty       ),
        .almost_empty           (                           )
    );

    drm_fifo_256b_8d u_cmr2_pix_fifo (
        .wr_clk                 (axi_clk                    ),
        .wr_rst                 (!rst_n                     ),
        .wr_en                  (cmr_2_pix_fifo_wr_en       ),
        .wr_data                (cmr_2_pix_fifo_wr_data     ),
        .wr_full                (                           ),
        .wr_water_level         (cmr_2_pix_fifo_wr_wl       ),
        .almost_full            (                           ),
        .rd_clk                 (pix_clk                    ),
        .rd_rst                 (fifo_rst                   ),
        .rd_en                  (cmr_2_pix_fifo_rd_en       ),
        .rd_data                (cmr_2_pix_fifo_rd_data     ),
        .rd_empty               (cmr_2_pix_fifo_empty       ),
        .almost_empty           (                           )
    );

    // -------------------------- 层级2: SGM数据引擎 --------------------------
    sgm_data_engine#(
        .H_VALID                (IMG_WIDTH                  ),
        .V_VALID                (IMG_HEIGHT                 ),
        .CMR_1_AXI_ID           (CMR1_AXI_ID                ),
        .CMR_2_AXI_ID           (CMR2_AXI_ID                ),
        .AXI_ADDR_WIDTH         (AXI_ADDR_WIDTH             ),
        .AXI_DATA_WIDTH         (AXI_DATA_WIDTH             ),
        .AXI_ID_WIDTH           (AXI_ID_WIDTH               ),
        .AXI_LEN_WIDTH          (AXI_LEN_WIDTH              )
    ) u_sgm_data_engine (
        .rst_n                  (rst_n                      ),
        .pix_clk                (pix_clk                    ),
        .cmr_1_pix_fifo_wr_wl   (cmr_1_pix_fifo_wr_wl[7:0]  ),
        .cmr_2_pix_fifo_wr_wl   (cmr_2_pix_fifo_wr_wl[7:0]  ),
        .camera_1_rd_de         (!cmr_1_pix_fifo_empty      ),
        .camera_1_rd_data       (cmr_1_pix_fifo_rd_data     ),
        .camera_1_rd_req        (cmr_1_pix_fifo_rd_en       ),
        .camera_2_rd_de         (!cmr_2_pix_fifo_empty      ),
        .camera_2_rd_data       (cmr_2_pix_fifo_rd_data     ),
        .camera_2_rd_req        (cmr_2_pix_fifo_rd_en       ),
        .vsync                  (disp_vsync                 ),
        .href                   (disp_href                  ),
        .l_r_chn                (l_disp_r_chn               ),
        .l_g_chn                (l_disp_g_chn               ),
        .l_b_chn                (l_disp_b_chn               ),
        .r_r_chn                (r_disp_r_chn               ),
        .r_g_chn                (r_disp_g_chn               ),
        .r_b_chn                (r_disp_b_chn               ),
        .cmr_1_rd_buf_ofst      (cmr_1_rd_buf_ofst          ),
        .cmr_2_rd_buf_ofst      (cmr_2_rd_buf_ofst          ),
        .axi_clk                (axi_clk                    ),
        .axi_ar_id              (axi_arid                   ),
        .axi_ar_len             (axi_arlen                  ),
        .axi_araddr             (axi_araddr                 ),
        .axi_araddr_valid       (axi_arvalid                ),
        .axi_araddr_ready       (axi_arready                ),
        .axi_rlast              (axi_rlast                  ),
        .axi_rd_id              (axi_rid                    )
    );

    // -------------------------- 层级3: RGB转灰度 --------------------------
    rgb2gray u_rgb2gray_left (
        .clk                    (pix_clk                    ),
        .rst_n                  (rst_n                      ),
        .per_vga_vsync          (disp_vsync                 ),
        .per_vga_hsync          (disp_href                  ),
        .per_vga_r              (l_disp_r_chn               ),
        .per_vga_g              (l_disp_g_chn               ),
        .per_vga_b              (l_disp_b_chn               ),
        .post_vga_vsync         (l_gray_vsync               ),
        .post_vga_hsync         (l_gray_hsync               ),
        .post_vga_gray          (l_gray_data                )
    );

    rgb2gray u_rgb2gray_right (
        .clk                    (pix_clk                    ),
        .rst_n                  (rst_n                      ),
        .per_vga_vsync          (disp_vsync                 ),
        .per_vga_hsync          (disp_href                  ),
        .per_vga_r              (r_disp_r_chn               ),
        .per_vga_g              (r_disp_g_chn               ),
        .per_vga_b              (r_disp_b_chn               ),
        .post_vga_vsync         (r_gray_vsync               ),
        .post_vga_hsync         (r_gray_hsync               ),
        .post_vga_gray          (r_gray_data                )
    );

    // -------------------------- 层级4: Census特征变换 --------------------------
    census_5x5#(
        .IMAGE_WIDTH            (IMG_WIDTH                  ),
        .IMAGE_HEIGHT           (IMG_HEIGHT                 )
    ) u_census_5x5_left (
        .pix_clk                (pix_clk                    ),
        .rst_n                  (rst_n                      ),
        .per_vga_vsync          (l_gray_vsync               ),
        .per_vga_href           (l_gray_hsync               ),
        .per_vga_gray           (l_gray_data                ),
        .census                 (l_census_data              ),
        .census_vsync           (l_census_vsync             ),
        .census_href            (l_census_href              )
    );

    census_5x5#(
        .IMAGE_WIDTH            (IMG_WIDTH                  ),
        .IMAGE_HEIGHT           (IMG_HEIGHT                 )
    ) u_census_5x5_right (
        .pix_clk                (pix_clk                    ),
        .rst_n                  (rst_n                      ),
        .per_vga_vsync          (r_gray_vsync               ),
        .per_vga_href           (r_gray_hsync               ),
        .per_vga_gray           (r_gray_data                ),
        .census                 (r_census_data              ),
        .census_vsync           (r_census_vsync             ),
        .census_href            (r_census_href              )
    );

    // -------------------------- 层级5: Census → SGM 间 FIFO 缓冲层 --------------------------
    cmr_census_fifo u_cmr1_census_fifo (
        .wr_clk         (pix_clk                    ),
        .wr_rst         (!rst_n                     ),
        .wr_en          (l_census_href              ),
        .wr_data        (l_census_data              ),
        .wr_full        (                           ),
        .almost_full    (                           ),
        .rd_clk         (sgm_clk                    ),
        .rd_rst         (!rst_n                     ),
        .rd_en          (cmr_census_fifo_rd_en      ),
        .rd_data        (cmr1_census_fifo_dout      ),
        .rd_empty       (cmr1_line_fifo_empty       ),
        .almost_empty   (                           )
    );

    cmr_census_fifo u_cmr2_census_fifo (
        .wr_clk         (pix_clk                    ),
        .wr_rst         (!rst_n                     ),
        .wr_en          (r_census_href              ),
        .wr_data        (r_census_data              ),
        .wr_full        (                           ),
        .almost_full    (                           ),
        .rd_clk         (sgm_clk                    ),
        .rd_rst         (!rst_n                     ),
        .rd_en          (cmr_census_fifo_rd_en      ),
        .rd_data        (cmr2_census_fifo_dout      ),
        .rd_empty       (cmr2_line_fifo_empty       ),
        .almost_empty   (                           )
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

    // -------------------------- 层级6: SGM半全局匹配 --------------------------
    sgm_new_2#(
        .IMG_WIDTH              (IMG_WIDTH                  ),
        .IMG_HEIGHT             (IMG_HEIGHT                 ),
        .MAX_MATCH_DEPTH        (MAX_MATCH_DEPTH            ),
        .CENSUS_WIDTH           (CENSUS_WIDTH               ),
        .DISPARITY_WIDTH        (DISPARITY_WIDTH            ),
        .CONFIDENCE_WIDTH       (8                          ),
        .CONFIDENCE_THRE        (1                          ),
        .SGM_P1                 (SGM_P1                     ),
        .SGM_P2                 (SGM_P2                     ),
        .SGM_LR_WIDTH           (SGM_LR_WIDTH               ),
        .SGM_INVALID_COST       (24                         )
    ) u_sgm_new (
        .sgm_clk                (sgm_clk                    ),
        .rst_n                  (rst_n                      ),
        .cmr_vsync_fifo_empty   (cmr_vsync_fifo_empty       ),
        .cmr1_line_fifo_empty   (cmr1_line_fifo_empty       ),
        .cmr1_census            (cmr1_census_fifo_dout      ),
        .cmr2_line_fifo_empty   (cmr2_line_fifo_empty       ),
        .cmr2_census            (cmr2_census_fifo_dout      ),
        .cmr_vsync_fifo_rd_en   (cmr_vsync_fifo_rd_en       ),
        .cmr_census_fifo_rd_en  (cmr_census_fifo_rd_en      ),
        .disparity_vsync        (disparity_vsync            ),
        .disparity_href         (disparity_href             ),
        .disparity              (disparity                  )
    );

    // -------------------------- 层级7: VESA_AXI输出 --------------------------
    // 内部信号用于VESA_AXI

    VESA_AXI#(
        .AXI_ADDR_WIDTH         (AXI_ADDR_WIDTH             ),
        .MEM_DQ_WIDTH           (MEM_DQ_WIDTH               ),
        .WIDTH                  (IMG_WIDTH                  ),
        .HEIGHT                 (IMG_HEIGHT                 ),
        .INPUT_DATA_WIDTH       (DISPARITY_WIDTH            ),
        .AXI_ID                 (WRITE_AXI_ID               )
    ) u_VESA_AXI (
        .rst_n                  (rst_n                      ),
        .pclk                   (sgm_clk                    ),
        .din                    (disparity                  ),
        .href                   (disparity_href             ),
        .vref                   (disparity_vsync            ),
        .write_buffer_offset    (write_buffer_offset        ),
        .axi_clk                (axi_clk                    ),
        .axi_awaddr             (axi_awaddr                 ),
        .axi_awready            (axi_awready                ),
        .axi_awvalid            (axi_awvalid                ),
        .axi_awid               (axi_awid                   ),
        .axi_awlen              (axi_awlen                  ),
        .axi_wid                (axi_wid                    ),
        .axi_wready             (axi_wready                 ),
        .axi_wlast              (axi_wlast                  ),
        .axi_wdata              (axi_wdata                  ),
        .axi_wstrb              (axi_wstrb                  )
    );

endmodule