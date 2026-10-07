module frame_switch_v_2_0#(
    parameter   AXI_ADDR_WIDTH  =   28      ,
                AXI_ID_WIDTH    =   4       ,
                AXI_LEN_WIDTH   =   4       ,      
                DDR_DQ_WIDTH    =   32      ,
                PIX_DATA_WIDTH  =   16      ,
                FRAME_WIDTH     =   640     ,
                FRAME_HEIGHT    =   480     ,                       
                BUFFER_OFFSET   =   28'd0   ,
                BUFFER_INTERVAL =   10      ,
                RD_USER_VAL     =   2           
)(
    input   wire                                        clk                 ,
    input   wire                                        rst_n               ,
    input   wire    [AXI_ID_WIDTH-1:0]                  wr_user_id          ,
    input   wire    [RD_USER_VAL*AXI_ID_WIDTH-1:0]      rd_user_id          ,
    // ---- AXI AW ports for write users ----
    input   wire    [AXI_ADDR_WIDTH-1:0]                wr_user_awaddr/*synthesis PAP_MARK_DEBUG="true"*/   ,   
    input   wire                                        wr_user_awvalid/*synthesis PAP_MARK_DEBUG="true"*/  ,
    input   wire                                        wr_user_awready/*synthesis PAP_MARK_DEBUG="true"*/  ,
    input   wire    [AXI_ID_WIDTH-1:0]                  wr_user_awid/*synthesis PAP_MARK_DEBUG="true"*/     ,
    input   wire    [AXI_LEN_WIDTH-1:0]                 wr_user_awlen/*synthesis PAP_MARK_DEBUG="true"*/    ,

    // ---- AXI AW ports for read users ----
    input   wire    [RD_USER_VAL*AXI_ADDR_WIDTH-1:0]    rd_user_araddr/*synthesis PAP_MARK_DEBUG="true"*/   ,    
    input   wire    [RD_USER_VAL-1:0]                   rd_user_arvalid/*synthesis PAP_MARK_DEBUG="true"*/  ,
    input   wire    [RD_USER_VAL-1:0]                   rd_user_arready/*synthesis PAP_MARK_DEBUG="true"*/  ,
    input   wire    [RD_USER_VAL*AXI_ID_WIDTH-1:0]      rd_user_arid/*synthesis PAP_MARK_DEBUG="true"*/     ,
    input   wire    [RD_USER_VAL*AXI_LEN_WIDTH-1:0]     rd_user_arlen/*synthesis PAP_MARK_DEBUG="true"*/    ,

    output  reg     [AXI_ADDR_WIDTH-1:0]                write_buffer_offset/*synthesis PAP_MARK_DEBUG="true"*/ ,
    output  reg     [RD_USER_VAL*AXI_ADDR_WIDTH-1:0]    read_buffer_offset/*synthesis PAP_MARK_DEBUG="true"*/      
);

    //=============================================================================
    // Local Parameters
    //=============================================================================
    localparam  TOTAL_BUFS      = RD_USER_VAL + 2;
    localparam  AXI_DATA_WIDTH  = DDR_DQ_WIDTH * 8;        // 256 bits
    localparam  BUFFER_SIZE     = FRAME_WIDTH * FRAME_HEIGHT * PIX_DATA_WIDTH / DDR_DQ_WIDTH;

    //=============================================================================
    // Buffer Address Calculation (已有逻辑 + generate)
    //=============================================================================
    wire [AXI_ADDR_WIDTH-1:0] buffer[TOTAL_BUFS-1:0];
    assign buffer[0] = BUFFER_OFFSET;
    genvar buf_i;
    generate
        for(buf_i = 1; buf_i < TOTAL_BUFS; buf_i = buf_i + 1) begin : gen_buffer_addr
            assign buffer[buf_i] = buffer[buf_i-1] + BUFFER_SIZE + (1 << BUFFER_INTERVAL);
        end
    endgenerate

    wire    [AXI_ADDR_WIDTH-1:0]    wr_user_awaddr_real      ;   
   
    assign wr_user_awaddr_real = wr_user_awaddr - write_buffer_offset;
                
    wire    [RD_USER_VAL*AXI_ADDR_WIDTH-1:0]    rd_user_araddr_real      ; 
    genvar real_rd_i;
    generate
        for(real_rd_i = 0; real_rd_i < RD_USER_VAL; real_rd_i = real_rd_i + 1) begin : rd_user_awaddr_real_gen
            assign rd_user_araddr_real[real_rd_i*AXI_ADDR_WIDTH+:AXI_ADDR_WIDTH] = 
                rd_user_araddr[real_rd_i*AXI_ADDR_WIDTH+:AXI_ADDR_WIDTH] - read_buffer_offset[real_rd_i*AXI_ADDR_WIDTH+:AXI_ADDR_WIDTH];
        end
    endgenerate 

    integer i,j;
    reg    [AXI_ADDR_WIDTH-1:0]    wr_user_awaddr_real_reg      ;   
    reg    [AXI_LEN_WIDTH-1:0]    wr_user_awlen_reg            ;   
    always @(posedge clk) begin
        if(!rst_n) begin
                wr_user_awaddr_real_reg <= {AXI_ADDR_WIDTH{1'b0}};
                wr_user_awlen_reg <= {AXI_LEN_WIDTH{1'b0}};
        end
        else begin
            if(wr_user_awvalid && wr_user_awready && wr_user_awid == wr_user_id) begin
                wr_user_awaddr_real_reg <= wr_user_awaddr_real;
                wr_user_awlen_reg <= wr_user_awlen;
            end
            else begin
                wr_user_awaddr_real_reg <= {AXI_ADDR_WIDTH{1'b0}};
                wr_user_awlen_reg <= {AXI_LEN_WIDTH{1'b0}};
            end
        end
    end

    reg    [RD_USER_VAL*AXI_ADDR_WIDTH-1:0]    rd_user_araddr_real_reg      ;   
    reg    [RD_USER_VAL*AXI_LEN_WIDTH-1:0]    rd_user_arlen_reg            ;   
    always @(posedge clk) begin
        if(!rst_n) begin
            for (i = 0; i < RD_USER_VAL ; i = i + 1) begin
                rd_user_araddr_real_reg[i*AXI_ADDR_WIDTH+:AXI_ADDR_WIDTH] <= {AXI_ADDR_WIDTH{1'b0}};
                rd_user_arlen_reg[i*AXI_LEN_WIDTH+:AXI_LEN_WIDTH] <= {AXI_LEN_WIDTH{1'b0}};
            end
        end
        else begin
            for (i = 0; i < RD_USER_VAL ; i = i + 1) begin
                if(rd_user_arvalid[i] && rd_user_arready[i] && rd_user_arid[i*AXI_ID_WIDTH+:AXI_ID_WIDTH] == rd_user_id[i*AXI_ID_WIDTH+:AXI_ID_WIDTH]) begin
                    rd_user_araddr_real_reg[i*AXI_ADDR_WIDTH+:AXI_ADDR_WIDTH] <= rd_user_araddr_real[i*AXI_ADDR_WIDTH+:AXI_ADDR_WIDTH];
                    rd_user_arlen_reg[i*AXI_LEN_WIDTH+:AXI_LEN_WIDTH] <= rd_user_arlen[i*AXI_LEN_WIDTH+:AXI_LEN_WIDTH];
                end
                else begin
                    rd_user_araddr_real_reg[i*AXI_ADDR_WIDTH+:AXI_ADDR_WIDTH] <= {AXI_ADDR_WIDTH{1'b0}};
                    rd_user_arlen_reg[i*AXI_LEN_WIDTH+:AXI_LEN_WIDTH] <= {AXI_LEN_WIDTH{1'b0}};
                end
            end
        end
    end
    wire [AXI_LEN_WIDTH:0] wr_user_finish_ar_len;
    wire [AXI_LEN_WIDTH:0] rd_user_finish_ar_len[RD_USER_VAL-1:0];
    wire                   wr_user_finish_flag;
    wire [RD_USER_VAL-1:0] rd_user_finish_flag;

    assign wr_user_finish_flag = wr_user_awaddr_real_reg + wr_user_finish_ar_len*(AXI_DATA_WIDTH/DDR_DQ_WIDTH) >= BUFFER_SIZE;
    assign wr_user_finish_ar_len = {1'b0,wr_user_awlen_reg} + 1'b1;
    genvar rd_user_i;
    generate
        for ( rd_user_i = 0; rd_user_i < RD_USER_VAL ; rd_user_i = rd_user_i + 1) begin
            assign rd_user_finish_ar_len[rd_user_i] = {1'b0,rd_user_arlen_reg[rd_user_i*AXI_LEN_WIDTH+:AXI_LEN_WIDTH]} + 1'b1;
            assign rd_user_finish_flag[rd_user_i] = rd_user_araddr_real_reg[rd_user_i*AXI_ADDR_WIDTH+:AXI_ADDR_WIDTH] + rd_user_finish_ar_len[rd_user_i]*(AXI_DATA_WIDTH/DDR_DQ_WIDTH) >= BUFFER_SIZE;
        end
    endgenerate

    reg                   wr_user_finish_flag_dly;
    reg [RD_USER_VAL-1:0] rd_user_finish_flag_dly;
    always @(posedge clk) begin
        if(!rst_n) begin
            wr_user_finish_flag_dly <= 1'b0;
            for (i = 0; i < RD_USER_VAL; i = i + 1) begin
                rd_user_finish_flag_dly[i] <= 1'b0;
            end
        end
        else begin
            wr_user_finish_flag_dly <= wr_user_finish_flag;
            for (i = 0; i < RD_USER_VAL; i = i + 1) begin
                rd_user_finish_flag_dly[i] <= rd_user_finish_flag[i];
            end
        end
    end

    wire                   wr_user_finish_flag_pose;
    wire [RD_USER_VAL-1:0] rd_user_finish_flag_pose;

    assign wr_user_finish_flag_pose = wr_user_finish_flag && !wr_user_finish_flag_dly;
    generate
        for ( rd_user_i = 0; rd_user_i < RD_USER_VAL ; rd_user_i = rd_user_i + 1) begin
            assign  rd_user_finish_flag_pose[rd_user_i] = rd_user_finish_flag[rd_user_i] && !rd_user_finish_flag_dly[rd_user_i];
        end
    endgenerate

    localparam PTR_WIDTH = $clog2(TOTAL_BUFS);

    reg [PTR_WIDTH-1:0] wr_ptr/*synthesis PAP_MARK_DEBUG="true"*/;
    reg [PTR_WIDTH-1:0] rd_ptr[RD_USER_VAL-1:0]/*synthesis PAP_MARK_DEBUG="true"*/;
    reg [PTR_WIDTH-1:0] data_ptr[RD_USER_VAL-1:0]/*synthesis PAP_MARK_DEBUG="true"*/;

    wire [RD_USER_VAL-1:0]rd_data_empty;
    wire [RD_USER_VAL-1:0]rd_data_full;

    reg  wr_full;
    always @(*) begin
        wr_full = 1'b1;
        for (i = 0; i < RD_USER_VAL;i=i+1 ) begin
            if(!rd_data_full[i]) begin
                wr_full = 0;
            end
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            wr_ptr <= {PTR_WIDTH{1'b0}};
        end
        else begin
            if(wr_user_finish_flag_pose && !wr_full) begin
                wr_ptr <= wr_ptr == TOTAL_BUFS - 1 ? {PTR_WIDTH{1'b0}} : wr_ptr + 1'b1;
            end
        end
    end

    generate
        for ( rd_user_i = 0; rd_user_i < RD_USER_VAL ; rd_user_i = rd_user_i + 1) begin
            assign rd_data_full[rd_user_i] = data_ptr[rd_user_i] == TOTAL_BUFS - 1;
            assign rd_data_empty[rd_user_i] = data_ptr[rd_user_i] <= 1;
            always @(posedge clk) begin
                if(!rst_n) begin
                    rd_ptr[rd_user_i] <= {PTR_WIDTH{1'b0}};
                end
                else begin
                    if(rd_user_finish_flag_pose[rd_user_i] && !rd_data_empty[rd_user_i]) begin
                        rd_ptr[rd_user_i] <= rd_ptr[rd_user_i] == TOTAL_BUFS - 1 ? {PTR_WIDTH{1'b0}} : rd_ptr[rd_user_i] + 1'b1;
                    end
                end
            end

            always @(posedge clk) begin
                if(!rst_n) begin
                    data_ptr[rd_user_i] <= {PTR_WIDTH{1'b0}};
                end
                else begin
                    if(wr_user_finish_flag_pose && !rd_user_finish_flag_pose[rd_user_i]) begin
                        data_ptr[rd_user_i] <= data_ptr[rd_user_i] == TOTAL_BUFS - 1 ? TOTAL_BUFS - 1 : data_ptr[rd_user_i] + 1'b1;
                    end
                    else if(rd_user_finish_flag_pose[rd_user_i] && !wr_user_finish_flag_pose && !rd_data_empty[rd_user_i]) begin
                        data_ptr[rd_user_i] <= data_ptr[rd_user_i] == {PTR_WIDTH{1'b0}} ? {PTR_WIDTH{1'b0}} : data_ptr[rd_user_i] - 1'b1;
                    end
                end
            end
        end
    endgenerate

    always @(*) begin
        write_buffer_offset = buffer[wr_ptr];
        for (i = 0; i < RD_USER_VAL ; i = i + 1) begin
            read_buffer_offset[i*AXI_ADDR_WIDTH+:AXI_ADDR_WIDTH] = buffer[rd_ptr[i]];
        end
    end
endmodule
