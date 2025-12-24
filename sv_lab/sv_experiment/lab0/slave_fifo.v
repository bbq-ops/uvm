 module slave_fifo(
    input               clk_i           ,
    input               rstn_i          ,
    input       [31:0]  chx_data_i      ,
    input               a2sx_ack_i      ,
    input               chx_valid_i     ,
    output reg  [31:0]  slvx_data_o     ,
    output      [5:0]   slvx_margin_o   ,
    output reg          chx_ready_o     ,
    output reg          slvx_val_o      ,
    output reg          slvx_req_o            //请求发送数据
);

reg [5:0] wr_pointer_r;  //写指针，最高位来判断是否写满
reg [5:0] rd_pointer_r;  //读指针

wire rd_en_s;
wire empty_s;
wire full_s;
wire [5:0] data_cnt_s;

reg [31:0] mem [31:0];   //FIFO的位宽为32，深度也为32

//读使能信号
assign rd_en_s = a2sx_ack_i;

//判断FIFO是否写满，写满必须wr_pointer_s比rd_pointer_s多32位（可以用最高位来判断）
assign full_s = ({!wr_pointer_r[5],wr_pointer_r[4:0]} == rd_pointer_r);

//判断FIFO是否为空，只需wr_pointer_s和rd_pointer_s相等
assign empty_s = (wr_pointer_r == rd_pointer_r);

//计算当前FIFO剩余空间
assign data_cnt_s = (6'd32 - (wr_pointer_r - rd_pointer_r));
assign slvx_margin_o = data_cnt_s;

//表明可以向FIFO中传输数据
always @(*)
begin
    if(!full_s)
        chx_ready_o = 1'b1;
    else
        chx_ready_o = 1'b0;
end

//FIFO输出数据请求信号
always @(*)
begin
    if(!rstn_i)
        slvx_req_o = 1'b0;
    else if(!empty_s)
        slvx_req_o = 1'b1;
    else
        slvx_req_o = 1'b0;
end


//写指针计数
always @(posedge clk_i or negedge rstn_i)
    if(!rstn_i) begin
       wr_pointer_r <= 6'b0;
    end
    else if(chx_valid_i && chx_ready_o) begin
       wr_pointer_r <= wr_pointer_r + 1'b1;
    end
    
//读指针计数
always @(posedge clk_i or negedge rstn_i)
    if(!rstn_i) begin
        rd_pointer_r <= 6'b0;
    end
    else if(rd_en_s && (!empty_s)) begin
        rd_pointer_r <= rd_pointer_r + 1'b1;
    end
    
//输出数据有效信号
always @(posedge clk_i or negedge rstn_i)
    if(!rstn_i)
        slvx_val_o <= 1'b0;
    else if(rd_en_s && (!empty_s))
        slvx_val_o <= 1'b1;
    else
        slvx_val_o <= 1'b0;

//读模块
always @(posedge clk_i)
begin : READ_DATA
    if(rd_en_s && (!empty_s) && rstn_i)
        slvx_data_o <= mem[rd_pointer_r[4:0]];
end     

//写模块
always @(posedge clk_i)
begin : MEM_WRITE
    if(rstn_i && chx_valid_i && chx_ready_o)
        mem[wr_pointer_r[4:0]] <= chx_data_i;
end