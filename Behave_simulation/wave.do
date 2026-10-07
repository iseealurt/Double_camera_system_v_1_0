onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/ref_clk
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/resetn
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/ddr_init_done
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/ddrphy_clkin
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/pll_lock
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_awaddr
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_awuser_ap
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_awuser_id
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_awlen
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_awready
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_awvalid
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_wdata
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_wstrb
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_wready
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_wusero_id
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_wusero_last
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_araddr
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_aruser_ap
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_aruser_id
add wave -noupdate -expand -group ddr3_controller -radix unsigned /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_arlen
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_arready
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_arvalid
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_rdata
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_rid
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_rlast
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/axi_rvalid
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/apb_clk
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/apb_rst_n
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/apb_sel
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/apb_enable
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/apb_addr
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/apb_write
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/apb_ready
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/apb_wdata
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/apb_rdata
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/apb_int
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/debug_data
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/debug_slice_state
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/debug_calib_ctrl
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/ck_dly_set_bin
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/ck_dly_en
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/init_ck_dly_step
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/wl_step_ov_warning
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/dll_step
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/dll_lock
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/init_read_clk_ctrl
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/init_slip_step
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/force_read_clk_ctrl
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/ddrphy_gate_update_en
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/update_com_val_err_flag
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/rd_fake_stop
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/mem_rst_n
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/mem_ck
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/mem_ck_n
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/mem_cke
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/mem_cs_n
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/mem_ras_n
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/mem_cas_n
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/mem_we_n
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/mem_odt
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/mem_a
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/mem_ba
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/mem_dqs
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/mem_dqs_n
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/mem_dq
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/mem_dm
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/dfi_phyupd_req
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/dfi_phyupd_ack
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/dfi_init_complete
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/dfi_address
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/dfi_bank
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/dfi_cs_n
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/dfi_ras_n
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/dfi_cas_n
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/dfi_we_n
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/dfi_cke
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/dfi_odt
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/dfi_wrdata
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/dfi_wrdata_en
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/dfi_wrdata_mask
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/dfi_rddata
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/dfi_rddata_valid
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/ddrphy_ioclk_gate
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/ddrphy_dqs_rst
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/ddrphy_ioclk_source
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/ioclk
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/ddrphy_ioclk
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/pll_clkin
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/pll_ioclk_lock
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/ddr_rstn
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/ddrphy_pll_rst
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/ioclk_gate_clk
add wave -noupdate -expand -group ddr3_controller /tb_OV_DDR_HDMI_v_2_0/dut/ddr3_50h_inst/ioclk_gate_clk_pll
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {806043750000 fs} 0}
quietly wave cursor active 1
configure wave -namecolwidth 250
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {449593446 ps} {1162494054 ps}
