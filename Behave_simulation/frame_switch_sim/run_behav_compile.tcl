# ----------------------------------------
# frame_switch_v_2_0 Behavioral Simulation Compile Script
# Module: frame_switch_v_2_0 (Multi-Buffer Frame Switch)
# Top Testbench: tb_frame_switch_v_2_0
# ----------------------------------------

vlib  work
vmap  work ./work
vlog  -sv -f define.f -work work   \
"../RTL_code/Video_data_buffer_layer/frame_switch_v_2_0.v"   \
"../Bench/tb_frame_switch_v_2_0.v"
