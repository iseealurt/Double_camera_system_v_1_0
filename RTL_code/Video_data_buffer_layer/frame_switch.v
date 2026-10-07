module frame_switch#(
	parameter 	AXI_ADDR_WIDTH	=	28		,
				DDR_DQ_WIDTH	=	32		,
				PIX_DATA_WIDTH	=	16		,
				FRAME_WIDTH		=	640		,
				FRAME_HEIGHT	=	480		,						
				BUFFER_OFFSET 	= 	28'd0	,
				BUFFER_INTERVAL	=	10	
)(
    input   wire               			 	axi_clk				,
    input   wire                			ddr_init_done		,
    input   wire                			stream_rst_n		,	
    input   wire                			wr_end				/*synthesis PAP_MARK_DEBUG="true"*/,
    input   wire                			rd_end				/*synthesis PAP_MARK_DEBUG="true"*/,
	output 	reg 	[4:0]					test_signal			,
    output  reg     [AXI_ADDR_WIDTH-1:0]    write_buffer_offset	/*synthesis PAP_MARK_DEBUG="true"*/,
    output  reg     [AXI_ADDR_WIDTH-1:0]	read_buffer_offset  /*synthesis PAP_MARK_DEBUG="true"*/   
);

	localparam 	BUFFER_SIZE = FRAME_HEIGHT * FRAME_WIDTH * PIX_DATA_WIDTH / DDR_DQ_WIDTH;
	localparam 	BUFFER0 	= BUFFER_OFFSET;
	localparam	BUFFER1 	= BUFFER0 + BUFFER_SIZE + (1<<BUFFER_INTERVAL);
	localparam	BUFFER2 	= BUFFER1 + BUFFER_SIZE + (1<<BUFFER_INTERVAL);
	
    // 内部信号定义
    reg     [1:0]   cmr_vref_reg;
	reg 	[2:0]	buf_valid_flag;
	reg 	[2:0]	buf_write_flag;
	reg 	[2:0]	buf_read_flag;
    reg     [1:0]   display_vsync_reg;
    wire            cmr_vref_pose;
    wire            display_vsync_pose;
    // 缓冲区状态寄存器

    
    // 边沿检测
    always @(posedge axi_clk) begin
        if (!stream_rst_n) begin
            cmr_vref_reg <= 2'b00;
            display_vsync_reg <= 2'b00;
        end else begin
            cmr_vref_reg <= {cmr_vref_reg,wr_end};
            display_vsync_reg <= {display_vsync_reg,rd_end};
        end
    end
    
    assign cmr_vref_pose = cmr_vref_reg == 2'b01;
    assign display_vsync_pose = display_vsync_reg == 2'b01;
    
	
    always @(posedge axi_clk) begin
        if (!ddr_init_done) begin
            write_buffer_offset <= BUFFER0;
			read_buffer_offset  <= BUFFER2;
			buf_valid_flag <= 3'b000;
			buf_read_flag <= 3'b100;
			buf_write_flag <= 3'b001;
			test_signal <= 5'd0;
        end
        else if (stream_rst_n) begin
			if(cmr_vref_pose && !display_vsync_pose) begin
				if(!buf_read_flag[2] && !buf_valid_flag[2] &&!buf_write_flag[2]) begin
					case(write_buffer_offset)
						BUFFER0: begin
							buf_write_flag[0] <= 1'b0;
							buf_valid_flag[0] <= 1'b1;
							buf_write_flag[2] <= 1'b1;
							write_buffer_offset <= BUFFER2;
						end
						BUFFER1: begin
							buf_write_flag[1] <= 1'b0;
							buf_valid_flag[1] <= 1'b1;
							buf_write_flag[2] <= 1'b1;
							write_buffer_offset <= BUFFER2;
						end
						BUFFER2: begin
							//error
							test_signal <= 5'd1;
						end
						default: begin
							//error
							test_signal <= 5'd2;
						end
					endcase
				end
				else if(!buf_read_flag[1] && !buf_valid_flag[1] && !buf_write_flag[1]) begin
					case(write_buffer_offset)
						BUFFER0: begin
							buf_write_flag[0] <= 1'b0;
							buf_valid_flag[0] <= 1'b1;
							buf_write_flag[1] <= 1'b1;
							write_buffer_offset <= BUFFER1;
						end
						BUFFER1: begin
							//error
							test_signal <= 5'd3;
						end
						BUFFER2: begin
							buf_write_flag[2] <= 1'b0;
							buf_valid_flag[2] <= 1'b1;
							buf_write_flag[1] <= 1'b1;
							write_buffer_offset <= BUFFER1;
						end
						default: begin
							//error
							test_signal <= 5'd4;
						end
					endcase
				end
				else if(!buf_read_flag[0] && !buf_valid_flag[0] && !buf_write_flag[0]) begin
					case(write_buffer_offset)
						BUFFER0: begin
							//error
							test_signal <= 5'd5;
						end
						BUFFER1: begin
							buf_write_flag[1] <= 1'b0;
							buf_valid_flag[1] <= 1'b1;
							buf_write_flag[0] <= 1'b1;
							write_buffer_offset <= BUFFER0;
						end
						BUFFER2: begin
							buf_write_flag[2] <= 1'b0;
							buf_valid_flag[2] <= 1'b1;
							buf_write_flag[0] <= 1'b1;
							write_buffer_offset <= BUFFER0;
						end
						default: begin
							//error
							test_signal <= 5'd6;
						end
					endcase
				end
				else begin
					test_signal <= 5'd26;
				end
			end
			else if(display_vsync_pose && !cmr_vref_pose) begin
				case(buf_valid_flag)
					3'b100: begin
						case(read_buffer_offset)
							BUFFER0: begin
								buf_read_flag[0] <= 1'b0;
								buf_read_flag[2] <= 1'b1;
								buf_valid_flag[2] <= 1'b0;
								read_buffer_offset <= BUFFER2;
							end
							BUFFER1: begin
								buf_read_flag[1] <= 1'b0;
								buf_read_flag[2] <= 1'b1;
								buf_valid_flag[2] <= 1'b0;
								read_buffer_offset <= BUFFER2;
							end
							BUFFER2: begin
								//error
								test_signal <= 5'd7;
							end
							default: begin
								//error
								test_signal <= 5'd8;
							end
						endcase
					end
					3'b010 , 3'b110: begin
						case(read_buffer_offset)
							BUFFER0: begin
								buf_read_flag[0] <= 1'b0;
								buf_read_flag[1] <= 1'b1;
								buf_valid_flag[1] <= 1'b0;
								read_buffer_offset <= BUFFER1;
							end
							BUFFER1: begin
								//error
								test_signal <= 5'd9;
							end
							BUFFER2: begin
								buf_read_flag[2] <= 1'b0;
								buf_read_flag[1] <= 1'b1;
								buf_valid_flag[1] <= 1'b0;
								read_buffer_offset <= BUFFER1;
							end
							default: begin
								//error
								test_signal <= 5'd10;
							end
						endcase
					end
					3'b001, 3'b011 , 3'b101, 3'b111: begin
						case(read_buffer_offset)
							BUFFER0: begin 
								//error
								test_signal <= 5'd11;
							end
							BUFFER1: begin
								buf_read_flag[1] <= 1'b0;
								buf_read_flag[0] <= 1'b1;
								buf_valid_flag[0] <= 1'b0;
								read_buffer_offset <= BUFFER0;
							end
							BUFFER2: begin
								buf_read_flag[2] <= 1'b0;
								buf_read_flag[0] <= 1'b1;
								buf_valid_flag[0] <= 1'b0;
								read_buffer_offset <= BUFFER0;
							end
							default: begin
								//error
								test_signal <= 5'd12;
							end
						endcase
					end
					
					default: begin
						test_signal <= 5'd13;
						//no valid data
					end
				endcase
			end
			else if(cmr_vref_pose && display_vsync_pose) begin
				case(buf_valid_flag)
					3'b100: begin
						case(read_buffer_offset)
							BUFFER0: begin
								read_buffer_offset <= BUFFER2;
								write_buffer_offset <= BUFFER0;
								buf_read_flag <= 3'b100;
								buf_write_flag <= 3'b001;
								buf_valid_flag[2] <= 1'b0;
							end
							BUFFER1: begin
								read_buffer_offset <= BUFFER2;
								write_buffer_offset <= BUFFER0;
								buf_read_flag <= 3'b100;
								buf_write_flag <= 3'b001;
								buf_valid_flag[2] <= 1'b0;
							end
							BUFFER2: begin
								//error
								test_signal <= 5'd14;
							end
							default: begin
								//error
								test_signal <= 5'd15;
							end
						endcase
					end
					3'b010 , 3'b110: begin
						case(read_buffer_offset)
							BUFFER0: begin
								read_buffer_offset <= BUFFER1;
								write_buffer_offset <= BUFFER2;
								buf_read_flag <= 3'b10;
								buf_write_flag <= 3'b001;
								buf_valid_flag[1] <= 1'b0;
							end
							BUFFER1: begin
								//error
								test_signal <= 5'd16;
							end
							BUFFER2: begin
								read_buffer_offset <= BUFFER1;
								write_buffer_offset <= BUFFER2;
								buf_read_flag <= 3'b010;
								buf_write_flag <= 3'b001;
								buf_valid_flag[1] <= 1'b0;
							end
							default: begin
								//error
								test_signal <= 5'd17;
							end
						endcase
					end
					3'b001, 3'b011 , 3'b101, 3'b111: begin
						case(read_buffer_offset)
							BUFFER0: begin 
								//error
								test_signal <= 5'd18;
							end
							BUFFER1: begin
								read_buffer_offset <= BUFFER0;
								write_buffer_offset <= BUFFER1;
								buf_read_flag <= 3'b001;
								buf_write_flag <= 3'b010;
								buf_valid_flag[0] <= 1'b0;
							end
							BUFFER2: begin
								read_buffer_offset <= BUFFER1;
								write_buffer_offset <= BUFFER2;
								buf_read_flag <= 3'b010;
								buf_write_flag <= 3'b001;
								buf_valid_flag[1] <= 1'b0;
							end
							default: begin
								//error
								test_signal <= 5'd19;
							end
						endcase
					end
					
					default: begin
					// no valid data
						read_buffer_offset <= read_buffer_offset;
						write_buffer_offset <= write_buffer_offset;
						buf_read_flag <= buf_read_flag;
						buf_write_flag <= buf_write_flag;
						buf_valid_flag <= buf_valid_flag;
					end
				endcase
			end
			else begin
				//keep
				test_signal <= 5'd24;
				read_buffer_offset <= read_buffer_offset;
				write_buffer_offset <= write_buffer_offset;
				buf_read_flag <= buf_read_flag;
				buf_write_flag <= buf_write_flag;
				buf_valid_flag <= buf_valid_flag;
			end
        end
		else begin
			//reset
			test_signal <= 5'd25;
			write_buffer_offset <= BUFFER0;
			read_buffer_offset  <= BUFFER2;
			buf_valid_flag <= 3'b000;
			buf_read_flag <= 3'b100;
			buf_write_flag <= 3'b001;
		end
    end

endmodule 