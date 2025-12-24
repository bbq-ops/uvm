//------------------------------------------------------------------------------------------------------------------------//
//change log 2017-08-20 Move package length select to Arbiter 
//------------------------------------------------------------------------------------------------------------------------//
// 模块功能：formater（格式化器）用于从仲裁器（arbiter）接收数据，根据指定的包长度（由pkglen_sel_i选择）将数据缓存、打包，
// 并通过外部接口发送出去，同时生成发送开始（fmt_start_o）和结束（fmt_end_o）标志，完成数据的格式化传输。
// 核心流程：接收仲裁器数据→缓存到FIFO→判断数据是否达到指定包长度→向外部请求发送权限→获得权限后按顺序发送数据→发送完成后复位准备下一包
module formater(
    input                      clk_i,               // 时钟信号，上升沿触发
    input                      rstn_i,              // 异步复位信号，低电平有效（复位时模块回到初始状态）
					  
    // 与仲裁器的接口信号
    output                     f2a_ack_o,           // 格式化器向仲裁器的应答信号，高电平表示已接收当前数据
    output                     fmt_id_req_o,        // 格式化器向仲裁器请求数据通道ID的信号，高电平表示需要新的ID
    input                      a2f_val_i,           // 仲裁器向格式化器的有效信号，高电平表示a2f_data_i数据有效
    input    [1:0]             a2f_id_i,            // 仲裁器传来的通道ID（00/01/10分别对应3个通道，11为无效）
    input    [31:0]            a2f_data_i,          // 仲裁器传来的32位数据
    input    [2:0]             pkglen_sel_i,        // 包长度选择信号，用于指定输出包的长度（4/8/16/32）
					  
    // 与外部的接口信号
    input                      fmt_grant_i,         // 外部授予的发送许可信号，高电平表示允许格式化器发送数据
    output   [1:0]             fmt_chid_o,          // 输出的通道ID，与接收的a2f_id_i保持一致
    output   [5:0]             fmt_length_o,        // 输出的包长度，由pkglen_sel_i解码得到
    output                     fmt_req_o,           // 向外部请求发送数据的信号，高电平表示请求发送
    output   [31:0]            fmt_data_o,          // 输出的32位数据，从FIFO中读取
    output                     fmt_start_o,         // 包发送开始标志，发送第一个数据时为高
    output                     fmt_end_o            // 包发送结束标志，发送最后一个数据时为高
);

// 内部寄存器定义：
reg [5:0]     length_r;              // 包长度寄存器，存储由pkglen_sel_i解码后的包长度（6位支持0~63）
reg [31:0]    fmt_fifo [0:31];       // 32深度的32位FIFO，用于缓存待发送的数据（最多存储32个32位数据）
reg [5:0]     cnt_rec_r;             // 接收计数器，记录已接收并写入FIFO的数据个数（FIFO写指针）
reg [5:0]     cnt_sen_r;             // 发送计数器，记录已从FIFO读出并发送的数据个数（FIFO读指针）
reg [31:0]    slv0_buffer_r;         // 通道0的数据缓冲区，当无法立即写入FIFO时暂存数据
reg [31:0]    slv1_buffer_r;         // 通道1的数据缓冲区
reg [31:0]    slv2_buffer_r;         // 通道2的数据缓冲区
reg [31:0]    fmt_data_r;            // 输出数据寄存器，寄存从FIFO读出的数据，用于驱动fmt_data_o
reg [2:0]     c_state, n_state;      // 状态机现态（c_state）和次态（n_state），控制整个模块的工作流程

reg buffer0_val_r;                   // 通道0缓冲区有效标志，高电平表示slv0_buffer_r中有有效数据
reg buffer1_val_r;                   // 通道1缓冲区有效标志
reg buffer2_val_r;                   // 通道2缓冲区有效标志

reg fmt_end_r;                       // 包结束标志寄存器，对应输出fmt_end_o
reg fmt_start_r;                     // 包开始标志寄存器，对应输出fmt_start_o
reg fmt_req_r;                       // 发送请求寄存器，对应输出fmt_req_o
reg fmt_ack_r;                       // 接收应答寄存器，对应输出f2a_ack_o
reg fmt_send_r;                      // 发送使能标志，控制FIFO读取和发送计数器递增
reg fmt_id_req_r;                    // ID请求寄存器，对应输出fmt_id_req_o

// 包长度解码逻辑：根据pkglen_sel_i选择包长度，复位时默认32
always @ (*) begin
  if (!rstn_i) length_r = 6'd32;
  else case (pkglen_sel_i) 
    3'd0 : length_r = 6'd4;    // 选择信号0对应包长度4
    3'd1 : length_r = 6'd8;    // 选择信号1对应包长度8
    3'd2 : length_r = 6'd16;   // 选择信号2对应包长度16
    3'd3 : length_r = 6'd32;   // 选择信号3对应包长度32
    default : length_r = 6'd32; // 其他情况默认32
  endcase
end 

// 接收计数器（FIFO写指针）逻辑：记录已接收数据个数，请求新ID时清零，接收有效数据时递增
always @ (posedge clk_i or negedge rstn_i) begin
  if (!rstn_i) cnt_rec_r <= 1'b0;
  else if (fmt_id_req_r) cnt_rec_r <= 1'b0;  // 请求新ID时，计数器清零（开始新包接收）
  else case (a2f_id_i)
    // 通道0：输入有效或缓冲区有数据，且应答有效时，计数+1
    2'b00 : if ((a2f_val_i | buffer0_val_r) && fmt_ack_r) cnt_rec_r <= cnt_rec_r + 1'b1;
    // 通道1：同上
    2'b01 : if ((a2f_val_i | buffer1_val_r) && fmt_ack_r) cnt_rec_r <= cnt_rec_r + 1'b1;
    // 通道2：同上
    2'b10 : if ((a2f_val_i | buffer2_val_r) && fmt_ack_r) cnt_rec_r <= cnt_rec_r + 1'b1;
    default : cnt_rec_r <= cnt_rec_r;  // 无效ID时计数不变
  endcase 
end 

// FIFO写入与缓冲区管理逻辑：将接收的数据写入FIFO，若当前无法写入则先存入缓冲区
always @ (posedge clk_i or negedge rstn_i) begin
  if (!rstn_i) begin  // 复位时初始化所有存储单元和标志
    fmt_fifo[cnt_rec_r] <= 32'hffff_ffff;
    slv0_buffer_r <= 32'hffff_ffff; buffer0_val_r <= 1'b0;
    slv1_buffer_r <= 32'hffff_ffff; buffer1_val_r <= 1'b0;
    slv2_buffer_r <= 32'hffff_ffff; buffer2_val_r <= 1'b0;
  end 
  else if (fmt_ack_r) begin  // 应答有效时（可以接收数据）
    case (a2f_id_i)
      2'b00 : begin  // 通道0：优先发送缓冲区数据，无缓冲时直接写入输入数据
        if (buffer0_val_r) begin fmt_fifo[cnt_rec_r] <= slv0_buffer_r; buffer0_val_r <= 1'b0; end 
        else if (a2f_val_i) fmt_fifo[cnt_rec_r] <= a2f_data_i;
      end
      2'b01 : begin  // 通道1：同上
        if (buffer1_val_r) begin fmt_fifo[cnt_rec_r] <= slv1_buffer_r; buffer1_val_r <= 1'b0; end 
        else if (a2f_val_i) fmt_fifo[cnt_rec_r] <= a2f_data_i;
      end
      2'b10 : begin  // 通道2：同上
        if (buffer2_val_r) begin fmt_fifo[cnt_rec_r] <= slv2_buffer_r; buffer2_val_r <= 1'b0; end 
        else if (a2f_val_i) fmt_fifo[cnt_rec_r] <= a2f_data_i;
      end
    endcase
  end
  else begin  // 应答无效时（无法接收数据），将输入数据存入对应通道的缓冲区
    case (a2f_id_i)
      2'b00 : if (a2f_val_i) begin slv0_buffer_r <= a2f_data_i; buffer0_val_r <= 1'b1; end
      2'b01 : if (a2f_val_i) begin slv1_buffer_r <= a2f_data_i; buffer1_val_r <= 1'b1; end
      2'b10 : if (a2f_val_i) begin slv2_buffer_r <= a2f_data_i; buffer2_val_r <= 1'b1; end 
    endcase 
  end
end 

// 发送计数器（FIFO读指针）逻辑：记录已发送数据个数，请求新ID时清零，发送数据时递增
always @ (posedge clk_i or negedge rstn_i) begin 
  if (!rstn_i) cnt_sen_r <= 1'b0;
  else if (fmt_id_req_r) cnt_sen_r <= 1'b0;  // 请求新ID时，计数器清零（开始新包发送）
  else if (fmt_send_r) cnt_sen_r <= cnt_sen_r + 1'b1;  // 发送使能时，计数+1
end 

// FIFO读取逻辑：从FIFO中读取数据到输出寄存器，供外部接口读取
always @ (*) begin
  if (!rstn_i) fmt_data_r <= 32'hffff_ffff;
  else if (fmt_send_r) fmt_data_r <= fmt_fifo[cnt_sen_r];  // 发送使能时，读取FIFO当前位置数据
  else fmt_data_r <= 32'hffff_ffff;  // 非发送时输出全1
end 

// 状态机定义及控制逻辑：通过状态机控制数据接收、请求发送、发送数据的全流程
// 状态定义：
// FMT_IDLE：空闲状态，等待接收足够数据
// FMT_REQ：请求发送状态，向外部申请发送权限
// FMT_WAIT_GRANT：等待许可状态，等待外部授予发送权限
// FMT_START：发送开始状态，发送第一个数据并置开始标志
// FMT_SEND：持续发送状态，发送后续数据
// FMT_END：发送结束状态，发送最后一个数据并置结束标志
parameter FMT_REQ = 3'b000;
parameter FMT_WAIT_GRANT = 3'b001;
parameter FMT_START = 3'b011;
parameter FMT_SEND = 3'b010;
parameter FMT_END = 3'b110;
parameter FMT_IDLE = 3'b111;

// 状态机现态更新：时钟沿触发，次态更新为现态
always @ (posedge clk_i or negedge rstn_i) begin
  if (!rstn_i) c_state <= FMT_IDLE;
  else c_state <= n_state;
end

// 状态机次态跳转逻辑：根据当前状态和条件确定次态
always @ (*) begin
  if (!rstn_i) n_state = FMT_IDLE;
  else case (c_state)
    FMT_IDLE :  // 空闲状态：当接收计数达到“包长度-1”时（下一个数据接收后即满），进入请求发送状态
      n_state = (cnt_rec_r == length_r - 2'd1) ? FMT_REQ : FMT_IDLE;
    FMT_REQ :  // 请求发送状态：当接收计数达到包长度时（数据已完全接收），进入等待许可状态
      n_state = (cnt_rec_r >= length_r) ? FMT_WAIT_GRANT : FMT_REQ;
    FMT_WAIT_GRANT :  // 等待许可状态：收到外部许可后进入发送开始状态
      n_state = fmt_grant_i ? FMT_START : FMT_WAIT_GRANT;
    FMT_START :  // 发送开始状态：发送第一个数据后进入持续发送状态
      n_state = FMT_SEND;
    FMT_SEND :  // 持续发送状态：当发送计数达到“包长度-2”时（下一个数据为最后一个），进入结束状态
      n_state = (cnt_sen_r == length_r - 2'd2) ? FMT_END : FMT_SEND;
    FMT_END :  // 结束状态：发送最后一个数据后返回空闲状态
      n_state = FMT_IDLE;
    default : n_state = FMT_IDLE;
  endcase 
end 

// 状态机输出控制：根据当前状态生成各类控制信号
always @ (*) begin
  if (!rstn_i) begin  // 复位时所有控制信号置默认值
    fmt_end_r = 1'b0;
    fmt_start_r = 1'b0;
    fmt_req_r = 1'b0;
    fmt_ack_r = 1'b0;
    fmt_send_r = 1'b0;
    fmt_id_req_r = 1'b1;  // 复位时默认请求ID
  end
  else case (c_state)
    FMT_IDLE : begin  // 空闲状态：允许接收数据，请求新ID
      fmt_ack_r = (a2f_id_i != 2'b11) ? 1'b1 : 1'b0;  // 有效通道ID时允许接收
      fmt_id_req_r = (a2f_id_i == 2'b11) ? 1'b1 : 1'b0;  // 无效ID时请求新ID
      fmt_end_r = 1'b0;
      fmt_start_r = 1'b0;
      fmt_req_r = 1'b0;
      fmt_send_r = 1'b0;
    end 
    FMT_REQ : begin  // 请求发送状态：向外部请求发送，数据满后停止接收
      fmt_ack_r = (cnt_rec_r >= length_r) ? 1'b0 : 1'b1;  // 数据满后停止接收
      fmt_req_r = 1'b1;  // 置发送请求
      fmt_end_r = 1'b0;
      fmt_start_r = 1'b0;
      fmt_send_r = 1'b0;
      fmt_id_req_r = 1'b0;
    end
    FMT_WAIT_GRANT : begin  // 等待许可状态：保持发送请求，停止接收
      fmt_req_r = 1'b1;
      fmt_ack_r = 1'b0;
      fmt_start_r = 1'b0;
      fmt_end_r = 1'b0;
      fmt_send_r = 1'b0;
      fmt_id_req_r = 1'b0;
    end
    FMT_START : begin  // 发送开始状态：发送第一个数据，置开始标志
      fmt_req_r = 1'b0;
      fmt_ack_r = 1'b0;
      fmt_start_r = 1'b1;  // 置开始标志
      fmt_end_r = 1'b0;
      fmt_send_r = 1'b1;  // 允许发送
      fmt_id_req_r = 1'b0;
    end
    FMT_SEND : begin  // 持续发送状态：发送中间数据
      fmt_req_r = 1'b0;
      fmt_ack_r = 1'b0;
      fmt_start_r = 1'b0;
      fmt_end_r = 1'b0;
      fmt_send_r = 1'b1;  // 持续发送
      fmt_id_req_r = 1'b0;
    end
    FMT_END : begin  // 发送结束状态：发送最后一个数据，置结束标志
      fmt_req_r = 1'b0;
      fmt_ack_r = 1'b0;
      fmt_start_r = 1'b0;
      fmt_end_r = 1'b1;  // 置结束标志
      fmt_send_r = 1'b1;  // 发送最后一个数据
      fmt_id_req_r = 1'b1;  // 请求新ID，准备下一包
    end
  endcase 
end 

// 输出端口赋值：将内部寄存器值映射到输出端口
assign fmt_id_req_o = fmt_id_req_r;
assign fmt_chid_o = a2f_id_i;
assign fmt_length_o = length_r;
assign fmt_req_o = fmt_req_r;
assign fmt_start_o = fmt_start_r;
assign fmt_end_o = fmt_end_r; 
assign f2a_ack_o = fmt_ack_r;
assign fmt_data_o = fmt_data_r;

endmodule 