`timescale  1ps/1ps
module axi_mem_test_module#(
    parameter		AXI_ADDR_WIDTH			=	28					,
	parameter 		AXI_DATA_WIDTH			=	256					,
	parameter 		AXI_ID_WIDTH			=	4					,
	parameter		AXI_LEN_WIDTH			=	4					,
    parameter       AXI_TRADE_BUFFER_DEPTH  =   8                   ,
	parameter 		DDR_DATA_MASK_WIDTH		=	32					,
	parameter 		DATA_BACKPRESSURE_EN	=	1'b0				,
    parameter       MEM_READY_DLY_CYCLES    =   100                 ,
    parameter       MEM_ADDRESS_WIDTH       =   16                  ,
    parameter       MEM_UNIT_WIDTH          =   32                  ,
    parameter       MEM_MIN_DATA_DELAY      =   3                   ,
    parameter       MEM_MAX_DATA_DELAY      =   10                  ,
    parameter       MEM_DATA_FILE_PATH      =   "../Matlab/test img/resize/venus/test_img.dat"
)(
    input   wire                            axi_clk                 ,
    input   wire                            rst_n                   ,

    output  reg                             mem_ready               ,

    input 	wire 	[AXI_ADDR_WIDTH-1:0]	araddr			        ,
	input 	wire 	[AXI_ID_WIDTH-1:0]		ar_id			        ,
	input 	wire 	[AXI_LEN_WIDTH-1:0]		ar_len			        ,
	input 	wire 							araddr_valid		    ,
	output 	reg 							araddr_ready		    ,
	
	input 	wire 	[AXI_ADDR_WIDTH-1:0]	awaddr			        ,
	input 	wire 	[AXI_ID_WIDTH-1:0]		aw_id			        ,
	input 	wire 	[AXI_LEN_WIDTH-1:0]		aw_len			        ,
	input 	wire 							awaddr_valid		    ,
	output 	reg 							awaddr_ready		    , 
    
    input 	wire 	[AXI_DATA_WIDTH-1:0]	wr_data			        ,
	input 	wire [DDR_DATA_MASK_WIDTH-1:0]	wstrb			        ,
	output 	wire 							wr_data_ready	        ,
	inout 	wire 	[AXI_ID_WIDTH-1:0]		wr_id			        ,	//不支持数据反压时id信号由mux给出
	inout 	wire 							wr_data_last		    , 	//不支持数据反压时last信号由mux给出
	
	output 	wire 	[AXI_DATA_WIDTH-1:0]	rd_data			        ,
	output 	wire							rd_data_valid	        ,
	output 	wire 	[AXI_ID_WIDTH-1:0]		rd_id			        ,	//不支持数据反压时id信号由mux给出
	output 	wire 							rd_data_last		    	//不支持数据反压时last信号由mux给出
); 
    // mem_core reset and illegal data check
    reg     [MEM_UNIT_WIDTH-1:0] mem_core[0:(1<<MEM_ADDRESS_WIDTH)-1];
    reg     mem_reset_flag;
    integer i;
    always@(posedge axi_clk) begin
        if(!rst_n) begin
            mem_reset_flag <= 1'b1;
            $display("@ %0t , [MEM MODULE] Reset request accepted",$time); 
            $display("@ %0t , [MEM MODULE] Reset in progress: loading the primitive data into mem_core",$time);
            $readmemh(MEM_DATA_FILE_PATH,mem_core);
            $display("@ %0t , [MEM MODULE] Loaded data from %s into mem_core.",$time,MEM_DATA_FILE_PATH);
            for(i=0;i < 1<<MEM_ADDRESS_WIDTH ; i=i+1) begin
                if (mem_core[i][0] !== 1'b1 && mem_core[i][0] !==1'b0) begin
                    $display("[MEM MODULE] Error, there is no enough data, current count of data is %d",i);
                    $stop;
                end
		    end
		    $display("@ %0t , [MEM MODULE] Data count matches memory capacity",$time);
            $display("@ %0t , [MEM MODULE] Reset completetd successfully ",$time);
        end
        else begin
            if(mem_ready) begin
                mem_reset_flag <= 1'b0;
            end
        end
    end
    
    // reset delay behavior 
    localparam MEM_RST_DLY_CNT_WIDTH = $clog2(MEM_READY_DLY_CYCLES+1);
    reg [MEM_RST_DLY_CNT_WIDTH-1:0] mem_rst_dly_cnt;
    reg                             mem_ready_dly;
    always@(posedge axi_clk) begin
        mem_ready_dly <= mem_ready;
        if(!rst_n) begin
            mem_rst_dly_cnt <= {MEM_RST_DLY_CNT_WIDTH{1'b0}};
            mem_ready <= 1'b0;
            mem_ready_dly <= 1'b0;
        end
        else if(mem_reset_flag) begin
            mem_rst_dly_cnt <= mem_rst_dly_cnt == MEM_READY_DLY_CYCLES - 1'b1 ? MEM_READY_DLY_CYCLES -1'b1 : mem_rst_dly_cnt + 1'b1;
            mem_ready <= mem_rst_dly_cnt == MEM_READY_DLY_CYCLES - 1'b1 ? 1'b1 : 1'b0;
            mem_ready_dly <= mem_ready;
        end
        if(mem_ready && !mem_ready_dly) $display("@ %0t ,[MEM MODULE] The mem_Core ready to work",$time);
    end

    // axi read address channel behavior
    // trade management
    localparam TRADE_PTR_WIDTH = $clog2(AXI_TRADE_BUFFER_DEPTH);
    reg [AXI_ADDR_WIDTH-1:0]    rd_address_buffer[AXI_TRADE_BUFFER_DEPTH-1:0];
    reg [AXI_ID_WIDTH-1:0]      rd_id_buffer[AXI_TRADE_BUFFER_DEPTH-1:0];
    reg [AXI_LEN_WIDTH-1:0]     rd_len_buffer[AXI_TRADE_BUFFER_DEPTH-1:0];
    reg [TRADE_PTR_WIDTH:0]     rd_buffer_counter;
    reg [TRADE_PTR_WIDTH:0]     rd_buffer_wr_ptr;
    reg [TRADE_PTR_WIDTH-1:0]   rd_buffer_rd_ptr;
    wire                        rd_trade_empty;
    wire                        rd_trade_full;
    wire                        rd_handshake_en;

    assign rd_handshake_en = araddr_valid && araddr_ready;
    always@(*) begin
        araddr_ready = 1'b0;
        if(araddr_valid && !rd_trade_full) begin
            araddr_ready = 1'b1;
        end
    end

    assign rd_trade_empty = rd_buffer_counter == 0;
    assign rd_trade_full = rd_buffer_counter == AXI_TRADE_BUFFER_DEPTH;

    always @(posedge axi_clk) begin
        if(!rst_n) begin
            rd_buffer_counter <= 0;
        end
        else begin
            if(rd_handshake_en && !rd_trade_full) begin
                rd_buffer_counter <=  rd_buffer_counter + 1'b1;
            end
            else if(rd_data_last && !rd_trade_empty) begin
                rd_buffer_counter <=  rd_buffer_counter - 1'b1;
            end
        end
    end

    always @(posedge axi_clk) begin
        if(!rst_n) begin
            rd_buffer_wr_ptr <= 0;
            rd_buffer_rd_ptr <= 0;
        end
        else begin
            if(rd_handshake_en && !rd_trade_full) begin
                rd_buffer_wr_ptr <=  rd_buffer_wr_ptr + 1'b1;
            end
            else if(rd_data_last && !rd_trade_empty) begin
                rd_buffer_rd_ptr <=  rd_buffer_rd_ptr + 1'b1;
            end
        end
    end

    always @(posedge axi_clk) begin
        if(!rst_n) begin
            for(i=0 ; i < AXI_TRADE_BUFFER_DEPTH ; i = i + 1) begin
                rd_address_buffer[i] <= 0;
                rd_id_buffer[i] <= 0;
                rd_len_buffer[i] <= 0;
             end       
        end
        else begin
            if(rd_handshake_en && !rd_trade_full) begin
                $display("@ %0t ,[MEM MODULE] AXI read address channel got a new handshake with %0h @ %0h for %0d burst length",$time,ar_id,araddr,ar_len+1);
                rd_address_buffer[rd_buffer_wr_ptr[TRADE_PTR_WIDTH-1:0]] <= araddr;
                rd_id_buffer[rd_buffer_wr_ptr[TRADE_PTR_WIDTH-1:0]] <= ar_id;
                rd_len_buffer[rd_buffer_wr_ptr[TRADE_PTR_WIDTH-1:0]] <= ar_len;
            end
        end
    end

    // axi read data channel behavior
    localparam R_SM_NUM = 2;
    localparam R_IDLE = 2'b01;
    localparam R_BUSY = 2'b10;

    reg [R_SM_NUM-1:0] curr_state;
    reg [R_SM_NUM-1:0] next_state;

    always@(*) begin
        next_state = R_IDLE;
        case(curr_state) 
            R_IDLE:begin 
                if(!rd_trade_empty) begin
                    next_state = R_BUSY;
                end
                else begin
                    next_state = R_IDLE;
                end
            end
            R_BUSY:begin
                if(rd_data_last) begin
                    next_state = R_IDLE;
                end
                else begin
                    next_state = R_BUSY;
                end
            end
            default:begin
                next_state = R_IDLE;
            end
        endcase
    end

    always@(posedge axi_clk) begin
        if(!rst_n) begin
            curr_state <= R_IDLE;
        end
        else begin
            curr_state <= next_state;
        end
    end

    reg [AXI_LEN_WIDTH-1:0] rd_d_cnt;
    always@(posedge axi_clk) begin
        if(!rst_n) begin
            rd_d_cnt <= 0;
        end
        else begin
            if(curr_state == R_IDLE) begin
                rd_d_cnt <= 0;
            end
            else if(rd_data_valid && !rd_data_last) begin
                rd_d_cnt <= rd_d_cnt + 1'b1;
            end
        end
    end 

    reg                         data_initial_delay_done;
    assign rd_data_last = curr_state == R_BUSY && rd_data_valid && (rd_d_cnt == rd_len_buffer[rd_buffer_rd_ptr]);

    localparam  DATA_DLY_CNT_WIDTH = $clog2(MEM_MAX_DATA_DELAY+1);
    reg [DATA_DLY_CNT_WIDTH-1:0] data_dly_cnt;
    reg [DATA_DLY_CNT_WIDTH-1:0] data_dly_target;
   

    always @(posedge axi_clk) begin
        if(!rst_n) begin
            data_dly_target <= MEM_MIN_DATA_DELAY;
        end
        else if(curr_state == R_IDLE && next_state == R_BUSY) begin
            data_dly_target <= $random % (MEM_MAX_DATA_DELAY - MEM_MIN_DATA_DELAY + 1) + MEM_MIN_DATA_DELAY;
        end
    end

    always @(posedge axi_clk) begin
        if(!rst_n) begin
            data_dly_cnt <= {DATA_DLY_CNT_WIDTH{1'b0}};
            data_initial_delay_done <= 1'b0;
        end
        else begin
            if(curr_state == R_IDLE) begin
                data_dly_cnt <= {DATA_DLY_CNT_WIDTH{1'b0}};
                data_initial_delay_done <= 1'b0;
            end
            else if(curr_state == R_BUSY && !data_initial_delay_done) begin
                if(data_dly_cnt >= data_dly_target) begin
                    data_initial_delay_done <= 1'b1;
                    data_dly_cnt <= data_dly_cnt;
                end
                else begin
                    data_dly_cnt <= data_dly_cnt + 1'b1;
                end
            end
        end
    end

    localparam MEM_ADDR_LSB = $clog2(AXI_DATA_WIDTH / MEM_UNIT_WIDTH);
    localparam MEM_PER_BEAT = AXI_DATA_WIDTH / MEM_UNIT_WIDTH;
    wire [MEM_ADDRESS_WIDTH-1:0] base_addr;
    wire [MEM_ADDRESS_WIDTH-1:0] burst_addr_offset;
    wire [MEM_ADDRESS_WIDTH-1:0] beat_base_addr;

    assign base_addr = rd_address_buffer[rd_buffer_rd_ptr][MEM_ADDRESS_WIDTH + MEM_ADDR_LSB : MEM_ADDR_LSB];
    assign burst_addr_offset = rd_d_cnt;
    assign beat_base_addr = (base_addr + burst_addr_offset) * MEM_PER_BEAT;

    genvar m;
    generate
        for(m = 0; m < MEM_PER_BEAT; m = m + 1) begin : gen_rd_data_concat
            assign rd_data[(m+1)*MEM_UNIT_WIDTH-1 : m*MEM_UNIT_WIDTH] = mem_core[beat_base_addr + m];
        end
    endgenerate

    assign rd_data_valid = curr_state == R_BUSY && data_initial_delay_done;
    assign rd_id = rd_id_buffer[rd_buffer_rd_ptr];

    // write address channel
    // in progress
    // wirte data channel
    // in progress
endmodule
