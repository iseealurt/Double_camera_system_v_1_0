// Created by IP Generator (Version 2022.2-SP6.4 build 146967)
// Instantiation Template
//
// Insert the following codes into your Verilog file.
//   * Change the_instance_name to your own instance name.
//   * Change the signal names in the port associations


arbitor_afifo the_instance_name (
  .wr_data(wr_data),              // input [39:0]
  .wr_en(wr_en),                  // input
  .full(full),                    // output
  .almost_full(almost_full),      // output
  .rd_data(rd_data),              // output [39:0]
  .rd_en(rd_en),                  // input
  .empty(empty),                  // output
  .almost_empty(almost_empty),    // output
  .clk(clk),                      // input
  .rst(rst)                       // input
);
"../ipcore/arbitor_afifo/rtl/ipm_distributed_fifo_ctr_v1_1_arbitor_afifo.v"
"../ipcore/arbitor_afifo/rtl/ipm_distributed_fifo_v1_4_arbitor_afifo.v"
"../ipcore/arbitor_afifo/arbitor_afifo.v"
"../ipcore/arbitor_afifo/rtl/ipm_distributed_sdpram_v1_3_arbitor_afifo.v"
"../ipcore/arbitor_dfifo/arbitor_dfifo.v"
"../ipcore/arbitor_dfifo/rtl/ipm_distributed_fifo_ctr_v1_1_arbitor_dfifo.v"
"../ipcore/arbitor_dfifo/rtl/ipm_distributed_fifo_v1_4_arbitor_dfifo.v"
"../ipcore/arbitor_mask_fifo/arbitor_mask_fifo.v"
"../ipcore/arbitor_dfifo/rtl/ipm_distributed_sdpram_v1_3_arbitor_dfifo.v"
"../ipcore/arbitor_mask_fifo/rtl/ipm_distributed_fifo_ctr_v1_1_arbitor_mask_fifo.v"
"../ipcore/arbitor_mask_fifo/rtl/ipm_distributed_fifo_v1_4_arbitor_mask_fifo.v"
"../ipcore/arbitor_mask_fifo/rtl/ipm_distributed_sdpram_v1_3_arbitor_mask_fifo.v"