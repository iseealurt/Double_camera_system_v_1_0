`timescale 1ns/1ns
module tb_multi_axi_connector();

	//------------------------------ parameter ------------------------------
	parameter 	CLOCK_PERIOD_NS = 	10					;
	parameter	AXI_ID_WIDTH	=	4					;
	parameter	AXI_LEN_WIDTH	=	4					;
	parameter	AXI_ADDR_WIDTH	=	28					;
	parameter	AXI_DATA_WIDTH	=	256					;
	parameter	AXI_STRB_WIDTH	=	AXI_DATA_WIDTH / 8 	;
	parameter	ARBITER_AXI_ID	=	4'b0001				;
	parameter	USER_0_AXI_ID	=	4'b0001				;
	parameter	USER_1_AXI_ID	=	4'b0011				;
	parameter	CREDIT_DIGITS	=	4					;
	parameter	CREDIT_MAX_NUM	=	4'd10				;
	//------------------------------ signal ------------------------------
	reg 							axi_clk			;
	reg 							rst_n			;
	
	reg 							user_0_arvalid	;
	wire 							user_0_arready	;
	reg		[AXI_ADDR_WIDTH-1:0]	user_0_araddr	;
	reg 	[AXI_ID_WIDTH-1:0]		user_0_ar_id	;
	reg 	[AXI_LEN_WIDTH-1:0]		user_0_ar_len	;
	
	reg 							user_1_arvalid	;
	wire 							user_1_arready	;
	reg		[AXI_ADDR_WIDTH-1:0]	user_1_araddr	;
	reg 	[AXI_ID_WIDTH-1:0]		user_1_ar_id	;
	reg 	[AXI_LEN_WIDTH-1:0]		user_1_ar_len	;

	wire 	[AXI_DATA_WIDTH-1:0]	user_0_rd_data	;
	wire 							user_0_rvalid	;
	wire 							user_0_rlast	;
	
	wire 	[AXI_DATA_WIDTH-1:0]	user_1_rd_data	;
	wire 							user_1_rvalid	;
	wire 							user_1_rlast	;
	
	reg 							user_0_awvalid	;
	wire 							user_0_awready	;
	reg		[AXI_ADDR_WIDTH-1:0]	user_0_awaddr	;
	reg 	[AXI_ID_WIDTH-1:0]		user_0_aw_id	;
	reg 	[AXI_LEN_WIDTH-1:0]		user_0_aw_len	;
	
	reg 							user_1_awvalid	;
	wire 							user_1_awready	;
	reg		[AXI_ADDR_WIDTH-1:0]	user_1_awaddr	;
	reg 	[AXI_ID_WIDTH-1:0]		user_1_aw_id	;
	reg 	[AXI_LEN_WIDTH-1:0]		user_1_aw_len	;

	reg 	[AXI_DATA_WIDTH-1:0]	user_0_wr_data	;
	reg 	[AXI_STRB_WIDTH-1:0]	user_0_wstrb	;
	wire 	[AXI_ID_WIDTH-1:0]		user_0_wr_id	;
	wire 							user_0_wready	;
	wire 							user_0_wlast	;
	
	reg 	[AXI_DATA_WIDTH-1:0]	user_1_wr_data	;
	reg 	[AXI_STRB_WIDTH-1:0]	user_1_wstrb	;
	wire 	[AXI_ID_WIDTH-1:0]		user_1_wr_id	;
	wire 							user_1_wready	;
	wire 							user_1_wlast	;
	
	wire 	[AXI_ID_WIDTH-1:0]		user_0_rd_id	;
	wire 							user_0_rready	;
		
	wire 	[AXI_ID_WIDTH-1:0]		user_1_rd_id	;
	wire 							user_1_rready	;
	
	wire 							arbiter_arvalid	;
	reg 							arbiter_arready	;
	wire	[AXI_ADDR_WIDTH-1:0]	arbiter_araddr	;
	wire 	[AXI_ID_WIDTH-1:0]		arbiter_ar_id	;
	wire 	[AXI_LEN_WIDTH-1:0]		arbiter_ar_len	;
	
	wire 							arbiter_awvalid	;
	reg 							arbiter_awready	;
	wire	[AXI_ADDR_WIDTH-1:0]	arbiter_awaddr	;
	wire 	[AXI_ID_WIDTH-1:0]		arbiter_aw_id	;
	wire 	[AXI_LEN_WIDTH-1:0]		arbiter_aw_len	;
	
	wire 	[AXI_DATA_WIDTH-1:0]	arbiter_wr_data	;
	wire 	[AXI_STRB_WIDTH-1:0]	arbiter_wstrb	;
	reg 	[AXI_ID_WIDTH-1:0]		arbiter_wr_id	;
	reg 							arbiter_wready	;
	reg 							arbiter_wlast	;
	
	reg 	[AXI_DATA_WIDTH-1:0]	arbiter_rd_data	;
	reg 	[AXI_ID_WIDTH-1:0]		arbiter_rd_id	;
	reg 							arbiter_rvalid	;
	reg 							arbiter_rlast	;
	
	integer i;
	//------------------------------ module instantiation ------------------------------
	GTP_GRS GRS_INST (
		.GRS_N(rst_n) // INPUT  
	);
	//Global reset
	multi_axi_connector #(
		.AXI_ADDR_WIDTH        (AXI_ADDR_WIDTH    ),
		.AXI_DATA_WIDTH        (AXI_DATA_WIDTH    ),
		.AXI_ID_WIDTH          (AXI_ID_WIDTH      ),
		.AXI_LEN_WIDTH         (AXI_LEN_WIDTH     ),
		.DDR_DATA_MASK_WIDTH   (AXI_STRB_WIDTH    ),
		.DATA_BACKPRESSURE_EN  (1'b0              ),
		.ARBITER_CLIENT_ID     (ARBITER_AXI_ID    ),
		.USER_0_AXI_ID         (USER_0_AXI_ID     ),
		.USER_1_AXI_ID         (USER_1_AXI_ID     ),
		.CREDIT_DIGITS         (CREDIT_DIGITS     ),
		.CREDIT_MAX_NUM        (CREDIT_MAX_NUM    )
	) uut (
		.axi_clk               (axi_clk           ),
		.rst_n                 (rst_n             ),
		.grant_busy            (                  ),
		
		.user_0_araddr         (user_0_araddr     ),
		.user_0_ar_id          (user_0_ar_id      ),
		.user_0_ar_len         (user_0_ar_len     ),
		.user_0_araddr_valid   (user_0_arvalid    ),
		.user_0_araddr_ready   (user_0_arready    ),
		
		.user_0_awaddr         (user_0_awaddr     ),
		.user_0_aw_id          (user_0_aw_id      ),
		.user_0_aw_len         (user_0_aw_len     ),
		.user_0_awaddr_valid   (user_0_awvalid    ),
		.user_0_awaddr_ready   (user_0_awready    ),
		
		.user_1_araddr         (user_1_araddr     ),
		.user_1_ar_id          (user_1_ar_id      ),
		.user_1_ar_len         (user_1_ar_len     ),
		.user_1_araddr_valid   (user_1_arvalid    ),
		.user_1_araddr_ready   (user_1_arready    ),
		
		.user_1_awaddr         (user_1_awaddr     ),
		.user_1_aw_id          (user_1_aw_id      ),
		.user_1_aw_len         (user_1_aw_len     ),
		.user_1_awaddr_valid   (user_1_awvalid    ),
		.user_1_awaddr_ready   (user_1_awready    ),
		
		.arbiter_araddr        (arbiter_araddr    ),
		.arbiter_ar_id         (arbiter_ar_id     ),
		.arbiter_ar_len        (arbiter_ar_len    ),
		.arbiter_araddr_valid  (arbiter_arvalid   ),
		.arbiter_araddr_ready  (arbiter_arready   ),
		
		.arbiter_awaddr        (arbiter_awaddr    ),
		.arbiter_aw_id         (arbiter_aw_id     ),
		.arbiter_aw_len        (arbiter_aw_len    ),
		.arbiter_awaddr_valid  (arbiter_awvalid   ),
		.arbiter_awaddr_ready  (arbiter_awready   ),
		
		.user_0_wr_data        (user_0_wr_data    ),
		.user_0_wr_data_valid  (),
		.user_0_wstrb          (user_0_wstrb      ),
		.user_0_wr_data_ready  (user_0_wready     ),
		.user_0_wr_id          (user_0_wr_id      ),
		.user_0_wr_data_last   (user_0_wlast      ),
		
		.user_0_rd_data        (user_0_rd_data    ),
		.user_0_rd_data_valid  (user_0_rvalid     ),
		.user_0_rd_data_ready  (),
		.user_0_rd_id          (user_0_rd_id      ),
		.user_0_rd_data_last   (user_0_rlast      ),
		
		.user_1_wr_data        (user_1_wr_data    ),
		.user_1_wr_data_valid  (),
		.user_1_wstrb          (user_1_wstrb      ),
		.user_1_wr_data_ready  (user_1_wready     ),
		.user_1_wr_id          (user_1_wr_id      ),
		.user_1_wr_data_last   (user_1_wlast      ),
		
		.user_1_rd_data        (user_1_rd_data    ),
		.user_1_rd_data_valid  (user_1_rvalid	  ),
		.user_1_rd_data_ready  (),
		.user_1_rd_id          (user_1_rd_id      ),
		.user_1_rd_data_last   (user_1_rlast      ),
		
		.arbiter_wr_data       (arbiter_wr_data   ),
		.arbiter_wr_data_valid (),
		.arbiter_wr_data_ready (arbiter_wready    ),
		.arbiter_wstrb         (arbiter_wstrb     ),
		.arbiter_wr_id         (arbiter_wr_id     ),
		.arbiter_wr_data_last  (arbiter_wlast     ),
		
		.arbiter_rd_data       (arbiter_rd_data   ),
		.arbiter_rd_data_valid (arbiter_rvalid    ),
		.arbiter_rd_data_ready (),
		.arbiter_rd_id         (arbiter_rd_id     ),
		.arbiter_rd_data_last  (arbiter_rlast     )
		
	);
	//------------------------------ CLock signal ------------------------------
	initial begin
		axi_clk = 0;
		forever #(CLOCK_PERIOD_NS/2) axi_clk = ~ axi_clk;
	end
	//------------------------------ task ------------------------------
	task user_0_single_read;
		input 	integer 				task_id;
		input 	[AXI_ADDR_WIDTH-1:0]	axi_araddr;
		input 	[AXI_LEN_WIDTH-1:0]		axi_ar_len;
		input 	integer 				timeout_cycles;
		output 	reg 					success;
		integer i;
		reg last_flag;
		begin
			success = 0;
			last_flag = 0;
			fork: user_0_single_read_task
				begin: araddr_channel
					user_0_arvalid = 1'b0;
					@(posedge axi_clk) begin
						user_0_arvalid = 1'b1;
						user_0_araddr = axi_araddr;
						user_0_ar_len = axi_ar_len;
						user_0_ar_id  = USER_0_AXI_ID;
					end
					$display("@ %0t , User 0 commenced a single read @address: %0d and %0d burst length",$time,axi_araddr,axi_ar_len + 1);
					wait(user_0_arvalid && user_0_arready) begin
						$display("@ %0t , User 0 got a read address handshake with the connector",$time);
						@(posedge axi_clk) user_0_arvalid = 1'b0;
					end
				end
				begin: rdata_channel
					i = 0;
					while(i <= axi_ar_len && !last_flag) begin
						@(posedge axi_clk) begin
							if(user_0_rvalid) begin
								$display("@ %0t , User_0_rd_chn got a new data: %h",$time,user_0_rd_data);
								i = i + 1;
							end
							if(user_0_rlast) begin
								$display("@ %0t , User_0_rd_chn finished a read task",$time);
								last_flag = 1;
							end
						end
					end
					if(i == axi_ar_len + 1) begin
						$display("@ %0t , a read task of User 0 succeeded",$time);
						success = 1;
						disable user_0_single_read_task;
					end
					else begin
						$display("@ %0t , a read task of User 0 failed because the number of the data got from the arbiter didn't match the predicted one: %0d / %0d",$time,i,axi_ar_len+1);
						success = 0;
						disable user_0_single_read_task;
					end
				end
				begin: timeout_monitor
					repeat(timeout_cycles) @(posedge axi_clk);
					$display("warning , timeout occured @ %0t",$time);
					success = 0;
					disable user_0_single_read_task;
				end
			join 
			if(!success) begin
				$display("@ %0t , task %0d failed",$time,task_id);
				@(posedge axi_clk)  begin
					user_0_arvalid = 1'b0;
					user_0_araddr = 0;
					user_0_ar_len = 0;
					user_0_ar_id  = 0;
				end
			end
			else begin
				$display("@ %0t , task %0d succeeded",$time,task_id);
				@(posedge axi_clk)  begin
					user_0_arvalid = 1'b0;
					user_0_araddr = 0;
					user_0_ar_len = 0;
					user_0_ar_id  = 0;
				end
			end
		end
	endtask
	
	task user_1_single_read;
		input 	integer 				task_id;
		input 	[AXI_ADDR_WIDTH-1:0]	axi_araddr;
		input 	[AXI_LEN_WIDTH-1:0]		axi_ar_len;
		input 	integer 				timeout_cycles;
		output 	reg 					success;
		integer i;
		reg 	last_flag;
		begin 
			success = 0;
			last_flag = 0;
			fork: user_1_single_read_task
				begin: araddr_channel
					user_1_arvalid = 1'b0;
					@(posedge axi_clk) begin
						user_1_arvalid = 1'b1;
						user_1_araddr = axi_araddr;
						user_1_ar_len = axi_ar_len;
						user_1_ar_id  = USER_1_AXI_ID;
					end
					$display("@ %0t , User 1 commenced a single read @address: %0d and %0d burst length",$time,axi_araddr,axi_ar_len + 1);
					wait(user_1_arvalid && user_1_arready) begin
						$display("@ %0t , User 1 got a read address handshake with the connector",$time);
						@(posedge axi_clk) user_1_arvalid = 1'b0;
					end
				end
				begin: rdata_channel
					i = 0;
					while(i <= axi_ar_len && !last_flag) begin
						@(posedge axi_clk) begin
							if(user_1_rvalid) begin
								$display("@ %0t , User_1_rd_chn got a new data: %h",$time,user_1_rd_data);
								i = i + 1;
							end
							if(user_1_rlast) begin
								$display("@ %0t , User_1_rd_chn finished a read task",$time);
								last_flag = 1'b1;
							end
						end
					end
					if(i == axi_ar_len + 1) begin
						$display("@ %0t , a read task of User 1 succeeded",$time);
						success = 1;
						disable user_1_single_read_task;
					end
					else begin
						$display("@ %0t , a read task of User 1 failed because the number of the data got from the arbiter didn't match the predicted one: %0d / %0d",$time,i,axi_ar_len+1);
						success = 0;
						disable user_1_single_read_task;
					end
				end
				begin: timeout_monitor
					repeat(timeout_cycles) @(posedge axi_clk);
					$display("warning , timeout occured @ %0t",$time);
					success = 0;
					disable user_1_single_read_task;
				end
			join 
			if(!success) begin
				$display("@ %0t , task %0d failed",$time,task_id);
				@(posedge axi_clk)  begin
					user_1_arvalid = 1'b0;
					user_1_araddr = 0;
					user_1_ar_len = 0;
					user_1_ar_id  = 0;
				end
			end
			else begin
				$display("@ %0t , task %0d succeeded",$time,task_id);
				@(posedge axi_clk)  begin
					user_1_arvalid = 1'b0;
					user_1_araddr = 0;
					user_1_ar_len = 0;
					user_1_ar_id  = 0;
				end
			end
		end
	endtask
	
	task user_0_single_write;
		input 	integer 				task_id;
		input 	[AXI_ADDR_WIDTH-1:0]	axi_awaddr;
		input 	[AXI_LEN_WIDTH-1:0]		axi_aw_len;
		input 	integer 				timeout_cycles;
		output 	reg 					success;
		integer i;
		reg last_flag;
		begin
			success = 0;
			i = 0;
			last_flag = 0;
			fork: user_0_single_write_task
				begin: awaddr_chn
					user_0_awvalid = 0;
					@(posedge axi_clk) begin
						user_0_awvalid = 1'b1;
						user_0_awaddr = axi_awaddr;
						user_0_aw_len = axi_aw_len;
						user_0_aw_id  = USER_0_AXI_ID;
					end
					$display("@ %0t , User 0 commenced a single write @address: %h with %0d burst length",$time,axi_awaddr,axi_aw_len + 1);
					wait(user_0_awvalid && user_0_awready) begin
						$display("@ %0t , User 0 got a write address handshake with the connector",$time);
						@(posedge axi_clk) user_0_awvalid = 1'b0;
					end
				end
				begin: wdata_chn
					while (i < axi_aw_len + 1 && !last_flag) begin
						@(posedge axi_clk) begin
							user_0_wr_data = {228'd0,USER_0_AXI_ID*(28'd16+i)};
							user_0_wstrb = 32'hff_ff_Ff_ff;
							if(user_0_wready) begin
								i = i + 1;
								$display("@ %0t , User 0 write a new data to the connector",$time);
							end
							if(user_0_wlast) begin
								$display("@ %0t , User 0 finished the write data request",$time);
								last_flag = 1;
							end
						end
					end
					if(i != axi_aw_len + 1) begin
						$display("@ %0t , a write task of User 0 failed because the number of the data sent to the arbiter didn't match the predicted one: %0d / %0d",$time,i,axi_aw_len+1);
						success = 0;
						disable user_0_single_write_task;
					end
					else begin
						$display("@ %0t , a write task of User 0 succeeded",$time);
						success = 1;
						disable user_0_single_write_task;
					end
				end
				begin: timeout_monitor
					repeat(timeout_cycles) @(posedge axi_clk);
					$display("warning , timeout occured @ %0t",$time);
					success = 0;
					disable user_0_single_write_task;
				end
			join
			if(!success) begin
				$display("@ %0t , task %0d failed",$time,task_id);
				@(posedge axi_clk)  begin
					user_0_awvalid = 1'b0;
					user_0_awaddr = 0;
					user_0_aw_len = 0;
					user_0_aw_id  = 0;
				end
			end
			else begin
				$display("@ %0t , task %0d succeeded",$time,task_id);
				@(posedge axi_clk)  begin
					user_0_awvalid = 1'b0;
					user_0_awaddr = 0;
					user_0_aw_len = 0;
					user_0_aw_id  = 0;
				end
			end
		end
	endtask
	
	task user_1_single_write;
		input 	integer 				task_id;
		input 	[AXI_ADDR_WIDTH-1:0]	axi_awaddr;
		input 	[AXI_LEN_WIDTH-1:0]		axi_aw_len;
		input 	integer 				timeout_cycles;
		output 	reg 					success;
		integer i;
		reg last_flag;
		begin
			success = 0;
			last_flag = 0;
			i = 0;
			fork: user_1_single_write_task
				begin: awaddr_chn
					user_1_awvalid = 0;
					@(posedge axi_clk) begin
						user_1_awvalid = 1'b1;
						user_1_awaddr = axi_awaddr;
						user_1_aw_len = axi_aw_len;
						user_1_aw_id  = USER_1_AXI_ID;
					end
					$display("@ %0t , User 1 commenced a single write @address: %h with %0d burst length",$time,axi_awaddr,axi_aw_len + 1);
					wait(user_1_awvalid && user_1_awready) begin
						$display("@ %0t , User 1 got a write address handshake with the connector",$time);
						@(posedge axi_clk) user_1_awvalid = 1'b0;
					end
				end
				begin: wdata_chn
					while (i < axi_aw_len + 1) begin
						@(posedge axi_clk) begin
							user_1_wr_data = {228'd0,USER_1_AXI_ID*(28'd16+i)};
							user_1_wstrb = 32'hff_ff_Ff_ff;
							if(user_1_wready) begin
								i = i + 1;
								$display("@ %0t , User 1 write a new data to the connector",$time);
							end
							if(user_1_wlast) begin
								$display("@ %0t , User 1 finished the write data request",$time);
								last_flag = 1;
							end
						end
					end
					if(i != axi_aw_len + 1) begin
						$display("@ %0t , a write task of User 1 failed because the number of the data sent to the arbiter didn't match the predicted one: %0d / %0d",$time,i,axi_aw_len+1);
						success = 0;
						disable user_1_single_write_task;
					end
					else begin
						$display("@ %0t , a write task of User 1 succeeded",$time);
						success = 1;
						disable user_1_single_write_task;
					end
				end
				begin: timeout_monitor
					repeat(timeout_cycles) @(posedge axi_clk);
					$display("warning , timeout occured @ %0t",$time);
					success = 0;
					disable user_1_single_write_task;
				end
			join
			if(!success) begin
				$display("@ %0t , task %0d failed",$time,task_id);
				@(posedge axi_clk)  begin
					user_1_awvalid = 1'b0;
					user_1_awaddr = 0;
					user_1_aw_len = 0;
					user_1_aw_id  = 0;
				end
			end
			else begin
				$display("@ %0t , task %0d succeeded",$time,task_id);
				@(posedge axi_clk)  begin
					user_1_awvalid = 1'b0;
					user_1_awaddr = 0;
					user_1_aw_len = 0;
					user_1_aw_id  = 0;
				end
			end
		end
	endtask
	
	task user_0_back_to_back_read;
		input 	integer					task_id;
		input 	[AXI_ADDR_WIDTH-1:0] 	axi_address;
		input 	integer 				repeat_rounds;
		input 	[AXI_LEN_WIDTH-1:0]		axi_ar_len;
		output 	reg 					success;
		integer i,j;
		reg last_flag;
		begin
			success = 0;
			fork: user_0_back_to_back_read_task
				begin: araddr_chn
					i = 0;
					repeat(repeat_rounds) begin
						user_0_arvalid = 1'b0;
						@(posedge axi_clk) begin
							user_0_arvalid = 1'b1;
							user_0_araddr = axi_address;
							user_0_ar_len = axi_ar_len;
							user_0_ar_id  = USER_0_AXI_ID;
						end
						$display("@ %0t , User 0 commenced a single read @address: %0d and %0d burst length",$time,axi_address,axi_ar_len + 1);
						wait(user_0_arvalid && user_0_arready) begin
							@(posedge axi_clk) user_0_arvalid = 1'b0; i = i + 1;
							$display("@ %0t , User 0 got a read address handshake with the connector , %0d handshake tasks left",$time,repeat_rounds - i);							
						end	
					end
					$display("@ %0t , all ar address handshake tasks finished",$time);
				end
				begin: rdata_chn
					repeat(repeat_rounds) begin
						j = 0;
						last_flag = 0;
						while(j <= axi_ar_len && !last_flag) begin
							@(posedge axi_clk) begin
								if(user_0_rvalid) begin
									$display("@ %0t , User_0_rd_chn got a new data: %h",$time,user_0_rd_data);
									j = j + 1;
								end
								if(user_0_rlast) begin
									$display("@ %0t , User_0_rd_chn finished a read task",$time);
									last_flag = 1;
								end
							end
						end
						if(j == axi_ar_len + 1) begin
							$display("@ %0t , a read task of User 0 succeeded",$time);
						end
						else begin
							$display("@ %0t , a read task of User 0 failed because the number of the data got from the arbiter didn't match the predicted one: %0d / %0d",$time,i,axi_ar_len+1);
							success = 0;
							disable user_0_back_to_back_read_task;
						end
					end
					success = 1;
					disable user_0_back_to_back_read_task;
					$display("@ %0t , a back-to-back read taks of User 0 succeeded",$time);
				end
				begin: timeout_monitor
					repeat(repeat_rounds * (axi_ar_len+14)) @(posedge axi_clk);	
					$display("warning , timeout occured @ %0t",$time);
					success = 0;
					disable user_0_back_to_back_read_task;
				end
			join
			if(!success) begin
				$display("@ %0t , task %0d failed",$time,task_id);
				@(posedge axi_clk)  begin
					user_0_arvalid = 1'b0;
					user_0_araddr = 0;
					user_0_ar_len = 0;
					user_0_ar_id  = 0;
				end
			end
			else begin
				$display("@ %0t , task %0d succeeded",$time,task_id);
				@(posedge axi_clk)  begin
					user_0_arvalid = 1'b0;
					user_0_araddr = 0;
					user_0_ar_len = 0;
					user_0_ar_id  = 0;
				end
			end
		end
	endtask
	
	task user_1_back_to_back_read;
		input 	integer					task_id;
		input 	[AXI_ADDR_WIDTH-1:0] 	axi_address;
		input 	integer 				repeat_rounds;
		input 	[AXI_LEN_WIDTH-1:0]		axi_ar_len;
		output 	reg 					success;
		integer i,j;
		reg last_flag;
		begin
			success = 0;
			fork: user_1_back_to_back_read_task
				begin: araddr_chn
					i = 0;
					repeat(repeat_rounds) begin
						user_1_arvalid = 1'b0;
						@(posedge axi_clk) begin
							user_1_arvalid = 1'b1;
							user_1_araddr = axi_address;
							user_1_ar_len = axi_ar_len;
							user_1_ar_id  = USER_1_AXI_ID;
						end
						$display("@ %0t , User 1 commenced a single read @address: %0d and %0d burst length",$time,axi_address,axi_ar_len + 1);
						wait(user_1_arvalid && user_1_arready) begin
							i = i + 1;
							$display("@ %0t , User 1 got a read address handshake with the connector , %0d handshake tasks left",$time,repeat_rounds - i);
							@(posedge axi_clk) user_1_arvalid = 1'b0;
						end	
					end
					$display("@ %0t , all ar address handshake tasks finished",$time);
				end
				begin: rdata_chn
					repeat(repeat_rounds) begin
						j = 0;
						last_flag = 0;
						while(j <= axi_ar_len && !last_flag) begin
							@(posedge axi_clk) begin
								if(user_1_rvalid) begin
									$display("@ %0t , User_1_rd_chn got a new data: %h",$time,user_1_rd_data);
									j = j + 1;
								end
								if(user_1_rlast) begin
									$display("@ %0t , User_1_rd_chn finished a read task",$time);
									last_flag = 1;
								end
							end
						end
						if(j == axi_ar_len + 1) begin
							$display("@ %0t , a read task of User 1 succeeded",$time);
						end
						else begin
							$display("@ %0t , a read task of User 1 failed because the number of the data got from the arbiter didn't match the predicted one: %0d / %0d",$time,i,axi_ar_len+1);
							success = 0;
							disable user_1_back_to_back_read_task;
						end
					end
					success = 1;
					disable user_1_back_to_back_read_task;
					$display("@ %0t , a back-to-back read taks of User 1 succeeded",$time);
				end
				begin: timeout_monitor
					repeat(repeat_rounds * (axi_ar_len+14)) @(posedge axi_clk);
					//握手延迟3个周期，数据传输 len + 1 个周期，外加10个周期的传输响应时间冗余
					$display("warning , timeout occured @ %0t",$time);
					success = 0;
					disable user_1_back_to_back_read_task;
				end
			join
			if(!success) begin
				$display("@ %0t , task %0d failed",$time,task_id);
				@(posedge axi_clk)  begin
					user_1_arvalid = 1'b0;
					user_1_araddr = 0;
					user_1_ar_len = 0;
					user_1_ar_id  = 0;
				end
			end
			else begin
				$display("@ %0t , task %0d succeeded",$time,task_id);
				@(posedge axi_clk)  begin
					user_1_arvalid = 1'b0;
					user_1_araddr = 0;
					user_1_ar_len = 0;
					user_1_ar_id  = 0;
				end
			end
		end
	endtask
	
	task interval_back_to_back_read;
		input	integer 				task_id;
		input 	[AXI_ADDR_WIDTH-1:0]	axi_address;
		input	integer 				repeat_rounds;
		input 	[AXI_LEN_WIDTH-1:0]		axi_ar_len;
		output 	reg 					success;
		reg 							user_0_success;
		reg 							user_1_success;
		integer 						i,j,user_0_hs_cnt,user_1_hs_cnt;
		reg 							user_0_last_flag;
		reg 							user_1_last_flag;
		begin
			user_0_success = 0 ;
			user_1_success = 0 ;
			success = 0;
			fork: interval_back_to_back_read_task
				begin: user_0_ar_chn
					user_0_hs_cnt = 0;
					repeat(repeat_rounds) begin
						user_0_arvalid = 1'b0;
						@(posedge axi_clk) begin
							user_0_arvalid = 1'b1;
							user_0_araddr = axi_address;
							user_0_ar_len = axi_ar_len;
							user_0_ar_id  = USER_0_AXI_ID;
						end
						$display("@ %0t , User 0 commenced a single read @address: %0d and %0d burst length",$time,axi_address,axi_ar_len + 1);
						wait(user_0_arvalid && user_0_arready) begin							
							@(posedge axi_clk) user_0_arvalid = 1'b0; user_0_hs_cnt = user_0_hs_cnt + 1;
							$display("@ %0t , User 0 got a read address handshake with the connector, %0d handshakes left",$time,repeat_rounds - user_0_hs_cnt);
						end
					end
				end
				begin: user_0_rd_chn
					repeat(repeat_rounds) begin
						i = 0;
						user_0_last_flag = 0;
						while(i <= axi_ar_len && !user_0_last_flag) begin
							@(posedge axi_clk) begin
								if(user_0_rvalid && user_0_ar_id == USER_0_AXI_ID) begin
									$display("@ %0t , User_0_rd_chn got a new data: %h",$time,user_0_rd_data);
									i = i + 1;
								end
								if(user_0_rlast && user_0_ar_id == USER_0_AXI_ID) begin
									$display("@ %0t , User_0_rd_chn finished a read task",$time);
									user_0_last_flag = 1;
								end
							end
						end
						if(i == axi_ar_len + 1) begin
							$display("@ %0t , a read task of User 0 succeeded",$time);
						end
						else begin
							$display("@ %0t , a read task of User 0 failed because the number of the data got from the arbiter didn't match the predicted one: %0d / %0d",$time,i,axi_ar_len+1);
							user_0_success = 0;
							disable interval_back_to_back_read_task;
						end
					end
					user_0_success = 1;
					$display("@ %0t, the part of User 0 in interval back-to-back read task finished",$time);
				end
				begin: user_1_ar_chn
					user_1_hs_cnt = 0;
					repeat(repeat_rounds) begin
						user_1_arvalid = 1'b0;
						@(posedge axi_clk) begin
							user_1_arvalid = 1'b1;
							user_1_araddr = axi_address;
							user_1_ar_len = axi_ar_len;
							user_1_ar_id  = USER_1_AXI_ID;
						end
						$display("@ %0t , User 1 commenced a single read @address: %0d and %0d burst length",$time,axi_address,axi_ar_len + 1);
						wait(user_1_arvalid && user_1_arready) begin					
							@(posedge axi_clk) user_1_arvalid = 1'b0; user_1_hs_cnt = user_1_hs_cnt + 1;
							$display("@ %0t , User 1 got a read address handshake with the connector, %0d handshakes left",$time,repeat_rounds - user_1_hs_cnt);
						end
					end
				end
				begin: user_1_rd_chn
					repeat(repeat_rounds) begin
						j = 0;
						user_1_last_flag = 0;
						while(j <= axi_ar_len && !user_1_last_flag) begin
							@(posedge axi_clk) begin
								if(user_1_rvalid && user_1_ar_id == USER_1_AXI_ID) begin
									$display("@ %0t , User_1_rd_chn got a new data: %h",$time,user_1_rd_data);
									j = j + 1;
								end
								if(user_1_rlast && user_1_ar_id == USER_1_AXI_ID) begin
									$display("@ %0t , User_1_rd_chn finished a read task",$time);
									user_1_last_flag = 1;
								end
							end
						end
						if(j == axi_ar_len + 1) begin
							$display("@ %0t , a read task of User 1 succeeded",$time);
						end
						else begin
							$display("@ %0t , a read task of User 1 failed because the number of the data got from the arbiter didn't match the predicted one: %0d / %0d",$time,i,axi_ar_len+1);
							user_1_success = 0;
							disable interval_back_to_back_read_task;
						end	
					end
					user_1_success = 1;
					$display("@ %0t, the part of User 1 in interval back-to-back read task finished",$time);
				end
				begin:success_judgement
					wait(user_0_success && user_1_success) begin
						$display("@ %0t , interval back-to-back read task succeeded",$time);
						success = 1;
						disable interval_back_to_back_read_task;
					end
				end 
				begin: timout_monitor
					repeat(repeat_rounds *2* (axi_ar_len+14)) @(posedge axi_clk);
					//握手延迟3个周期，数据传输 len + 1 个周期，外加10个周期的传输响应时间冗余,两个用户同时使用，乘以2
					$display("warning , timeout occured @ %0t",$time);
					success = 0;
					disable interval_back_to_back_read_task;
				end
			join
			if(!success) begin
				$display("@ %0t , task %0d failed",$time,task_id);
				@(posedge axi_clk)  begin
					user_0_arvalid = 1'b0;
					user_0_araddr = 0;
					user_0_ar_len = 0;
					user_0_ar_id  = 0;
					user_1_arvalid = 1'b0;
					user_1_araddr = 0;
					user_1_ar_len = 0;
					user_1_ar_id  = 0;
				end
			end
			else begin
				$display("@ %0t , task %0d succeeded",$time,task_id);
				@(posedge axi_clk)  begin
					user_0_arvalid = 1'b0;
					user_0_araddr = 0;
					user_0_ar_len = 0;
					user_0_ar_id  = 0;
					user_1_arvalid = 1'b0;
					user_1_araddr = 0;
					user_1_ar_len = 0;
					user_1_ar_id  = 0;
				end
			end
		end
	endtask
	
	task user_0_back_to_back_write;
		input 	integer 				task_id;
		input 	integer 				repeat_rounds;
		input 	[AXI_ADDR_WIDTH-1:0]	axi_awaddr;
		input 	[AXI_LEN_WIDTH-1:0]		axi_aw_len;
		output 	reg 					success;
		integer i,hs_cnt;
		reg 	last_flag;
		begin
			success = 0;
			fork : user_0_back_to_back_write_task
				begin : aw_chn
					hs_cnt = 0 ;
					repeat(repeat_rounds) begin
						user_0_awvalid = 0;
						@(posedge axi_clk) begin
							user_0_awvalid = 1'b1;
							user_0_awaddr = axi_awaddr;
							user_0_aw_len = axi_aw_len;
							user_0_aw_id  = USER_0_AXI_ID;
						end
						$display("@ %0t , User 0 commenced a single write @address: %h with %0d burst length",$time,axi_awaddr,axi_aw_len + 1);
						wait(user_0_awvalid && user_0_awready) begin
							@(posedge axi_clk) user_0_awvalid = 1'b0; hs_cnt = hs_cnt + 1;
							$display("@ %0t , User 0 got a write address handshake with the connector, %0d handshakes left",$time,repeat_rounds - hs_cnt);
						end
					end
				end
				begin : wr_chn
					repeat(repeat_rounds) begin
						i = 0 ;
						last_flag = 0;
						while (i < axi_aw_len + 1 && !last_flag) begin
							@(posedge axi_clk) begin
								user_0_wr_data = {28'd0,USER_0_AXI_ID*(28'd16+i)};
								user_0_wstrb = 32'hffffffff;
								if(user_0_wready && user_0_aw_id == USER_0_AXI_ID) begin
									i = i + 1;
									$display("@ %0t , User 0 write a new data to the connector",$time);
								end
								if(user_0_wlast && user_0_aw_id == USER_0_AXI_ID) begin
									$display("@ %0t , User 0 finished the write data request",$time);
									last_flag = 1;
								end
							end
						end
						if(i != axi_aw_len + 1) begin
							$display("@ %0t , a write task of User 0 failed because the number of the data sent to the arbiter didn't match the predicted one: %0d / %0d",$time,i,axi_aw_len+1);
							success = 0;
							disable user_0_back_to_back_write_task;
						end
					end
					$display("@ %0t , a back-to-back write task of user 0 succeeded",$time);
					success = 1;
					disable user_0_back_to_back_write_task;
				end
				begin : timout_monitor
					repeat(repeat_rounds * (axi_aw_len+14)) @(posedge axi_clk); 
					//握手延迟3个周期，数据传输 len + 1 个周期，外加10个周期的传输响应时间冗余,两个用户同时使用，乘以2
					$display("warning , timeout occured @ %0t",$time);
					success = 0;
					disable user_0_back_to_back_write_task;
				end
			join 
			if(!success) begin
				$display("@ %0t , task %0d failed",$time,task_id);
				@(posedge axi_clk)  begin
					user_0_awvalid = 1'b0;
					user_0_awaddr = 0;
					user_0_aw_len = 0;
					user_0_aw_id  = 0;
				end
			end
			else begin
				$display("@ %0t , task %0d succeeded",$time,task_id);
				@(posedge axi_clk)  begin
					user_0_awvalid = 1'b0;
					user_0_awaddr = 0;
					user_0_aw_len = 0;
					user_0_aw_id  = 0;
				end
			end
		end
	endtask
	
	task user_1_back_to_back_write;
		input 	integer 				task_id;
		input 	integer 				repeat_rounds;
		input 	[AXI_ADDR_WIDTH-1:0]	axi_awaddr;
		input 	[AXI_LEN_WIDTH-1:0]		axi_aw_len;
		output 	reg 					success;
		reg 	last_flag;
		integer i, hs_cnt;
		begin
			success = 0;
			fork : user_1_back_to_back_write_task
				begin : aw_chn
					hs_cnt = 0;
					repeat(repeat_rounds) begin
						user_1_awvalid = 0;
						@(posedge axi_clk) begin
							user_1_awvalid = 1'b1;
							user_1_awaddr = axi_awaddr;
							user_1_aw_len = axi_aw_len;
							user_1_aw_id  = USER_1_AXI_ID;
						end
						$display("@ %0t , User 1 commenced a single write @address: %h with %0d burst length",$time,axi_awaddr,axi_aw_len + 1);
						wait(user_1_awvalid && user_1_awready) begin
							@(posedge axi_clk) user_1_awvalid = 1'b0; hs_cnt = hs_cnt + 1;
							$display("@ %0t , User 1 got a write address handshake with the connector, %0d handshakes left",$time,repeat_rounds - hs_cnt);
						end
					end
				end
				begin : wr_chn
					repeat(repeat_rounds) begin
						i = 0 ;
						last_flag = 0;
						while (i < axi_aw_len + 1 &&!last_flag) begin
							@(posedge axi_clk) begin
								user_1_wr_data = {28'd0,USER_1_AXI_ID*(28'd16+i)};
								user_1_wstrb = 32'hffffffff;
								if(user_1_wready && user_1_aw_id == USER_1_AXI_ID) begin
									i = i + 1;
									$display("@ %0t , User 1 write a new data to the connector",$time);
								end
								if(user_1_wlast && user_1_aw_id == USER_1_AXI_ID) begin
									$display("@ %0t , User 1 finished the write data request",$time);
									last_flag = 1;
								end
							end
						end
						if(i != axi_aw_len + 1) begin
							$display("@ %0t , a write task of User 1 failed because the number of the data sent to the arbiter didn't match the predicted one: %0d / %0d",$time,i,axi_aw_len+1);
							success = 0;
							disable user_1_back_to_back_write_task;
						end
					end
					$display("@ %0t , a back-to-back write task of user 1 succeeded",$time);
					success = 1;
					disable user_1_back_to_back_write_task;
				end
				begin : timout_monitor
					repeat(repeat_rounds * (axi_aw_len+14)) begin
						@(posedge axi_clk);
					end	//握手延迟3个周期，数据传输 len + 1 个周期，外加10个周期的传输响应时间冗余,两个用户同时使用，乘以2
					$display("warning , timeout occured @ %0t",$time);
					success = 0;
					disable user_1_back_to_back_write_task;
				end
			join 
			if(!success) begin
				$display("@ %0t , task %0d failed",$time,task_id);
				@(posedge axi_clk)  begin
					user_1_awvalid = 1'b0;
					user_1_awaddr = 0;
					user_1_aw_len = 0;
					user_1_aw_id  = 0;
				end
			end
			else begin
				$display("@ %0t , task %0d succeeded",$time,task_id);
				@(posedge axi_clk)  begin
					user_1_awvalid = 1'b0;
					user_1_awaddr = 0;
					user_1_aw_len = 0;
					user_1_aw_id  = 0;
				end
			end
		end
	endtask
	
	task interval_back_to_back_write;
		input 	integer 				task_id;
		input 	integer 				repeat_rounds;
		input 	[AXI_ADDR_WIDTH-1:0]	axi_awaddr;
		input 	[AXI_LEN_WIDTH-1:0]		axi_aw_len;
		output 	reg 					success;
		integer i,j;
		integer user_0_hs_cnt, user_1_hs_cnt;
		reg user_0_success, user_1_success;
		reg user_0_last_flag , user_1_last_flag;
		begin 
			success = 0;
			user_0_success = 0;
			user_1_success = 0;
			fork : interval_back_to_back_write_task
				begin : user_0_aw_chn
					user_0_hs_cnt = 0;
					repeat(repeat_rounds) begin
						user_0_awvalid = 0;
						@(posedge axi_clk) begin
							user_0_awvalid = 1'b1;
							user_0_awaddr = axi_awaddr;
							user_0_aw_len = axi_aw_len;
							user_0_aw_id  = USER_0_AXI_ID;
						end
						$display("@ %0t , User 0 commenced a single write @address: %h with %0d burst length",$time,axi_awaddr,axi_aw_len + 1);
						wait(user_0_awvalid && user_0_awready) begin
							@(posedge axi_clk) user_0_awvalid = 1'b0; user_0_hs_cnt = user_0_hs_cnt + 1;
							$display("@ %0t , User 0 got a write address handshake with the connector, %0d handshakes left",$time,repeat_rounds - user_0_hs_cnt);
						end
					end
				end
				begin : user_0_wr_chn
					repeat(repeat_rounds) begin
						i = 0;
						user_0_last_flag = 0;
						while (i < axi_aw_len + 1 && !user_0_last_flag) begin
							@(posedge axi_clk) begin
								user_0_wr_data = {28'd0,USER_0_AXI_ID*(28'd16+i)};
								user_0_wstrb = 32'hffffffff;
								if(user_0_wready && user_0_aw_id == USER_0_AXI_ID) begin
									i = i + 1;
									$display("@ %0t , User 0 write a new data to the connector",$time);
								end
								if(user_0_wlast && user_0_aw_id == USER_0_AXI_ID) begin
									$display("@ %0t , User 0 finished the write data request",$time);
									user_0_last_flag = 1;
								end
							end
						end
						if(i != axi_aw_len + 1) begin
							$display("@ %0t , a write task of User 0 failed because the number of the data sent to the arbiter didn't match the predicted one: %0d / %0d",$time,i,axi_aw_len+1);
							user_0_success = 0;
							disable interval_back_to_back_write_task;
						end
					end
					user_0_success = 1;
					$display("@ %0t, the part of User 0 in interval back-to-back write task finished",$time);
				end
				begin : user_1_aw_chn
					user_1_hs_cnt = 0;
					repeat(repeat_rounds) begin
						user_1_awvalid = 0;
						@(posedge axi_clk) begin
							user_1_awvalid = 1'b1;
							user_1_awaddr = axi_awaddr;
							user_1_aw_len = axi_aw_len;
							user_1_aw_id  = USER_1_AXI_ID;
						end
						$display("@ %0t , User 1 commenced a single write @address: %h with %0d burst length",$time,axi_awaddr,axi_aw_len + 1);
						wait(user_1_awvalid && user_1_awready) begin
							@(posedge axi_clk) user_1_awvalid = 1'b0; user_1_hs_cnt = user_1_hs_cnt + 1;
							$display("@ %0t , User 1 got a write address handshake with the connector, %0d handshakes left",$time,repeat_rounds - user_1_hs_cnt);
						end
					end
				end
				begin : user_1_wr_chn
					repeat(repeat_rounds) begin
						j = 0;
						user_1_last_flag = 0;
						while (j < axi_aw_len + 1 && !user_1_last_flag) begin
							@(posedge axi_clk) begin
								user_1_wr_data = {28'd0,USER_1_AXI_ID*(28'd16+j)};
								user_1_wstrb = 32'hffffffff;
								if(user_1_wready && user_1_aw_id == USER_1_AXI_ID) begin
									j = j + 1;
									$display("@ %0t , User 1 write a new data to the connector",$time);
								end
								if(user_1_wlast && user_1_aw_id == USER_1_AXI_ID) begin
									$display("@ %0t , User 1 finished the write data request",$time);
									user_1_last_flag = 1;
								end
							end
						end
						if(j != axi_aw_len + 1) begin
							$display("@ %0t , a write task of User 1 failed because the number of the data sent to the arbiter didn't match the predicted one: %0d / %0d",$time,j,axi_aw_len+1);
							user_1_success = 0;
							disable interval_back_to_back_write_task;
						end
					end
					user_1_success = 1;
					$display("@ %0t, the part of User 1 in interval back-to-back write task finished",$time);
				end
				begin:success_judgement
					wait(user_0_success && user_1_success) begin
						$display("@ %0t , interval back-to-back write task succeeded",$time);
						success = 1;
						disable interval_back_to_back_write_task;
					end
				end 
				begin : timout_monitor
					repeat(repeat_rounds * 2 * (axi_aw_len+14)) begin
						@(posedge axi_clk);
					end	//握手延迟3个周期，数据传输 len + 1 个周期，外加10个周期的传输响应时间冗余,两个用户同时使用，乘以2
					$display("warning , timeout occured @ %0t",$time);
					success = 0;
					disable interval_back_to_back_write_task;
				end
			join
			if(!success) begin
				$display("@ %0t , task %0d failed ",$time,task_id);
				@(posedge axi_clk)  begin
					user_0_awvalid = 1'b0;
					user_0_awaddr = 0;
					user_0_aw_len = 0;
					user_0_aw_id  = 0;
					user_1_awvalid = 1'b0;
					user_1_awaddr = 0;
					user_1_aw_len = 0;
					user_1_aw_id  = 0;
				end
			end
			else begin
				$display("@ %0t , task %0d succeeded ",$time,task_id);
				@(posedge axi_clk)  begin
					user_0_awvalid = 1'b0;
					user_0_awaddr = 0;
					user_0_aw_len = 0;
					user_0_aw_id  = 0;
					user_1_awvalid = 1'b0;
					user_1_awaddr = 0;
					user_1_aw_len = 0;
					user_1_aw_id  = 0;
				end
			end
		end
	endtask
	// ------------------------------ verification ------------------------------
	// 覆盖率收集变量
	integer 							total_task_count		;
	integer 							passed_task_count		;
	integer 							failed_task_count		;
	reg 								task_success_flag		;
	
	// 任务结果记录
	integer 							passed_task_id	[0:63]	;
	integer 							failed_task_id	[0:63]	;
	integer 							passed_idx				;
	integer 							failed_idx				;
	
	// 测试任务参数
	parameter	TEST_INTERVAL_CYCLES	=	50					;
	parameter	TEST_TIMEOUT			=	1000				;
	
	// 复位序列
	initial begin
		rst_n = 1'b0;
		$display("@ %0t , [Verification] Reset asserted, holding for 100ns...", $time);
		#100;
		rst_n = 1'b1;
		$display("@ %0t , [Verification] Reset released, starting test sequence...", $time);
		
		// 初始化覆盖率变量
		total_task_count = 0;
		passed_task_count = 0;
		failed_task_count = 0;
		passed_idx = 0;
		failed_idx = 0;
		
		// 等待复位稳定
		repeat(10) @(posedge axi_clk);
		
		// ==================== 测试序列开始 ====================
		$display("\n==================== Verification Test Sequence Start ====================\n");
		
		// -------------------- Task 1: User 0 单次读测试 --------------------
		total_task_count = total_task_count + 1;
		$display("@ %0t , [Verification] Starting Task %0d: User 0 single read test", $time, total_task_count);
		user_0_single_read(total_task_count,28'h001_0000,4'd0,TEST_TIMEOUT,task_success_flag);
		if (task_success_flag) begin
			passed_task_count = passed_task_count + 1;
			passed_task_id[passed_idx] = total_task_count;
			passed_idx = passed_idx + 1;
		end
		else begin
			failed_task_count = failed_task_count + 1;
			failed_task_id[failed_idx] = total_task_count;
			failed_idx = failed_idx + 1;
		end
		repeat(TEST_INTERVAL_CYCLES) @(posedge axi_clk);
		
		// -------------------- Task 2: User 1 单次读测试 --------------------
		total_task_count = total_task_count + 1;
		$display("@ %0t , [Verification] Starting Task %0d: User 1 single read test", $time, total_task_count);
		user_1_single_read(
			total_task_count,
			28'h0020000,
			4'd1,
			TEST_TIMEOUT,
			task_success_flag
		);
		if (task_success_flag) begin
			passed_task_count = passed_task_count + 1;
			passed_task_id[passed_idx] = total_task_count;
			passed_idx = passed_idx + 1;
		end
		else begin
			failed_task_count = failed_task_count + 1;
			failed_task_id[failed_idx] = total_task_count;
			failed_idx = failed_idx + 1;
		end
		repeat(TEST_INTERVAL_CYCLES) @(posedge axi_clk);
		
		// -------------------- Task 3: User 0 单次写测试 --------------------
		total_task_count = total_task_count + 1;
		$display("@ %0t , [Verification] Starting Task %0d: User 0 single write test", $time, total_task_count);
		user_0_single_write(
			total_task_count,
			28'h0030000,
			4'd0,
			TEST_TIMEOUT,
			task_success_flag
		);
		if (task_success_flag) begin
			passed_task_count = passed_task_count + 1;
			passed_task_id[passed_idx] = total_task_count;
			passed_idx = passed_idx + 1;
		end
		else begin
			failed_task_count = failed_task_count + 1;
			failed_task_id[failed_idx] = total_task_count;
			failed_idx = failed_idx + 1;
		end
		repeat(TEST_INTERVAL_CYCLES) @(posedge axi_clk);
		
		// -------------------- Task 4: User 1 单次写测试 --------------------
		total_task_count = total_task_count + 1;
		$display("@ %0t , [Verification] Starting Task %0d: User 1 single write test", $time, total_task_count);
		user_1_single_write(
			total_task_count,
			28'h0040000,
			4'd1,
			TEST_TIMEOUT,
			task_success_flag
		);
		if (task_success_flag) begin
			passed_task_count = passed_task_count + 1;
			passed_task_id[passed_idx] = total_task_count;
			passed_idx = passed_idx + 1;
		end
		else begin
			failed_task_count = failed_task_count + 1;
			failed_task_id[failed_idx] = total_task_count;
			failed_idx = failed_idx + 1;
		end
		repeat(TEST_INTERVAL_CYCLES) @(posedge axi_clk);
		
		// -------------------- Task 5: User 0 背靠背读测试 --------------------
		total_task_count = total_task_count + 1;
		$display("@ %0t , [Verification] Starting Task %0d: User 0 back-to-back read test", $time, total_task_count);
		user_0_back_to_back_read(
			total_task_count,
			28'h0050000,
			3,
			4'd1,
			task_success_flag
		);
		if (task_success_flag) begin
			passed_task_count = passed_task_count + 1;
			passed_task_id[passed_idx] = total_task_count;
			passed_idx = passed_idx + 1;
		end
		else begin
			failed_task_count = failed_task_count + 1;
			failed_task_id[failed_idx] = total_task_count;
			failed_idx = failed_idx + 1;
		end
		repeat(TEST_INTERVAL_CYCLES) @(posedge axi_clk);
		
		// -------------------- Task 6: User 1 背靠背读测试 --------------------
		total_task_count = total_task_count + 1;
		$display("@ %0t , [Verification] Starting Task %0d: User 1 back-to-back read test", $time, total_task_count);
		user_1_back_to_back_read(
			total_task_count,
			28'h0060000,
			2,
			4'd2,
			task_success_flag
		);
		if (task_success_flag) begin
			passed_task_count = passed_task_count + 1;
			passed_task_id[passed_idx] = total_task_count;
			passed_idx = passed_idx + 1;
		end
		else begin
			failed_task_count = failed_task_count + 1;
			failed_task_id[failed_idx] = total_task_count;
			failed_idx = failed_idx + 1;
		end
		repeat(TEST_INTERVAL_CYCLES) @(posedge axi_clk);
		
		// -------------------- Task 7: User 0 背靠背写测试 --------------------
		total_task_count = total_task_count + 1;
		$display("@ %0t , [Verification] Starting Task %0d: User 0 back-to-back write test", $time, total_task_count);
		user_0_back_to_back_write(
			total_task_count,
			2,
			28'h0070000,
			4'd1,
			task_success_flag
		);
		if (task_success_flag) begin
			passed_task_count = passed_task_count + 1;
			passed_task_id[passed_idx] = total_task_count;
			passed_idx = passed_idx + 1;
		end
		else begin
			failed_task_count = failed_task_count + 1;
			failed_task_id[failed_idx] = total_task_count;
			failed_idx = failed_idx + 1;
		end
		repeat(TEST_INTERVAL_CYCLES) @(posedge axi_clk);
		
		// -------------------- Task 8: User 1 背靠背写测试 --------------------
		total_task_count = total_task_count + 1;
		$display("@ %0t , [Verification] Starting Task %0d: User 1 back-to-back write test", $time, total_task_count);
		user_1_back_to_back_write(
			total_task_count,
			2,
			28'h0080000,
			4'd2,
			task_success_flag
		);
		if (task_success_flag) begin
			passed_task_count = passed_task_count + 1;
			passed_task_id[passed_idx] = total_task_count;
			passed_idx = passed_idx + 1;
		end
		else begin
			failed_task_count = failed_task_count + 1;
			failed_task_id[failed_idx] = total_task_count;
			failed_idx = failed_idx + 1;
		end
		repeat(TEST_INTERVAL_CYCLES) @(posedge axi_clk);
		
		// -------------------- Task 9: 交替背靠背读测试 --------------------
		total_task_count = total_task_count + 1;
		$display("@ %0t , [Verification] Starting Task %0d: Interval back-to-back read test", $time, total_task_count);
		interval_back_to_back_read(
			total_task_count,
			28'h0090000,
			2,
			4'd1,
			task_success_flag
		);
		if (task_success_flag) begin
			passed_task_count = passed_task_count + 1;
			passed_task_id[passed_idx] = total_task_count;
			passed_idx = passed_idx + 1;
		end
		else begin
			failed_task_count = failed_task_count + 1;
			failed_task_id[failed_idx] = total_task_count;
			failed_idx = failed_idx + 1;
		end
		repeat(TEST_INTERVAL_CYCLES) @(posedge axi_clk);
		
		// -------------------- Task 10: 交替背靠背写测试 --------------------
		total_task_count = total_task_count + 1;
		$display("@ %0t , [Verification] Starting Task %0d: Interval back-to-back write test", $time, total_task_count);
		interval_back_to_back_write(
			total_task_count,
			2,
			28'h00A0000,
			4'd1,
			task_success_flag
		);
		if (task_success_flag) begin
			passed_task_count = passed_task_count + 1;
			passed_task_id[passed_idx] = total_task_count;
			passed_idx = passed_idx + 1;
		end
		else begin
			failed_task_count = failed_task_count + 1;
			failed_task_id[failed_idx] = total_task_count;
			failed_idx = failed_idx + 1;
		end
		repeat(TEST_INTERVAL_CYCLES) @(posedge axi_clk);
		
		// ==================== 测试序列结束 ====================
		$display("\n==================== Verification Test Sequence End ====================\n");
		
		// 输出覆盖率报告
		$display("\n==================== Coverage Report ====================");
		$display("Total Tasks:    %0d", total_task_count);
		$display("Passed Tasks:   %0d", passed_task_count);
		$display("Failed Tasks:   %0d", failed_task_count);
		$display("Pass Rate:      %.2f%%", (real'(passed_task_count) / real'(total_task_count)) * 100.0);
		
		// 输出成功的任务ID
		$display("\n--- Passed Task IDs ---");
		
		if (passed_task_count > 0) begin
			for (i = 0; i < passed_idx; i = i + 1) begin
				$display("  Task %0d: PASSED", passed_task_id[i]);
			end
		end
		else begin
			$display("  No passed tasks");
		end
		
		// 输出失败的任务ID
		$display("\n--- Failed Task IDs ---");
		if (failed_task_count > 0) begin
			for (i = 0; i < failed_idx; i = i + 1) begin
				$display("  Task %0d: FAILED", failed_task_id[i]);
			end
		end
		else begin
			$display("  No failed tasks");
		end
		$display("========================================================\n");
		
		// 输出仲裁器行为记录
		print_arbiter_statistics();
		
		// 仿真结束
		$display("@ %0t , [Verification] All tests completed. Simulation finished.", $time);
		$finish;
	end
	
	// ------------------------------ arbiter behavior model ------------------------------
	// 参照 axi_arbitor_double_master_one_slave 的上层行为逻辑
	// 使用堆栈缓存地址信息，地址通道和数据通道独立工作
	
	// ==================== 读通道 ====================
	// 堆栈定义
	parameter 	RD_STACK_DEPTH		=	8											;
	parameter 	RD_STACK_PTR_WIDTH	=	4											;
	
	reg 	[AXI_ADDR_WIDTH-1:0]	rd_stack_addr_mem	[0:RD_STACK_DEPTH-1]			;
	reg 	[AXI_ID_WIDTH-1:0]		rd_stack_id_mem		[0:RD_STACK_DEPTH-1]			;
	reg 	[AXI_LEN_WIDTH-1:0]		rd_stack_len_mem	[0:RD_STACK_DEPTH-1]			;
	reg 	[RD_STACK_PTR_WIDTH-1:0]	rd_stack_ptr										;
	
	wire 							rd_stack_empty										;
	wire 							rd_stack_full										;
	wire 	[AXI_ADDR_WIDTH-1:0]	rd_stack_top_addr									;
	wire 	[AXI_ID_WIDTH-1:0]		rd_stack_top_id										;
	wire 	[AXI_LEN_WIDTH-1:0]		rd_stack_top_len									;
	
	assign rd_stack_empty		= (rd_stack_ptr == 0)										;
	assign rd_stack_full		= (rd_stack_ptr == RD_STACK_DEPTH)							;
	assign rd_stack_top_addr	= rd_stack_addr_mem[rd_stack_ptr - 1]						;
	assign rd_stack_top_id		= rd_stack_id_mem[rd_stack_ptr - 1]						;
	assign rd_stack_top_len		= rd_stack_len_mem[rd_stack_ptr - 1]						;
	
	// 读地址通道 - 堆栈指针管理
	wire rd_addr_hs = arbiter_arvalid && arbiter_arready							;
	wire rd_data_last = arbiter_rvalid && arbiter_rlast							;
	
	always @(posedge axi_clk) begin
		if (!rst_n) begin
			rd_stack_ptr <= 0;
		end
		else begin
			case ({rd_addr_hs, rd_data_last})
				2'b10: begin
					rd_stack_addr_mem[rd_stack_ptr]	<= arbiter_araddr;
					rd_stack_id_mem[rd_stack_ptr]	<= arbiter_ar_id;
					rd_stack_len_mem[rd_stack_ptr]	<= arbiter_ar_len;
					rd_stack_ptr <= rd_stack_ptr + 1'b1;
				end
				2'b01: begin
					rd_stack_ptr <= rd_stack_ptr - 1'b1;
				end
				default: rd_stack_ptr <= rd_stack_ptr;
			endcase
		end
	end
	
	// 读地址通道ready信号
	always @(posedge axi_clk) begin
		if (!rst_n) begin
			arbiter_arready <= 1'b0;
		end
		else begin
			arbiter_arready <= !rd_stack_full;
		end
	end
	
	// 读数据通道 - busy标志和临时寄存器
	reg 							rd_chn_busy_flag									;
	reg 	[AXI_ID_WIDTH-1:0]		rd_id_temp											;
	reg 	[AXI_LEN_WIDTH-1:0]		rd_len_temp											;
	reg 	[AXI_ADDR_WIDTH-1:0]	rd_addr_temp										;
	reg 	[AXI_LEN_WIDTH:0]		rd_dcnt												;
	
	// 读数据通道busy_flag和临时寄存器管理
	always @(posedge axi_clk) begin
		if (!rst_n) begin
			rd_chn_busy_flag	<= 1'b0;
			rd_id_temp			<= 0;
			rd_len_temp			<= 0;
			rd_addr_temp		<= 0;
		end
		else begin
			if (!rd_chn_busy_flag && !rd_stack_empty) begin
				rd_chn_busy_flag	<= 1'b1;
				rd_id_temp			<= rd_stack_top_id;
				rd_len_temp			<= rd_stack_top_len;
				rd_addr_temp		<= rd_stack_top_addr;
			end
			else if (rd_chn_busy_flag && arbiter_rlast) begin
				rd_chn_busy_flag	<= 1'b0;
			end
		end
	end
	
	// 读数据通道dcnt管理
	always @(posedge axi_clk) begin
		if (!rst_n) begin
			rd_dcnt <= 0;
		end
		else begin
			if (arbiter_rlast) begin
				rd_dcnt <= 0;
			end
			else if (arbiter_rvalid) begin
				rd_dcnt <= rd_dcnt + 1'b1;
			end
		end
	end
	
	// 读数据通道输出信号
	always @(posedge axi_clk) begin
		if (!rst_n) begin
			arbiter_rvalid	<= 1'b0;
			arbiter_rd_data	<= 0;
			arbiter_rd_id	<= 0;
		end
		else begin
			if (rd_chn_busy_flag && !arbiter_rlast) begin
				arbiter_rvalid	<= 1'b1;
				arbiter_rd_data	<= {AXI_DATA_WIDTH{1'b1}} & (rd_addr_temp + rd_dcnt);
				arbiter_rd_id	<= rd_id_temp;
			end
			else begin
				arbiter_rvalid	<= 1'b0;
			end
		end
	end
	
	always@(*) begin
		arbiter_rlast = 0;
		if(rd_dcnt == rd_len_temp && arbiter_rvalid) begin
			arbiter_rlast = 1;
		end
	end	
	// ==================== 写通道 ====================
	// 堆栈定义
	parameter 	WR_STACK_DEPTH		=	8											;
	parameter 	WR_STACK_PTR_WIDTH	=	4											;
	
	reg 	[AXI_ADDR_WIDTH-1:0]	wr_stack_addr_mem	[0:WR_STACK_DEPTH-1]			;
	reg 	[AXI_ID_WIDTH-1:0]		wr_stack_id_mem		[0:WR_STACK_DEPTH-1]			;
	reg 	[AXI_LEN_WIDTH-1:0]		wr_stack_len_mem	[0:WR_STACK_DEPTH-1]			;
	reg 	[WR_STACK_PTR_WIDTH-1:0]	wr_stack_ptr										;
	
	wire 							wr_stack_empty										;
	wire 							wr_stack_full										;
	wire 	[AXI_ADDR_WIDTH-1:0]	wr_stack_top_addr									;
	wire 	[AXI_ID_WIDTH-1:0]		wr_stack_top_id										;
	wire 	[AXI_LEN_WIDTH-1:0]		wr_stack_top_len									;
	
	assign wr_stack_empty		= (wr_stack_ptr == 0)										;
	assign wr_stack_full		= (wr_stack_ptr == WR_STACK_DEPTH)							;
	assign wr_stack_top_addr	= wr_stack_addr_mem[wr_stack_ptr - 1]						;
	assign wr_stack_top_id		= wr_stack_id_mem[wr_stack_ptr - 1]						;
	assign wr_stack_top_len		= wr_stack_len_mem[wr_stack_ptr - 1]						;
	
	// 写地址通道 - 堆栈指针管理
	wire wr_addr_hs = arbiter_awvalid && arbiter_awready							;
	wire wr_data_last = arbiter_wready && arbiter_wlast							;
	
	always @(posedge axi_clk) begin
		if (!rst_n) begin
			wr_stack_ptr <= 0;
		end
		else begin
			case ({wr_addr_hs, wr_data_last})
				2'b10: begin
					wr_stack_addr_mem[wr_stack_ptr]	<= arbiter_awaddr;
					wr_stack_id_mem[wr_stack_ptr]	<= arbiter_aw_id;
					wr_stack_len_mem[wr_stack_ptr]	<= arbiter_aw_len;
					wr_stack_ptr <= wr_stack_ptr + 1'b1;
				end
				2'b01: begin
					wr_stack_ptr <= wr_stack_ptr - 1'b1;
				end
				default: wr_stack_ptr <= wr_stack_ptr;
			endcase
		end
	end
	
	// 写地址通道ready信号
	always @(posedge axi_clk) begin
		if (!rst_n) begin
			arbiter_awready <= 1'b0;
		end
		else begin
			arbiter_awready <= !wr_stack_full;
		end
	end
	
	// 写数据通道 - busy标志和临时寄存器
	reg 							wr_chn_busy_flag									;
	reg 	[AXI_ID_WIDTH-1:0]		wr_id_temp											;
	reg 	[AXI_LEN_WIDTH-1:0]		wr_len_temp											;
	reg 	[AXI_LEN_WIDTH:0]		wr_dcnt												;
	
	// 写数据通道busy_flag和临时寄存器管理
	always @(posedge axi_clk) begin
		if (!rst_n) begin
			wr_chn_busy_flag	<= 1'b0;
			wr_id_temp			<= 0;
			wr_len_temp			<= 0;
		end
		else begin
			if (!wr_chn_busy_flag && !wr_stack_empty) begin
				wr_chn_busy_flag	<= 1'b1;
				wr_id_temp			<= wr_stack_top_id;
				wr_len_temp			<= wr_stack_top_len;
			end
			else if (wr_chn_busy_flag && arbiter_wlast) begin
				wr_chn_busy_flag	<= 1'b0;
			end
		end
	end
	
	// 写数据通道dcnt管理
	always @(posedge axi_clk) begin
		if (!rst_n) begin
			wr_dcnt <= 0;
		end
		else begin
			if (arbiter_wlast) begin
				wr_dcnt <= 0;
			end
			else if (arbiter_wready) begin
				wr_dcnt <= wr_dcnt + 1'b1;
			end
			
		end
	end
	
	// 写数据通道输出信号
	always @(posedge axi_clk) begin
		if (!rst_n) begin
			arbiter_wready	<= 1'b0;
			arbiter_wr_id	<= 0;
		end
		else begin
			if (wr_chn_busy_flag && !arbiter_wlast) begin
				arbiter_wready	<= 1'b1;
				arbiter_wr_id	<= wr_id_temp;
			end
			else begin
				arbiter_wready	<= 1'b0;
			end
		end
	end
	always@(*) begin
		arbiter_wlast = 0;
		if(wr_dcnt == wr_len_temp && arbiter_wready) begin
			arbiter_wlast = 1;
		end
	end	
	// ==================== 行为记录 ====================
	integer 							ar_transaction_cnt		;
	integer 							aw_transaction_cnt		;
	integer 							bh_rd_data_cnt				;
	integer 							bh_wr_data_cnt				;
	
	reg 	[AXI_ADDR_WIDTH-1:0]		ar_addr_record	[0:255]	;
	reg 	[AXI_ID_WIDTH-1:0]			ar_id_record	[0:255]	;
	reg 	[AXI_LEN_WIDTH-1:0]			ar_len_record	[0:255]	;
	integer 							ar_handshake_time	[0:255];
	
	reg 	[AXI_ADDR_WIDTH-1:0]		aw_addr_record	[0:255]	;
	reg 	[AXI_ID_WIDTH-1:0]			aw_id_record	[0:255]	;
	reg 	[AXI_LEN_WIDTH-1:0]			aw_len_record	[0:255]	;
	integer 							aw_handshake_time	[0:255];
	
	integer 							rd_burst_len_record	[0:255];
	integer 							wr_burst_len_record	[0:255];
	
	// 读地址握手记录
	always @(posedge axi_clk) begin
		if (!rst_n) begin
			ar_transaction_cnt <= 0;
		end
		else if (arbiter_arvalid && arbiter_arready) begin
			ar_addr_record[ar_transaction_cnt]	<= arbiter_araddr;
			ar_id_record[ar_transaction_cnt]	<= arbiter_ar_id;
			ar_len_record[ar_transaction_cnt]	<= arbiter_ar_len;
			ar_handshake_time[ar_transaction_cnt] <= $time;
			$display("@ %0t , [Arbiter] AR handshake: addr=%h, id=%h, len=%0d", 
				$time, arbiter_araddr, arbiter_ar_id, arbiter_ar_len + 1);
			ar_transaction_cnt <= ar_transaction_cnt + 1;
		end
	end
	
	// 读数据完成记录
	always @(posedge axi_clk) begin
		if (!rst_n) begin
			bh_rd_data_cnt <= 0;
		end
		else if (arbiter_rvalid && arbiter_rlast) begin
			rd_burst_len_record[ar_transaction_cnt - 1] <= bh_rd_data_cnt + 1;
			$display("@ %0t , [Arbiter] Read burst completed: total %0d data transferred", $time, bh_rd_data_cnt + 1);
			bh_rd_data_cnt <= 0;
		end
		else if (arbiter_rvalid) begin
			bh_rd_data_cnt <= bh_rd_data_cnt + 1;
		end
	end
	
	// 写地址握手记录
	always @(posedge axi_clk) begin
		if (!rst_n) begin
			aw_transaction_cnt <= 0;
		end
		else if (arbiter_awvalid && arbiter_awready) begin
			aw_addr_record[aw_transaction_cnt]	<= arbiter_awaddr;
			aw_id_record[aw_transaction_cnt]	<= arbiter_aw_id;
			aw_len_record[aw_transaction_cnt]	<= arbiter_aw_len;
			aw_handshake_time[aw_transaction_cnt] <= $time;
			$display("@ %0t , [Arbiter] AW handshake: addr=%h, id=%h, len=%0d", 
				$time, arbiter_awaddr, arbiter_aw_id, arbiter_aw_len + 1);
			aw_transaction_cnt <= aw_transaction_cnt + 1;
		end
	end
	
	// 写数据完成记录
	always @(posedge axi_clk) begin
		if (!rst_n) begin
			bh_wr_data_cnt <= 0;
		end
		else if (arbiter_wready && arbiter_wlast) begin
			wr_burst_len_record[aw_transaction_cnt - 1] <= bh_wr_data_cnt + 1;
			bh_wr_data_cnt <= 0;
		end
		else if (arbiter_wready) begin
			bh_wr_data_cnt <= bh_wr_data_cnt + 1;
		end
	end
	
	// 行为统计报告任务
	task print_arbiter_statistics;
		integer i;
		begin
			$display("\n==================== Arbiter Behavior Statistics ====================");
			$display("Total AR transactions: %0d", ar_transaction_cnt);
			$display("Total AW transactions: %0d", aw_transaction_cnt);
			$display("Total read data transferred: %0d", bh_rd_data_cnt);
			$display("Total write data transferred: %0d", bh_wr_data_cnt);
			
			$display("\n--- Read Address Channel Records ---");
			for (i = 0; i < ar_transaction_cnt; i = i + 1) begin
				$display("  AR[%0d]: addr=%h, id=%h, len=%0d, handshake_time=%0t", 
					i, ar_addr_record[i], ar_id_record[i], ar_len_record[i] + 1,
					ar_handshake_time[i]);
			end
			
			$display("\n--- Write Address Channel Records ---");
			for (i = 0; i < aw_transaction_cnt; i = i + 1) begin
				$display("  AW[%0d]: addr=%h, id=%h, len=%0d, handshake_time=%0t", 
					i, aw_addr_record[i], aw_id_record[i], aw_len_record[i] + 1,
					aw_handshake_time[i]);
			end
			
			$display("\n--- Burst Length Records ---");
			$display("Read burst lengths:");
			for (i = 0; i < ar_transaction_cnt; i = i + 1) begin
				$display("  AR[%0d]: expected=%0d, actual=%0d", 
					i, ar_len_record[i] + 1, rd_burst_len_record[i]);
			end
			$display("Write burst lengths:");
			for (i = 0; i < aw_transaction_cnt; i = i + 1) begin
				$display("  AW[%0d]: expected=%0d, actual=%0d", 
					i, aw_len_record[i] + 1, wr_burst_len_record[i]);
			end
			$display("====================================================================\n");
		end
	endtask
	
endmodule 