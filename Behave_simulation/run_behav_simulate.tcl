# ============================================================
# Full System Simulation Waveform Observation Script (ModelSim Only)
# Module: OV_DDR_HDMI_v_2_0 (Double Camera System)
# Top Testbench: tb_OV_DDR_HDMI_v_2_0
# ============================================================

vsim -vopt -L work -L usim -L adc -L ddrc -L ddrphy -L hsst_e2 \
     -L iolhr_dft -L ipal_e1 -L pciegen2 \
     work.tb_OV_DDR_HDMI_v_2_0 usim.GTP_GRS \
     -voptargs="+acc=npr"

# ============================================================
# Base Path Definitions
# ============================================================
set DUT  /tb_OV_DDR_HDMI_v_2_0/dut
set TB   /tb_OV_DDR_HDMI_v_2_0

# ============================================================
# Module Waveform Groups
# ============================================================

# Testbench Level
add wave -noupdate -group tb_top                  ${TB}/*

# DUT Top Level (wires and interconnects between sub-modules)
add wave -noupdate -group dut_top                 ${DUT}/*

# video_init - 系统初始化状态机
add wave -noupdate -group video_init              ${DUT}/video_init_inst/*

# uart_cfg - 摄像头I2C配置模块 x2
add wave -noupdate -group cmr1_uart_cfg           ${DUT}/cmr_1_uart_cfg_inst/*
add wave -noupdate -group cmr2_uart_cfg           ${DUT}/cmr_2_uart_cfg_inst/*

# ms72xx_ctl - HDMI驱动芯片初始化模块
add wave -noupdate -group ms_init                 ${DUT}/ms_init_module/*

# PLL - 像素时钟生成
add wave -noupdate -group pix_clk_gene            ${DUT}/pix_clk_gene/*

# DVP_AXI_v_2_0 - 摄像头数据采集转AXI x2
add wave -noupdate -group cmr1_dvp_axi            ${DUT}/cmr_1_dvp_axi/*
add wave -noupdate -group cmr2_dvp_axi            ${DUT}/cmr_2_dvp_axi/*

# ddr3_50h - DDR3控制器IP核
add wave -noupdate -group ddr3_controller         ${DUT}/ddr3_50h_inst/*

# SGM_TOP - 立体匹配算法顶层（含内部子模块）
add wave -noupdate -group sgm_top                 ${DUT}/u_sgm_top/*
add wave -noupdate -group sgm_data_engine         ${DUT}/u_sgm_top/u_sgm_data_engine/*
add wave -noupdate -group {rgb2gray_left}         ${DUT}/u_sgm_top/u_rgb2gray_left/*
add wave -noupdate -group {rgb2gray_right}        ${DUT}/u_sgm_top/u_rgb2gray_right/*
add wave -noupdate -group {census_5x5_left}       ${DUT}/u_sgm_top/u_census_5x5_left/*
add wave -noupdate -group {census_5x5_right}      ${DUT}/u_sgm_top/u_census_5x5_right/*
add wave -noupdate -group sgm_core                ${DUT}/u_sgm_top/u_sgm_new/*
add wave -noupdate -group VESA_AXI                ${DUT}/u_sgm_top/u_VESA_AXI/*
add wave -noupdate -group VESA_AXI                ${DUT}/u_sgm_top/u_VESA_AXI/no_buffer_data_acquisition/*

add wave -noupdate -group sgm_cmr1_pix_fifo       ${DUT}/u_sgm_top/u_cmr1_pix_fifo//*
add wave -noupdate -group sgm_cmr2_pix_fifo       ${DUT}/u_sgm_top/u_cmr2_pix_fifo//*
add wave -noupdate -group sgm_cmr1_census_fifo    ${DUT}/u_sgm_top/u_cmr1_census_fifo//*
add wave -noupdate -group sgm_cmr2_census_fifo    ${DUT}/u_sgm_top/u_cmr2_census_fifo//*
add wave -noupdate -group sgm_vsync_fifo          ${DUT}/u_sgm_top/u_sgm_vsync_fifo//*


# axi_arbiter_v_2_0 - 4-user AXI仲裁器 (扁平化架构)
add wave -noupdate -group axi_arbiter             ${DUT}/u_axi_arbiter_v_2_0//*

# frame_switch - 帧切换模块 x2
add wave -noupdate -group cmr1_frame_switch       ${DUT}/cmr1_frame_switch_v_2_0/*
add wave -noupdate -group cmr2_frame_switch       ${DUT}/cmr2_frame_switch_v_2_0/*


# drm_fifo_256b_8d - 像素数据FIFO x2
add wave -noupdate -group cmr1_pix_fifo           ${DUT}/cmr_1_pix_fifo/*
add wave -noupdate -group cmr2_pix_fifo           ${DUT}/cmr_2_pix_fifo/*

# double_camera_disp - 双摄像头显示驱动
add wave -noupdate -group double_camera_disp      ${DUT}/double_camera_disp_inst/*

# sgm_disp - SGM视差图叠加显示
add wave -noupdate -group sgm_disp                ${DUT}/u_sgm_disp/*

# ==============================================================
# Waveform Display Configuration
# ==============================================================
configure wave -signalnamewidth 1
configure wave -namecolwidth      250
configure wave -valuecolwidth     100
configure wave -justifyvalue      left
configure wave -timelineunits     ns
configure wave -griddelta         40
configure wave -timeline          0

# ==============================================================
# Open Waveform Windows
# ==============================================================
view wave
view structure
view signals

update

# ==============================================================
# Debug Helpers - Run these in ModelSim console if needed
# ==============================================================
# find signals -r ${DUT}/*

run 1000 ms
