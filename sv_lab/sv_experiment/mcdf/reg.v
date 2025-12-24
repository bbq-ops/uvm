//------------------------------------------------------------------------------------------------------------------------//
// 模块名称：ctrl_regs（控制寄存器模块）
// 模块功能：用于配置和读取3个从设备（slv0、slv1、slv2）的参数，包括：
//           1. 可读写配置：包长度（pkglen）、优先级（prio）、使能状态（en）
//           2. 只读状态：各从设备FIFO的余量（margin，用于指示FIFO当前可用空间）
// 版本历史：
// 2017-08-13: V0.1 zhangshi   初始版本
// 2017-11-09: V0.2 zhangshi   优化：读写寄存器的保留位不允许写入（仅有效位可写）
//------------------------------------------------------------------------------------------------------------------------//
 
`include "param_def.v"  // 包含参数定义文件（如地址宽度、数据宽度、寄存器地址映射等）

module ctrl_regs(	
    clk_i,              // 时钟信号，上升沿触发
    rstn_i,             // 异步复位信号，低电平有效
    cmd_i,              // 命令信号（2位）：用于指示读/写操作（`READ表示读，`WRITE表示写，定义在param_def.v中）
    cmd_addr_i,         // 命令地址（宽度由`ADDR_WIDTH定义）：用于选择操作的寄存器地址
    cmd_data_i,         // 写入数据（宽度由`CMD_DATA_WIDTH定义）：写操作时的输入数据
    cmd_data_o,         // 读出数据（宽度同cmd_data_i）：读操作时的输出数据
    slv0_pkglen_o,      // slv0的包长度输出（配置值）
    slv1_pkglen_o,      // slv1的包长度输出
    slv2_pkglen_o,      // slv2的包长度输出
    slv0_prio_o,        // slv0的优先级输出（配置值）
    slv1_prio_o,        // slv1的优先级输出
    slv2_prio_o,        // slv2的优先级输出
    slv0_margin_i,      // slv0的FIFO余量输入（指示FIFO当前可用空间）
    slv1_margin_i,      // slv1的FIFO余量输入
    slv2_margin_i,      // slv2的FIFO余量输入
    slv0_en_o,          // slv0的使能输出（1=使能，0=禁用）
    slv1_en_o,          // slv1的使能输出
    slv2_en_o           // slv2的使能输出
);

// 输入端口定义
input clk_i;  // 时钟
input rstn_i;  // 异步复位（低有效）
input [1:0] cmd_i;  // 命令（读/写控制）
input [`ADDR_WIDTH-1:0] cmd_addr_i;  // 寄存器地址（宽度由`ADDR_WIDTH决定，如3位对应8个地址）
input [`CMD_DATA_WIDTH-1:0] cmd_data_i;  // 写入数据（宽度由`CMD_DATA_WIDTH决定，如32位）
// FIFO余量输入（宽度由`FIFO_MARGIN_WIDTH决定，如8位，指示FIFO可用空间大小）
input [`FIFO_MARGIN_WIDTH-1:0] slv0_margin_i;
input [`FIFO_MARGIN_WIDTH-1:0] slv1_margin_i;
input [`FIFO_MARGIN_WIDTH-1:0] slv2_margin_i;

// 内部寄存器定义
reg [`CMD_DATA_WIDTH-1:0] mem [5:0];  // 寄存器存储数组（共6个寄存器，地址0~5，映射关系见param_def.v）
reg [`CMD_DATA_WIDTH-1:0] cmd_data_reg;  // 读数据寄存器（缓存读出的数据，驱动cmd_data_o）

// 输出端口定义
output [`CMD_DATA_WIDTH-1:0] cmd_data_o;  // 读出数据输出
// 包长度输出（宽度由`PAC_LEN_WIDTH决定，如3位，对应4/8/16/32等包长）
output [`PAC_LEN_WIDTH-1:0] slv0_pkglen_o;
output [`PAC_LEN_WIDTH-1:0] slv1_pkglen_o;
output [`PAC_LEN_WIDTH-1:0] slv2_pkglen_o;
// 优先级输出（宽度由`PRIO_WIDTH决定，如2位，对应不同优先级等级）
output [`PRIO_WIDTH-1:0] slv0_prio_o;
output [`PRIO_WIDTH-1:0] slv1_prio_o;
output [`PRIO_WIDTH-1:0] slv2_prio_o;
// 使能输出（1位，高电平有效）
output slv0_en_o;
output slv1_en_o;
output slv2_en_o;

//--------------------------------------------------------------------------------------
// 块1：FIFO余量寄存器更新（只读寄存器）
// 功能：实时将slv0~slv2的FIFO余量（slvX_margin_i）存入对应的只读寄存器，供外部读取
// 说明：这些寄存器只能被读取，不能通过写命令修改
//--------------------------------------------------------------------------------------
always @ (posedge clk_i or negedge rstn_i) begin 
  if (!rstn_i) begin  // 复位时初始化只读寄存器（默认FIFO深度为32，故余量初始化为32）
    mem [`SLV0_R_REG] <= 32'h00000020;  // `SLV0_R_REG：slv0的只读寄存器地址（定义在param_def.v）
    mem [`SLV1_R_REG] <= 32'h00000020;  // `SLV1_R_REG：slv1的只读寄存器地址
    mem [`SLV2_R_REG] <= 32'h00000020;  // `SLV2_R_REG：slv2的只读寄存器地址
  end else begin  // 正常工作时，将输入的余量信号存入寄存器（高24位补0，低8位存余量）
    mem [`SLV0_R_REG] <= {24'b0, slv0_margin_i};  // 拼接：24位0 + 8位余量（假设`FIFO_MARGIN_WIDTH=8）
    mem [`SLV1_R_REG] <= {24'b0, slv1_margin_i};
    mem [`SLV2_R_REG] <= {24'b0, slv2_margin_i};
  end
end

//--------------------------------------------------------------------------------------
// 块2：读写寄存器写操作
// 功能：处理外部写命令，更新slv0~slv2的配置寄存器（读写寄存器）
// 关键：仅写入有效位（低6位），高26位为保留位（不允许修改，保持0），符合V0.2版本优化
//--------------------------------------------------------------------------------------
always @ (posedge clk_i or negedge rstn_i) begin
  if (!rstn_i) begin  // 复位时初始化读写寄存器（默认值32'h00000007）
    // 假设默认配置：使能（bit0=1）、优先级为0（bit1~2=00）、包长度为4（bit3~5=001），具体由位定义决定
    mem [`SLV0_RW_REG] = 32'h00000007;  // `SLV0_RW_REG：slv0的读写寄存器地址
    mem [`SLV1_RW_REG] = 32'h00000007;  // `SLV1_RW_REG：slv1的读写寄存器地址
    mem [`SLV2_RW_REG] = 32'h00000007;  // `SLV2_RW_REG：slv2的读写寄存器地址
  end else if (cmd_i == `WRITE) begin  // 当命令为写操作时（`WRITE定义在param_def.v）
    case (cmd_addr_i)  // 根据地址选择要写入的寄存器
      `SLV0_RW_ADDR:  // 写slv0的读写寄存器
        // 仅写入低6位（有效位），高26位保留为0（防止修改保留位）
        mem[`SLV0_RW_REG] <= {26'b0, cmd_data_i[`PAC_LEN_HIGH:0]};  
      `SLV1_RW_ADDR:  // 写slv1的读写寄存器（逻辑同上）
        mem[`SLV1_RW_REG] <= {26'b0, cmd_data_i[`PAC_LEN_HIGH:0]};  
      `SLV2_RW_ADDR:  // 写slv2的读写寄存器（逻辑同上）
        mem[`SLV2_RW_REG] <= {26'b0, cmd_data_i[`PAC_LEN_HIGH:0]};   
    endcase 
  end
end 

//--------------------------------------------------------------------------------------
// 块3：寄存器读操作
// 功能：处理外部读命令，从指定寄存器（读写寄存器或只读寄存器）读取数据，存入cmd_data_reg
//--------------------------------------------------------------------------------------
always @ (posedge clk_i or negedge rstn_i) begin
  if (!rstn_i) begin
    cmd_data_reg <= 32'b0;  // 复位时读数据寄存器清零
  end else if (cmd_i == `READ) begin  // 当命令为读操作时（`READ定义在param_def.v）
    case (cmd_addr_i)  // 根据地址选择要读取的寄存器
      `SLV0_RW_ADDR: cmd_data_reg <= mem[`SLV0_RW_REG];  // 读slv0的读写寄存器
      `SLV1_RW_ADDR: cmd_data_reg <= mem[`SLV1_RW_REG];  // 读slv1的读写寄存器
      `SLV2_RW_ADDR: cmd_data_reg <= mem[`SLV2_RW_REG];  // 读slv2的读写寄存器
      `SLV0_R_ADDR:  cmd_data_reg <= mem[`SLV0_R_REG];   // 读slv0的只读寄存器（FIFO余量）
      `SLV1_R_ADDR:  cmd_data_reg <= mem[`SLV1_R_REG];   // 读slv1的只读寄存器
      `SLV2_R_ADDR:  cmd_data_reg <= mem[`SLV2_R_REG];   // 读slv2的只读寄存器
    endcase
  end
end

//--------------------------------------------------------------------------------------
// 输出端口赋值：将内部寄存器的值映射到输出端口
//--------------------------------------------------------------------------------------
assign cmd_data_o = cmd_data_reg;  // 读数据输出（来自读数据寄存器）

// 包长度输出：从读写寄存器的指定位段提取（`PAC_LEN_HIGH~`PAC_LEN_LOW定义包长度的位范围）
assign slv0_pkglen_o = mem[`SLV0_RW_REG][`PAC_LEN_HIGH:`PAC_LEN_LOW];
assign slv1_pkglen_o = mem[`SLV1_RW_REG][`PAC_LEN_HIGH:`PAC_LEN_LOW];
assign slv2_pkglen_o = mem[`SLV2_RW_REG][`PAC_LEN_HIGH:`PAC_LEN_LOW];

// 优先级输出：从读写寄存器的指定位段提取（`PRIO_HIGH~`PRIO_LOW定义优先级的位范围）
assign slv0_prio_o = mem[`SLV0_RW_REG][`PRIO_HIGH:`PRIO_LOW];
assign slv1_prio_o = mem[`SLV1_RW_REG][`PRIO_HIGH:`PRIO_LOW];
assign slv2_prio_o = mem[`SLV2_RW_REG][`PRIO_HIGH:`PRIO_LOW];

// 使能输出：从读写寄存器的bit0提取（bit0定义为使能位）
assign slv0_en_o = mem[`SLV0_RW_REG][0];
assign slv1_en_o = mem[`SLV1_RW_REG][0];
assign slv2_en_o = mem[`SLV2_RW_REG][0];

endmodule