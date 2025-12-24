module formater(
    input           clk_i,
    input           rstn_i,
    input [2:0]     pkglen_sel_i,
    input [1:0]     a2f_id_i,
    input           a2f_val_i,
    input [31:0]    a2f_data_i,
    input           fmt_grant_i,
    
    output [31:0]   fmt_data_o,
    output          fmt_ack_o,
    output          fmt_chid_o,
    output          fmt_req_o,
    output          fmt_start_o,
    output          fmt_end_o,
    output          fmt_length_o,
    output          fmt_id_req_o
);

reg [5:0] length_r;
reg [5:0] cnt_rec_r;
reg [5:0] cnt_send_r;
reg       buffer0_val_r;
reg       buffer1_val_r;
reg       buffer2_val_r;
reg       fmt_ack_r;
reg [31:0] fmt_fifo [0:31];
reg       slv0_buffer_r;
reg       slv1_buffer_r;
reg       slv2_buffer_r;
reg [31:0] fmt_data_r;
reg [2:0] c_state;
reg [2:0] n_state;
reg       fmt_start_r;
reg       fmt_end_r;
reg       fmt_ack_r;
reg       fmt_send_r;
reg       fmt_id_req_r;
reg       fmt_req_r;



//包长度解码逻辑：根据pkglen_sel_i选择包长度，复位时默认32
always @(*) begin
    if(!rstn_i)
        length_r = 6'd32;
    else begin
        case(pkglen_sel_i)
          3'd0: length_r = 6'd4;
          3'd1: length_r = 6'd8;
          3'd2: length_r = 6'd16;
          3'd3: length_r = 6'd32;
          default: length_r = 6'd32;
        endcase
    end
end

//接收计数器（FIFO写指针） 逻辑：记录已接收数据个数，请求新ID时清零，接收有效数据时递增
always @(posedge clk_i or negedge rstn_i) begin
    if(!rstn_i) cnt_rec_r <= 6'b0;
    else if(fmt_id_req_r) cnt_rec_r <= 6'b0;
    else case(a2f_id_i)
        2'd00 : if((a2f_val_i | buffer0_val_r) && (fmt_ack_r)) cnt_rec_r <= cnt_rec_r + 1'b1;
        2'd01 : if((a2f_val_i | buffer1_val_r) && (fmt_ack_r)) cnt_rec_r <= cnt_rec_r + 1'b1;
        2'd10 : if((a2f_val_i | buffer2_val_r) && (fmt_ack_r)) cnt_rec_r <= cnt_rec_r + 1'b1;
        default : cnt_rec_r <= cnt_rec_r;
    endcase
end

//FIFO写入
always @(posedge clk_i or negedge rstn_i)
    if(!rstn_i) begin
        fmt_fifo[cnt_rec_r] <= 32'hffff_ffff;
        slv0_buffer_r <= 32'hffff_ffff;
        slv1_buffer_r <= 32'hffff_ffff;
        slv2_buffer_r <= 32'hffff_ffff;
        buffer0_val_r <= 1'b0;
        buffer1_val_r <= 1'b0;
        buffer2_val_r <= 1'b0;
    end
    else if(fmt_ack_r) begin
        case(a2f_id_i)
            2'd00: begin
                if(buffer0_val_r) fmt_fifo[cnt_rec_r] <= slv0_buffer_r; buffer0_val_r <= 1'b0;
                else if(a2f_val_i) fmt_fifo[cnt_rec_r] <= a2f_data_i;
            end
            2'd01: begin
                if(buffer1_val_r) fmt_fifo[cnt_rec_r] <= slv1_buffer_r; buffer1_val_r <= 1'b0;
                else if(a2f_val_i) fmt_fifo[cnt_rec_r] <= a2f_data_i;
            end
            2'd10: begin
                if(buffer2_val_r) fmt_fifo[cnt_rec_r] <= slv2_buffer_r; buffer2_val_r <= 1'b0;
                else if(a2f_val_i) fmt_fifo[cnt_rec_r] <= a2f_data_i;
            end
        endcase
    end 
    else begin //此部分代码应该不会执行，当fmt_ack_r = 1'b0 时 fifo不会发送数据
        case(a2f_id_i)
            2'd00: begin
               if(a2f_val_i) slv0_buffer_r <= a2f_data_i; buffer0_val_r <= 1'b1;
            end
            2'd01: begin
               if(a2f_val_i) slv1_buffer_r <= a2f_data_i; buffer1_val_r <= 1'b1;
            end
            2'd10: begin
               if(a2f_val_i) slv2_buffer_r <= a2f_data_i; buffer2_val_r <= 1'b1;
            end
    end
    
//发送计数器（FIFO读指针）逻辑：记录已发送数据个数
always @(posedge clk_i or negedge rstn_i)
    if(!rstn_i)
        cnt_send_r <= 6'd0;
    else if(fmt_id_req_r) cnt_send_r <= 6'd0;
    else if(fmt_send_r) cnt_send_r <= cnt_send_r + 1'b1;
      
//fifo读取逻辑：从fifo中读取数据到输出寄存器，供外部接口读取
always @(posedge clk_i or negedge rstn_i) begin
    if(!rst_n)
        fmt_data_r <= 32'hffff_ffff;
    else if(fmt_send_r) fmt_data_r <= fmt_fifo[cnt_send_r];
    else fmt_data_r <= 32'hffff_ffff;
end

//状态机
parameter FMT_REQ = 3'b000;
parameter FMT_WAIT_GRANT = 3'b001;
parameter FMT_START = 3'b011;
parameter FMT_SEND = 3'b010;
parameter FMT_END = 3'b110;
parameter FMT_IDLE = 3'b111;

//状态机现态更新，时钟沿触发，次态更新为现态
always @(posedge clk_i or negedge rst_n)
    if(!rst_n)
        c_state <= FMT_IDLE;
    else
        c_state <= n_state;

//状态跳转
always @(*)
    if(!rst_n)
        n_state = FMT_IDLE;
    else case(c_state)
        //当包满时，进入请求发送
        FMT_IDLE : n_state = (cnt_rec_r == length_r - 2'd1) ? FMT_REQ : FMT_IDLE;
        FMT_REQ : n_state = FMT_WAIT_GRANT;
        FMT_WAIT_GRANT : n_state = (fmt_grant_i) ? FMT_START : FMT_WAIT_GRANT;
        FMT_START : n_state = FMT_SEND;
        FMT_SEND : n_state = (cnt_send_r == length_r - 2'd2) ? FMT_END: : FMT_SEND;
        FMT_END : n_state = FMT_IDLE;
        default : n_state = FMT_IDLE;
    endcase
    
//状态机输出控制
always @(*)
    if(!rst_n)
            fmt_end_r = 1'b0;
            fmt_start_r = 1'b0;
            fmt_ack_r = 1'b0;
            fmt_req_r = 1'b0;
            fmt_id_req_r = 1'b1;
            fmt_send_r = 1'b0;
    else case(c_state)
        FMT_IDLE : begin
            fmt_end_r = 1'b0;
            fmt_start_r = 1'b0;
            fmt_ack_r = (a2f_id_i != 1'b11) ? 1'b1 : 1'b0;
            fmt_req_r = 1'b0;
            fmt_id_req_r =(a2f_id_i == 1'b11) ? 1'b1 : 1'b0;
            fmt_send_r = 1'b0;            
        end
        FMT_REQ : begin
            fmt_end_r = 1'b0;
            fmt_start_r = 1'b0;
            fmt_ack_r = 1'b0;
            fmt_req_r = 1'b1;
            fmt_id_req_r =1'b0;
            fmt_send_r = 1'b0;          
        end
        FMT_WAIT_GRANT : begin
            fmt_end_r = 1'b0;
            fmt_start_r = 1'b0;
            fmt_ack_r = 1'b0;
            fmt_req_r = 1'b1;
            fmt_id_req_r =1'b0;
            fmt_send_r = 1'b0;              
        end
        FMT_START : begin
            fmt_end_r = 1'b0;
            fmt_start_r = 1'b1;
            fmt_ack_r = 1'b0;
            fmt_req_r = 1'b0;
            fmt_id_req_r =1'b0;
            fmt_send_r = 1'b1;         
        end
        FMT_SEND : begin
            fmt_end_r = 1'b0;
            fmt_start_r = 1'b0;
            fmt_ack_r = 1'b0;
            fmt_req_r = 1'b0;
            fmt_id_req_r =1'b0;
            fmt_send_r = 1'b1; 
        end
        FMT_END : begin
            fmt_end_r = 1'b1;
            fmt_start_r = 1'b0;
            fmt_ack_r = 1'b0;
            fmt_req_r = 1'b0;
            fmt_id_req_r =1'b1;
            fmt_send_r = 1'b1;         
        end
    endcase
    
assign fmt_id_req_o = fmt_id_req_r;
assign fmt_ack_o = fmt_ack_r;
assign fmt_data_o = fmt_data_r;
assign fmt_start_o = fmt_start_r;
assign fmt_end_o = fmt_end_r;
assign fmt_req_o = fmt_req_r;
assign fmt_length_o = length_r;
assign fmt_chid_o = a2f_id_i;


endmodule