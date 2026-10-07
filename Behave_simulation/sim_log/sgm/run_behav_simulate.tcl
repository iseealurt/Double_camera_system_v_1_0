# ============================================================
# SGM_NEW_2 Full Waveform Observation Script (ModelSim Only)
# Module: sgm_new_2.v (SGM with single-path cost aggregation)
# Parameters: IMG_WIDTH=640, IMG_HEIGHT=480, MAX_MATCH_DEPTH=48
#             CENSUS_WIDTH=24, SGM_LR_WIDTH=12, DISPARITY_WIDTH=8
# ============================================================
# Safe signal add function - skip missing signals without stopping script
proc add_wave_safe {args} {
    if {[catch {eval add wave $args} err]} {
        puts "WARNING: Skip missing signal - [lindex $args end]"
    }
}

# Start simulation
vsim -vopt -L work -L usim -L adc -L ddrc -L ddrphy -L hsst_e2 \
     -L iolhr_dft -L ipal_e1 -L pciegen2 \
     work.tb_sgm_new usim.GTP_GRS \
     -voptargs="+acc=npr"

# ============================================================
# Base Path Definitions
# ============================================================
quietly set DUT         /tb_sgm_new/u_sgm_new
quietly set MAX_DEPTH   48
quietly set GRP_PER_D   4
quietly set HALF_GRP    2

# ============================================================
# Other Module Waveforms
# ============================================================
add wave -noupdate -group axi_mem_model_wave     /tb_sgm_new/u_axi_mem_test_module/*
add wave -noupdate -group sgm_data_engine_wave /tb_sgm_new/u_sgm_data_engine/*
add wave -noupdate -group cmr2_pix_fifo_wave     /tb_sgm_new/u_cmr2_pix_fifo/*
add wave -noupdate -group cmr1_pix_fifo_wave     /tb_sgm_new/u_cmr1_pix_fifo/*
add wave -noupdate -group rgb2gray_left_wave     /tb_sgm_new/u_rgb2gray_left/*
add wave -noupdate -group rgb2gray_right_wave    /tb_sgm_new/u_rgb2gray_right/*
add wave -noupdate -group census_5x5_left_wave   /tb_sgm_new/u_census_5x5_left/*
add wave -noupdate -group census_5x5_right_wave  /tb_sgm_new/u_census_5x5_right/*
add wave -noupdate -group cmr1_census_fifo_wave  /tb_sgm_new/u_cmr1_census_fifo/*
add wave -noupdate -group cmr2_census_fifo_wave  /tb_sgm_new/u_cmr2_census_fifo/*
add wave -noupdate -group vsync_fifo_wave        /tb_sgm_new/u_sgm_vsync_fifo/*
add wave -noupdate -group bench_wave             /tb_sgm_new/*

# ============================================================
# sgm_new_2 Module: Pipeline Stage Groups
# ============================================================

# ----------------------------------------------------------
# Group: sgm_top - 顶层控制与FIFO接口信号
# ----------------------------------------------------------
add wave -noupdate -group sgm_top \
    -label "sgm_clk"                ${DUT}/sgm_clk \
    -label "rst_n"                  ${DUT}/rst_n \
    -label "vsync_fifo_empty"       ${DUT}/cmr_vsync_fifo_empty \
    -label "cmr1_line_fifo_empty"   ${DUT}/cmr1_line_fifo_empty \
    -label "cmr1_census"            ${DUT}/cmr1_census \
    -label "cmr2_line_fifo_empty"   ${DUT}/cmr2_line_fifo_empty \
    -label "cmr2_census"            ${DUT}/cmr2_census \
    -label "vsync_fifo_rd_en"       ${DUT}/cmr_vsync_fifo_rd_en \
    -label "census_fifo_rd_en"      ${DUT}/cmr_census_fifo_rd_en \
    -label "disparity_vsync"        ${DUT}/disparity_vsync \
    -label "disparity_href"         ${DUT}/disparity_href \
    -label "disparity"              ${DUT}/disparity

# ----------------------------------------------------------
# Group: sgm_state_machine - 状态机 + 行列计数器
# ----------------------------------------------------------
add wave -noupdate -group sgm_state_machine \
    -label "curr_state"             ${DUT}/curr_state \
    -label "next_state"             ${DUT}/next_state \
    -label "row_cnt"                ${DUT}/row_cnt \
    -label "col_cnt"                ${DUT}/col_cnt

# ----------------------------------------------------------
# Group: sgm_pipeline_ctrl - 流水线控制与同步延迟链
# ----------------------------------------------------------
add wave -noupdate -group sgm_pipeline_ctrl \
    -label "sgm_vsync"              ${DUT}/sgm_vsync \
    -label "vsync_delay_chain"      ${DUT}/vsync_delay_chain \
    -label "pipeline_dly_chain"     ${DUT}/pipeline_dly_chain

# ----------------------------------------------------------
# Group: Stage 0 - XOR Matching Window (cmr2 移位, cmr1 寄存)
# ----------------------------------------------------------
add wave -noupdate -group sgm_stage0_xor_window \
    -label {ctrl:dly[0]}            ${DUT}/pipeline_dly_chain\[0\] \
    -label "cmr1_census_reg"        ${DUT}/cmr1_census_reg \
    -label "xor_window[0](newest)"  ${DUT}/xor_window\[0\] \
    -label "xor_window[1]"          ${DUT}/xor_window\[1\] \
    -label "xor_window[2]"          ${DUT}/xor_window\[2\] \
    -label "xor_window[11]"         ${DUT}/xor_window\[11\] \
    -label "xor_window[23]"         ${DUT}/xor_window\[23\] \
    -label "xor_window[35]"         ${DUT}/xor_window\[35\] \
    -label "xor_window[47](oldest)" ${DUT}/xor_window\[47\]

# ----------------------------------------------------------
# Group: Stage 1 - XOR Result
# ----------------------------------------------------------
add wave -noupdate -group sgm_stage1_xor_result \
    -label {ctrl:dly[1]}            ${DUT}/pipeline_dly_chain\[1\] \
    -label "xor_outcome[0]"         ${DUT}/xor_outcome\[0\] \
    -label "xor_outcome[1]"         ${DUT}/xor_outcome\[1\] \
    -label "xor_outcome[11]"        ${DUT}/xor_outcome\[11\] \
    -label "xor_outcome[23]"        ${DUT}/xor_outcome\[23\] \
    -label "xor_outcome[47]"        ${DUT}/xor_outcome\[47\]

# ----------------------------------------------------------
# Group: Stage 2 - Popcount Level 1 (6bit->3bit, LUT6 based)
# ----------------------------------------------------------
add wave -noupdate -group sgm_stage2_popcount_s1 \
    -label {ctrl:dly[2]}            ${DUT}/pipeline_dly_chain\[2\]

foreach d {0 23 47} {
    set idx0 [expr ${d} * 4]
    set idx1 [expr ${d} * 4 + 1]
    set idx2 [expr ${d} * 4 + 2]
    set idx3 [expr ${d} * 4 + 3]
    add wave -noupdate -group sgm_stage2_popcount_s1 \
        -label "d${d}_g0(bit5:0)"   ${DUT}/popcount_s1\[${idx0}\] \
        -label "d${d}_g1(bit11:6)"  ${DUT}/popcount_s1\[${idx1}\] \
        -label "d${d}_g2(bit17:12)" ${DUT}/popcount_s1\[${idx2}\] \
        -label "d${d}_g3(bit23:18)" ${DUT}/popcount_s1\[${idx3}\]
}

# ----------------------------------------------------------
# Group: Stage 3 - Mask Column Counter, Valid Mask, Popcount Level 2
# ----------------------------------------------------------
add wave -noupdate -group sgm_stage3_mask_popcount_s2 \
    -label {ctrl:dly[3]}            ${DUT}/pipeline_dly_chain\[3\] \
    -label "mask_col_cnt"           ${DUT}/hamming_valid_mask_col_cnt \
    -label "valid_mask[0]"          ${DUT}/hamming_dist_valid_mask\[0\] \
    -label "valid_mask[23]"         ${DUT}/hamming_dist_valid_mask\[23\] \
    -label "valid_mask[47]"         ${DUT}/hamming_dist_valid_mask\[47\]

foreach d {0 23 47} {
    add wave -noupdate -group sgm_stage3_mask_popcount_s2 \
        -label "d${d}_pair0(g0+g1)" ${DUT}/popcount_s2\[${d}\]\[0\] \
        -label "d${d}_pair1(g2+g3)" ${DUT}/popcount_s2\[${d}\]\[1\]
}

# ----------------------------------------------------------
# Group: Stage 4 - Final Hamming Distance (with mask)
# ----------------------------------------------------------
add wave -noupdate -group sgm_stage4_hamming_dist \
    -label {ctrl:dly[4]}            ${DUT}/pipeline_dly_chain\[4\]

set d 0
while {$d < 48} {
    add wave -noupdate -group sgm_stage4_hamming_dist \
        -label "hamming_dist\[${d}\]" ${DUT}/hamming_dist\[${d}\]
    incr d
}

# ----------------------------------------------------------
# Group: Stage 5 - SGM Cost Aggregation (Lr3_curr_comb -> Lr3_curr_reg)
# Note: Only Lr3 direction remains due to resource constraints
# ----------------------------------------------------------
add wave -noupdate -group sgm_stage5_cost_agg \
    -label {ctrl:dly[5]}            ${DUT}/pipeline_dly_chain\[5\]

foreach d {0 1 23 24 46 47} {
    add wave -noupdate -group sgm_stage5_cost_agg \
        -label "Lr3_comb[${d}]"     ${DUT}/Lr3_curr_comb\[${d}\] \
        -label "Lr3_reg[${d}]"      ${DUT}/Lr3_curr_reg\[${d}\]
}

# ----------------------------------------------------------
# Group: Stage 6 - Cost Sum (Lr_sum) + Lr3_prev_min_comb
# ----------------------------------------------------------
add wave -noupdate -group sgm_stage6_prev_and_sum \
    -label {ctrl:dly[6]}            ${DUT}/pipeline_dly_chain\[6\]

foreach d {0 1 23 24 46 47} {
    add wave -noupdate -group sgm_stage6_prev_and_sum \
        -label "Lr_sum[${d}]"       ${DUT}/Lr_sum\[${d}\]
}


# ----------------------------------------------------------
# Group: sgm_WTA_compare_tree - WTA 胜者为王比较树 (6级, Stage 7-12)
# ----------------------------------------------------------
add wave -noupdate -group sgm_WTA_compare_tree \
    -label {ctrl:dly[7..12]}        ${DUT}/pipeline_dly_chain

foreach k {0 1 11 23} {
    add wave -noupdate -group sgm_WTA_compare_tree \
        -label "stg1_cost[${k}]"    ${DUT}/WTA_compare_tree/Lr_min_compare_tree_temp0\[${k}\] \
        -label "stg1_disp[${k}]"    ${DUT}/WTA_compare_tree/best_d_temp0\[${k}\]
}

foreach k {0 1 5 11} {
    add wave -noupdate -group sgm_WTA_compare_tree \
        -label "stg2_cost[${k}]"    ${DUT}/WTA_compare_tree/Lr_min_compare_tree_temp1\[${k}\] \
        -label "stg2_disp[${k}]"    ${DUT}/WTA_compare_tree/best_d_temp1\[${k}\]
}

foreach k {0 1 2 5} {
    add wave -noupdate -group sgm_WTA_compare_tree \
        -label "stg3_cost[${k}]"    ${DUT}/WTA_compare_tree/Lr_min_compare_tree_temp2\[${k}\] \
        -label "stg3_disp[${k}]"    ${DUT}/WTA_compare_tree/best_d_temp2\[${k}\]
}

foreach k {0 1 2} {
    add wave -noupdate -group sgm_WTA_compare_tree \
        -label "stg4_cost[${k}]"    ${DUT}/WTA_compare_tree/Lr_min_compare_tree_temp3\[${k}\] \
        -label "stg4_disp[${k}]"    ${DUT}/WTA_compare_tree/best_d_temp3\[${k}\]
}

add wave -noupdate -group sgm_WTA_compare_tree \
    -label "stg5_cost[0](bypass)"   ${DUT}/WTA_compare_tree/Lr_min_compare_tree_temp4\[0\] \
    -label "stg5_cost[1](min)"      ${DUT}/WTA_compare_tree/Lr_min_compare_tree_temp4\[1\] \
    -label "stg5_disp[0]"           ${DUT}/WTA_compare_tree/best_d_temp4\[0\] \
    -label "stg5_disp[1]"           ${DUT}/WTA_compare_tree/best_d_temp4\[1\]
add wave -noupdate -group sgm_WTA_compare_tree \
    -label "best_disparity"         ${DUT}/best_disparity \

# ----------------------------------------------------------
# Group: sgm_disparity_output - 视差输出时序
# ----------------------------------------------------------
add wave -noupdate -group sgm_subpixel_insert \
    -label "Lr_min"             ${DUT}/Lr_min \
    -label "Lr_second_min"      ${DUT}/Lr_second_min \
    -label "confidence_reg"     ${DUT}/confidence_reg \
    -label "best_disparity_dly" ${DUT}/best_disparity_dly \

# ----------------------------------------------------------
# Group: sgm_disparity_output - 视差输出时序
# ----------------------------------------------------------
add wave -noupdate -group sgm_disparity_output \
    -label "sgm_vsync"              ${DUT}/sgm_vsync \
    -label {vsync_dly[10]}          ${DUT}/vsync_delay_chain\[10\] \
    -label {vsync_dly[11]}          ${DUT}/vsync_delay_chain\[11\] \
    -label {vsync_dly[12]}          ${DUT}/vsync_delay_chain\[12\] \
    -label {pipeline_dly[10]}       ${DUT}/pipeline_dly_chain\[10\] \
    -label {pipeline_dly[11]}       ${DUT}/pipeline_dly_chain\[11\] \
    -label {pipeline_dly[12]}       ${DUT}/pipeline_dly_chain\[12\] \
    -label "disparity_vsync"        ${DUT}/disparity_vsync \
    -label "disparity_href"         ${DUT}/disparity_href \
    -label "disparity"              ${DUT}/disparity

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
# 1. List all top level signals in sgm_new_2
# find signals /tb_sgm_new/u_sgm_new/*
#
# 2. Find WTA comparison tree hierarchy
# find signals -r /tb_sgm_new/u_sgm_new/WTA_compare_tree/*
#
# 3. Find cost aggregation internal signals
# find signals -r /tb_sgm_new/u_sgm_new/Lr0_aggregation/*

run 1000 ms
