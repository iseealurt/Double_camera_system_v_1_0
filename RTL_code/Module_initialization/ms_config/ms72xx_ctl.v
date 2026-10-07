`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:Meyesemi 
// Engineer: Will
// 
// Create Date: 2023-01-29 20:31  
// Design Name:  
// Module Name: 
// Project Name: 
// Target Devices: Pango
// Tool Versions: 
// Description: 
//      
// Dependencies: 
// 
// Revision:
// Revision 1.0 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

`define UD #1
module ms72xx_ctl(
    input       clk,
    input       rst_n,    
    output      init_over_tx,
    output      iic_tx_scl,
    inout       iic_tx_sda
);
    reg rstn_temp1,rstn_temp2;
    reg rstn;
    always @(posedge clk or negedge rst_n)
    begin
    	if(!rst_n)
    	    rstn_temp1 <= 1'b0;
    	else
    	    rstn_temp1 <= rst_n;
    end
    
    always @(posedge clk)
    begin
    	rstn_temp2 <= rstn_temp1;
    	rstn <= rstn_temp2;
    end
     
    wire   [7:0] device_id_tx;
    wire         iic_trig_tx ;
    wire         w_r_tx      ;
    wire  [15:0] addr_tx     ;
    wire  [ 7:0] data_in_tx  ;
    wire         busy_tx     ;
    wire  [ 7:0] data_out_tx ;
    wire         byte_over_tx;

    ms7210_ctl ms7210_ctl(
        .clk             (  clk           ),//input               
        .rstn            (  rstn          ),//input    rstn),//                       
        .init_over       (  init_over_tx  ),//output reg          
        .device_id       (  device_id_tx  ),//output        [7:0] 
        .iic_trig        (  iic_trig_tx   ),//output reg          
        .w_r             (  w_r_tx        ),//output reg          
        .addr            (  addr_tx       ),//output reg   [15:0] 
        .data_in         (  data_in_tx    ),//output reg   [ 7:0] 
        .busy            (  busy_tx       ),//input               
        .data_out        (  data_out_tx   ),//input        [ 7:0] 
        .byte_over       (  byte_over_tx  ) //input               
    );
    
    wire         sda_tx_in;
    wire         sda_tx_out;
    wire         sda_tx_out_en;  
    iic_dri #(
        .CLK_FRE        (  27'd50_000_000  ),//parameter            CLK_FRE   = 27'd50_000_000,//system clock frequency
        .IIC_FREQ       (  20'd400_000     ),//parameter            IIC_FREQ  = 20'd400_000,   //I2c clock frequency
        .T_WR           (  10'd1           ),//parameter            T_WR      = 10'd5,         //I2c transmit delay ms
        .ADDR_BYTE      (  2'd2            ),//parameter            ADDR_BYTE = 2'd1,          //I2C addr byte number
        .LEN_WIDTH      (  8'd3            ),//parameter            LEN_WIDTH = 8'd3,          //I2C transmit byte width
        .DATA_BYTE      (  2'd1            ) //parameter            DATA_BYTE = 2'd1           //I2C data byte number
    )iic_dri_tx(                       
        .clk            (  clk             ),//input                clk,
        .rstn           (  rstn            ),//input                rstn,
        .device_id      (  device_id_tx    ),//input                device_id,
        .pluse          (  iic_trig_tx     ),//input                pluse,                     //I2C transmit trigger
        .w_r            (  w_r_tx          ),//input                w_r,                       //I2C transmit direction 1:send  0:receive
        .byte_len       (  4'd1            ),//input  [LEN_WIDTH:0] byte_len,                  //I2C transmit data byte length of once trigger
                   
        .addr           (  addr_tx         ),//input  [7:0]         addr,                      //I2C transmit addr
        .data_in        (  data_in_tx      ),//input  [7:0]         data_in,                   //I2C send data
                     
        .busy           (  busy_tx         ),//output reg           busy=0,                    //I2C bus status
        
        .byte_over      (  byte_over_tx    ),//output reg           byte_over=0,               //I2C byte transmit over flag               
        .data_out       (  data_out_tx     ),//output reg[7:0]      data_out,                  //I2C receive data
                                           
        .scl            (  iic_tx_scl      ),//output               scl,
        .sda_in         (  sda_tx_in       ),//input                sda_in,
        .sda_out        (  sda_tx_out      ),//output   reg         sda_out=1'b1,
        .sda_out_en     (  sda_tx_out_en   ) //output               sda_out_en
    );
    
    assign iic_tx_sda = sda_tx_out_en ? sda_tx_out : 1'bz;
    assign sda_tx_in = iic_tx_sda;

endmodule
