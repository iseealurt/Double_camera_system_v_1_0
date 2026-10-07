# ============================================================
# frame_switch_v_2_0 Behavioral Simulation Waveform Script
# Module: frame_switch_v_2_0 (Multi-Buffer Frame Switch)
# Top Testbench: tb_frame_switch_v_2_0
# ============================================================

vsim -vopt -L work work.tb_frame_switch_v_2_0 -voptargs="+acc=npr"
onerror {quit -force}
onbreak {quit -force}

# ============================================================
# Base Path Definitions
# ============================================================
set DUT  /tb_frame_switch_v_2_0/dut
set TB   /tb_frame_switch_v_2_0

# ============================================================
# Waveform Groups
# ============================================================

# Testbench Level
add wave -noupdate -group tb_top                  ${TB}/*

# DUT Top Level - Module I/O
add wave -noupdate -group dut_io                  ${DUT}/*

# DUT Internal - Buffer Base Addresses
add wave -noupdate -group buffer_offsets \
    -radix hex                                  ${DUT}/buffer[0] \
    -radix hex                                  ${DUT}/buffer[1] \
    -radix hex                                  ${DUT}/buffer[2] \
    -radix hex                                  ${DUT}/buffer[3]

# DUT Internal - Write Address Capture
add wave -noupdate -group write_addr_capture \
    -label "awaddr_real_reg"                    ${DUT}/wr_user_awaddr_real_reg \
    -label "awlen_reg"                          ${DUT}/wr_user_awlen_reg \
    -label "finish_flag"                        ${DUT}/wr_user_finish_flag \
    -label "finish_flag_dly"                    ${DUT}/wr_user_finish_flag_dly \
    -label "finish_pose"                        ${DUT}/wr_user_finish_flag_pose

# DUT Internal - Read Address Capture
add wave -noupdate -group read_addr_capture \
    -label "araddr_real_reg[0]"                 ${DUT}/rd_user_araddr_real_reg[0*28+:28] \
    -label "arlen_reg[0]"                       ${DUT}/rd_user_arlen_reg[0*4+:4] \
    -label "finish_flag[0]"                     ${DUT}/rd_user_finish_flag[0] \
    -label "araddr_real_reg[1]"                 ${DUT}/rd_user_araddr_real_reg[1*28+:28] \
    -label "arlen_reg[1]"                       ${DUT}/rd_user_arlen_reg[1*4+:4] \
    -label "finish_flag[1]"                     ${DUT}/rd_user_finish_flag[1]

# DUT Internal - Pointer Tracking
add wave -noupdate -group ptr_tracking \
    -label "wr_ptr"                             ${DUT}/wr_ptr \
    -label "rd_ptr[0]"                          ${DUT}/rd_ptr[0] \
    -label "rd_ptr[1]"                          ${DUT}/rd_ptr[1] \
    -label "data_ptr[0]"                        ${DUT}/data_ptr[0] \
    -label "data_ptr[1]"                        ${DUT}/data_ptr[1]

# DUT Internal - Status Flags
add wave -noupdate -group status_flags \
    -label "wr_full"                            ${DUT}/wr_full \
    -label "rd_data_full[0]"                    ${DUT}/rd_data_full[0] \
    -label "rd_data_full[1]"                    ${DUT}/rd_data_full[1] \
    -label "rd_data_empty[0]"                   ${DUT}/rd_data_empty[0] \
    -label "rd_data_empty[1]"                   ${DUT}/rd_data_empty[1]

# DUT Internal - Output Monitor Ports
add wave -noupdate -group monitor_ports \
    -label "wr_finish_pose"                     ${DUT}/wr_user_finish_flag_pose \
    -label "rd_finish_pose[0]"                  ${DUT}/rd_user_finish_flag_pose[0] \
    -label "rd_finish_pose[1]"                  ${DUT}/rd_user_finish_flag_pose[1] \
    -label "wr_full"                            ${DUT}/wr_full \
    -label "rd_data_empty[0]"                   ${DUT}/rd_data_empty[0] \
    -label "rd_data_empty[1]"                   ${DUT}/rd_data_empty[1] \
    -label "wr_ptr"                             ${DUT}/wr_ptr \
    -label "rd_ptr[0]"                          ${DUT}/rd_ptr[0] \
    -label "rd_ptr[1]"                          ${DUT}/rd_ptr[1]

# ==============================================================
# Waveform Display Configuration
# ==============================================================
configure wave -signalnamewidth 1
configure wave -namecolwidth      250
configure wave -valuecolwidth     100
configure wave -justifyvalue      left
configure wave -timelineunits     ns
configure wave -griddelta         20
configure wave -timeline          0

# ==============================================================
# Run Simulation and View Waveform
# ==============================================================
view wave
run -all
quit -force
