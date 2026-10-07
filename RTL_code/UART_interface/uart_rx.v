module uart_rx#(
	parameter 	CLK_FREQ 	= 	28'd50_000_000	,
				BODE_RATE 	= 	19'd115200
)(
	input wire sys_clk,
	input wire sys_rst_n,
	input wire RX,
	input wire rd_ready,
	output reg rd_valid,
	output reg [7:0] rd_data
);
	wire rx_posedge;
	wire rx_negedge;
	wire [27:0] cnt_value_set;
	reg [2:0] RX_reg;
	reg [19:0] period_cnt;
	reg [7:0] rd_data_reg;
	reg [3:0] bit_cnt;
	reg cnt_flag;
	assign cnt_value_set = (CLK_FREQ / BODE_RATE) - 1;
	assign rx_posedge = RX_reg == 3'b001 ? 1'b1 : 1'b0;
	assign rx_negedge = RX_reg == 3'b100 ? 1'b1 : 1'b0;
	
	always@(posedge sys_clk or negedge sys_rst_n) begin
		if (!sys_rst_n) begin
			RX_reg <= 3'd0;
		end
		else begin 
			RX_reg <= {RX_reg,RX};
		end
	end
	
	always@(posedge sys_clk or negedge sys_rst_n) begin
		if (!sys_rst_n) begin
			cnt_flag <= 1'b0;
		end
		else begin 
			if (rx_negedge && !cnt_flag) begin cnt_flag <= 1'b1;end
			else if (cnt_flag && period_cnt == cnt_value_set && bit_cnt == 4'd9) begin 
				cnt_flag <= 1'b0;
			end
		end
	end
	
	always@(posedge sys_clk or negedge sys_rst_n) begin
		if (!sys_rst_n) begin
			period_cnt <= 20'd0;
		end
		else begin 
			if(cnt_flag) begin period_cnt <= period_cnt == cnt_value_set ? 20'd0 : period_cnt + 20'd1;end
			else begin period_cnt <= 20'd0; end
		end
	end
	
	always@(posedge sys_clk or negedge sys_rst_n) begin
		if (!sys_rst_n) begin
			bit_cnt <= 4'd0;
		end
		else begin 
			if(cnt_flag) begin
				bit_cnt <= period_cnt == cnt_value_set ? bit_cnt+ 4'd1 : bit_cnt;
			end
			else begin bit_cnt <= 4'd0; end
		end
	end
	
	always@(posedge sys_clk or negedge sys_rst_n) begin
		if (!sys_rst_n) begin
			rd_valid <= 1'b0;
		end
		else begin 
			if (cnt_flag) begin 
				if(rd_ready && rd_valid) begin
					rd_valid <= 1'b0;
				end
				else if(bit_cnt == 4'd9 && period_cnt == 20'd2) begin
					rd_valid <= 1'b1;
				end
				else begin rd_valid <= rd_valid; end
			end
			else begin rd_valid <= 1'b0; end
		end
	end
	
	always@(posedge sys_clk or negedge sys_rst_n) begin
		if (!sys_rst_n) begin
			rd_data <= 8'd0;
		end
		else begin 
			if (cnt_flag) begin 
				if(bit_cnt == 4'd9 && period_cnt == 20'd2) begin
					rd_data <= rd_data_reg;
				end
				else begin rd_data <=  rd_data; end
			end
			else begin rd_data <= 8'd0; end
		end
	end
	
	always@(posedge sys_clk or negedge sys_rst_n) begin
		if (!sys_rst_n) begin
			rd_data_reg <= 8'd0;
		end
		else begin		
			case (bit_cnt) 
			4'd0:begin end
			4'd1:begin rd_data_reg[0] <= period_cnt == cnt_value_set/2 ? RX_reg[2] : rd_data_reg[0];end
			4'd2:begin rd_data_reg[1] <= period_cnt == cnt_value_set/2 ? RX_reg[2] : rd_data_reg[1];end
			4'd3:begin rd_data_reg[2] <= period_cnt == cnt_value_set/2 ? RX_reg[2] : rd_data_reg[2];end
			4'd4:begin rd_data_reg[3] <= period_cnt == cnt_value_set/2 ? RX_reg[2] : rd_data_reg[3];end
			4'd5:begin rd_data_reg[4] <= period_cnt == cnt_value_set/2 ? RX_reg[2] : rd_data_reg[4];end
			4'd6:begin rd_data_reg[5] <= period_cnt == cnt_value_set/2 ? RX_reg[2] : rd_data_reg[5];end
			4'd7:begin rd_data_reg[6] <= period_cnt == cnt_value_set/2 ? RX_reg[2] : rd_data_reg[6];end
			4'd8:begin rd_data_reg[7] <= period_cnt == cnt_value_set/2 ? RX_reg[2] : rd_data_reg[7];end
			4'd9:begin end
			default:begin end
			endcase
		end
	end
	
	
endmodule