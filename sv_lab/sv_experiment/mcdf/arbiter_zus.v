//------------------------------------------------------------------------------------------------------------------------//
//change log 2017-08-20 Arbiter complete package length select and keep Not in Formater
//                      Need to update to configurable round robin arbiter  -----  @@ZS
//------------------------------------------------------------------------------------------------------------------------//
module arbiter(
    // 时钟与复位信号
    input                    clk_i,                  // 时钟信号，上升沿有效
    input                    rstn_i,                 // 异步复位信号，低电平有效（复位时模块进入初始状态）

    // 与配置寄存器的接口：接收从设备的优先级和包长度配置参数
    input  [1:0]             slv0_prio_i,            // slave0的优先级配置（2位宽，数值越大优先级越高）
    input  [1:0]             slv1_prio_i,            // slave1的优先级配置
    input  [1:0]             slv2_prio_i,            // slave2的优先级配置
    input [2:0]              slv0_pkglen_i,          // slave0的包长度选择配置（对应Formater的包长度解码）
    input [2:0]              slv1_pkglen_i,          // slave1的包长度选择配置
    input [2:0]              slv2_pkglen_i,          // slave2的包长度选择配置

    // 与3个从设备（slave port）的接口：接收从设备数据/请求，输出应答
    input  [31:0]            slv0_data_i,            // slave0输出的32位数据
    input  [31:0]            slv1_data_i,            // slave1输出的32位数据
    input  [31:0]            slv2_data_i,            // slave2输出的32位数据
    input                    slv0_req_i,             // slave0的请求信号（高电平=需要向Formater发送数据）
    input                    slv1_req_i,             // slave1的请求信号
    input                    slv2_req_i,             // slave2的请求信号
    input                    slv0_val_i,             // slave0的数据有效信号（高电平=slv0_data_i有效）
    input                    slv1_val_i,             // slave1的数据有效信号
    input                    slv2_val_i,             // slave2的数据有效信号
    output                   a2s0_ack_o,             // 仲裁器给slave0的应答信号（确认已接收数据）
    output                   a2s1_ack_o,             // 仲裁器给slave1的应答信号
    output                   a2s2_ack_o,             // 仲裁器给slave2的应答信号

    // 与格式化器（Formater）的接口：输出数据/控制信号，接收请求/应答
    input                    f2a_id_req_i,           // Formater的ID请求信号（高电平=需要新的通信通道）
    input                    f2a_ack_i,              // Formater的应答信号（高电平=已接收仲裁器数据）
    output                   a2f_val_o,              // 仲裁器给Formater的数据有效信号（高电平=数据有效）
    output [1:0]             a2f_id_o,               // 仲裁器给Formater的选中通道ID（00=slave0，01=slave1，10=slave2，11=无效）
    output [31:0]            a2f_data_o,             // 仲裁器给Formater的32位数据（取自选中通道）
    output [2:0]             a2f_pkglen_sel_o        // 仲裁器给Formater的包长度选择信号（取自选中通道）
);

// 内部寄存器定义：寄存输出到Formater的控制信号和数据，保证时序稳定
reg                   a2f_val_r;                 // 对应a2f_val_o，向Formater的数据有效信号寄存器
reg [1:0]             a2f_id_r;                  // 对应a2f_id_o，向Formater的通道ID寄存器
reg [31:0]            a2f_data_r;                // 对应a2f_data_o，向Formater的数据寄存器
reg [1:0]             id_sel_r;                  // 核心选择寄存器：存储当前选中的通道ID（00/01/10/11）
reg [2:0]             a2f_pkglen_sel_r;          // 对应a2f_pkglen_sel_o，包长度选择信号寄存器

//---------------------------------通道选择与优先级仲裁逻辑-------------------------//
// 触发条件：时钟上升沿或异步复位；核心功能：Formater请求新ID时，按请求+优先级选择唯一通道
always @ (posedge clk_i or negedge rstn_i)
begin : CHANEL_SELECT  // 块名：通道选择逻辑
    if (!rstn_i) begin
        id_sel_r         <= 2'b11;          // 复位时选中无效通道（2'b11），避免误触发
        a2f_pkglen_sel_r <= 3'b111;         // 复位时包长度选择信号置无效
    end
    // 仅当Formater请求新ID（f2a_id_req_i=1）时执行选择逻辑，否则保持当前状态
    else if (f2a_id_req_i) begin
        // 按3个从设备的请求信号组合（{slv2_req_i,slv1_req_i,slv0_req_i}）分类处理
        case ({slv2_req_i,slv1_req_i,slv0_req_i})  
            3'b001: begin  // 场景1：仅slave0请求
                id_sel_r         <= 2'b00;          // 选中slave0
                a2f_pkglen_sel_r <= slv0_pkglen_i;  // 包长度配置取自slave0
            end 
            
            3'b010: begin  // 场景2：仅slave1请求
                id_sel_r         <= 2'b01;          // 选中slave1
                a2f_pkglen_sel_r <= slv1_pkglen_i;  // 包长度配置取自slave1
            end 
            
            3'b011: begin  // 场景3：slave0和slave1同时请求
                // 优先级判断：数值大的优先，相等时选中slave1
                if(slv1_prio_i >= slv0_prio_i) begin
                    id_sel_r         <= 2'b01;
                    a2f_pkglen_sel_r <= slv1_pkglen_i;
                end else begin
                    id_sel_r         <= 2'b00;
                    a2f_pkglen_sel_r <= slv0_pkglen_i;
                end 
            end 
            
            3'b100: begin  // 场景4：仅slave2请求
                id_sel_r         <= 2'b10;          // 选中slave2
                a2f_pkglen_sel_r <= slv2_pkglen_i;  // 包长度配置取自slave2
            end 
            
            3'b101: begin  // 场景5：slave0和slave2同时请求
                // 优先级判断：数值大的优先，相等时选中slave2
                if(slv2_prio_i >= slv0_prio_i) begin
                    id_sel_r         <= 2'b10;
                    a2f_pkglen_sel_r <= slv2_pkglen_i;
                end else begin
                    id_sel_r         <= 2'b00;
                    a2f_pkglen_sel_r <= slv0_pkglen_i;
                end 
            end
            
            3'b110: begin  // 场景6：slave1和slave2同时请求
                // 优先级判断：数值大的优先，相等时选中slave2
                if(slv2_prio_i >= slv1_prio_i) begin
                    id_sel_r         <= 2'b10;
                    a2f_pkglen_sel_r <= slv2_pkglen_i;
                end else begin
                    id_sel_r         <= 2'b01;
                    a2f_pkglen_sel_r <= slv1_pkglen_i;
                end 
            end
            
            3'b111: begin  // 场景7：三个从设备同时请求（最高优先级仲裁）
                // 用if-else if实现互斥判断，确保仅选中一个设备
                if((slv0_prio_i >= slv1_prio_i) && (slv0_prio_i >= slv2_prio_i)) begin
                    id_sel_r         <= 2'b00;  // slave0优先级最高
                    a2f_pkglen_sel_r <= slv0_pkglen_i;
                end else if((slv1_prio_i >= slv0_prio_i) && (slv1_prio_i >= slv2_prio_i)) begin
                    id_sel_r         <= 2'b01;  // slave1优先级最高
                    a2f_pkglen_sel_r <= slv1_pkglen_i;
                end else begin
                    id_sel_r         <= 2'b10;  // slave2优先级最高（兜底条件，无遗漏）
                    a2f_pkglen_sel_r <= slv2_pkglen_i;
                end 
            end

            default: begin  // 场景8：无任何请求或异常组合
                id_sel_r         <= 2'b11;          // 选中无效通道
                a2f_pkglen_sel_r <= 3'b111;         // 包长度信号置无效
            end 
        endcase 
    end
    else begin  // Formater未请求新ID，保持当前通道和包长度配置
        id_sel_r         <= id_sel_r;
        a2f_pkglen_sel_r <= a2f_pkglen_sel_r;
    end 
end 

//---------------------------------数据与控制信号映射逻辑-------------------------//
// 触发条件：选中通道ID或从设备数据/有效信号变化；核心功能：将选中通道信号映射到Formater输出寄存器
always@( id_sel_r or slv0_data_i or slv1_data_i or slv2_data_i or
         slv0_val_i or slv1_val_i or slv2_val_i) begin
    case (id_sel_r)
        2'b00: begin  // 选中slave0
            a2f_id_r   = 2'b00;              // 输出slave0的通道ID
            a2f_data_r = slv0_data_i;        // 输出slave0的数据
            a2f_val_r  = slv0_val_i;         // 输出slave0的数据有效信号
        end
        2'b01: begin  // 选中slave1
            a2f_id_r   = 2'b01;              // 输出slave1的通道ID
            a2f_data_r = slv1_data_i;        // 输出slave1的数据
            a2f_val_r  = slv1_val_i;         // 输出slave1的数据有效信号
        end
        2'b10: begin  // 选中slave2
            a2f_id_r   = 2'b10;              // 输出slave2的通道ID
            a2f_data_r = slv2_data_i;        // 输出slave2的数据
            a2f_val_r  = slv2_val_i;         // 输出slave2的数据有效信号
        end
        default : begin  // 选中无效通道
            a2f_id_r   = 2'b11;              // 输出无效ID
            a2f_data_r = 32'hffff_ffff;      // 输出无效数据（全1填充）
            a2f_val_r  = 1'b0;               // 输出无效数据有效信号（低电平）
        end
    endcase
end

//---------------------------------从设备应答信号生成逻辑-------------------------//
// 核心功能：将Formater的应答信号（f2a_ack_i）定向转发给当前选中的从设备，未选中设备应答为低
assign a2s0_ack_o = (id_sel_r == 2'b00) ? f2a_ack_i : 1'b0;  // 选中slave0时转发应答
assign a2s1_ack_o = (id_sel_r == 2'b01) ? f2a_ack_i : 1'b0;  // 选中slave1时转发应答
assign a2s2_ack_o = (id_sel_r == 2'b10) ? f2a_ack_i : 1'b0;  // 选中slave2时转发应答

//---------------------------------输出端口赋值-------------------------//
// 核心功能：将内部寄存器值映射到模块输出端口，驱动Formater输入
assign a2f_val_o        = a2f_val_r;                  // 数据有效信号输出
assign a2f_id_o         = a2f_id_r;                   // 选中通道ID输出
assign a2f_data_o       = a2f_data_r;                 // 数据输出
assign a2f_pkglen_sel_o = a2f_pkglen_sel_r;           // 包长度选择信号输出

endmodule