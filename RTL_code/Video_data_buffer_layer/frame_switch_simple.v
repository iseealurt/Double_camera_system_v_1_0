module frame_switch#(
	parameter 	AXI_ADDR_WIDTH	=	28		,
				DDR_DQ_WIDTH	=	32		,
				PIX_DATA_WIDTH	=	16		,
				FRAME_WIDTH		=	640		,
				FRAME_HEIGHT	=	480		,						
				BUFFER_OFFSET 	= 	28'd0	,
				BUFFER_INTERVAL	=	10	    ,
                WR_USER_VAL     =   1       ,
                RD_USER_VAL     =   2       
)(
    input   wire               			 	            clk				    ,
    input   wire                			            rst_n		        ,	
    input   wire    [WR_USER_VAL-1:0]                   wr_end				,
    input   wire    [RD_USER_VAL-1:0]                   rd_end				,
    output  reg     [WR_USER_VAL*AXI_ADDR_WIDTH-1:0]    write_buffer_offset	,
    output  reg     [RD_USER_VAL*AXI_ADDR_WIDTH-1:0]	read_buffer_offset     
);

	localparam 	BUFFER_SIZE = FRAME_HEIGHT * FRAME_WIDTH * PIX_DATA_WIDTH / DDR_DQ_WIDTH;
    reg [AXI_ADDR_WIDTH-1:0] buffer[WR_USER_VAL+RD_USER_VAL:0];
    integer i;
    always@(*)begin
        buffer[0] = BUFFER_OFFSET;
        for(i=1;i < WR_USER_VAL+RD_USER_VAL+1 ; i = i+1) begin
            buffer[i] = buffer[i-1] + BUFFER_SIZE + (1<<BUFFER_INTERVAL);
        end
    end
    
    wire [WR_USER_VAL-1:0] wr_end_pose;
    wire [RD_USER_VAL-1:0] rd_end_pose;

    genvar wr_cnt , rd_cnt;
    generate
        begin: posedge_detect
            for(wr_cnt = 0 ; wr_cnt < WR_USER_VAL ; wr_cnt = wr_cnt + 1) begin
                reg wr_end_dly;
                always @(posedge clk) begin
                    if(!rst_n) begin
                        wr_end_dly <= 1'b0;
                    end
                    else begin
                        wr_end_dly <= wr_end[wr_cnt];
                    end
                end
                assign wr_end_pose[wr_cnt] = wr_end[wr_cnt] && !wr_end_dly;
            end

            for(rd_cnt = 0 ; rd_cnt < RD_USER_VAL ; rd_cnt = rd_cnt + 1) begin
                reg rd_end_dly;
                always @(posedge clk) begin
                    if(!rst_n) begin
                        rd_end_dly <= 1'b0;
                    end
                    else begin
                        rd_end_dly <= rd_end[rd_cnt];
                    end
                end
                assign rd_end_pose[rd_cnt] = rd_end[rd_cnt] && !rd_end_dly;
            end
        end
    endgenerate

    
endmodule 