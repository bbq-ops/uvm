// 时间单位定义：仿真时间单位1ns，时间精度1ps，用于控制仿真时序精度
`timescale 1ns/1ps

// 定义通道接口chnl_intf，封装DUT与测试平台之间的信号交互
// 输入参数：clk（时钟）、rstn（低电平复位）
interface chnl_intf(input clk, input rstn);
  // 接口信号定义
  logic [31:0] ch_data;    // 32位通道数据信号
  logic        ch_valid;   // 数据有效信号（高电平表示data有效）
  logic        ch_ready;   // 接收就绪信号（高电平表示DUT可接收数据）
  logic [ 5:0] ch_margin;  // 通道余量信号（表示DUT内部缓存剩余空间）

  // 定义驱动时钟块drv_ck，同步于clk上升沿
  // 用于测试平台驱动接口信号，避免时序竞争
  clocking drv_ck @(posedge clk);
    // 默认时序约束：输入信号延迟1ns采样，输出信号延迟1ns驱动
    default input #1ns output #1ns;
    output ch_data, ch_valid;  // 测试平台需要驱动的信号
    input ch_ready, ch_margin; // 测试平台需要采样的信号
  endclocking
endinterface

// 通道发起器模块chnl_initiator：实现通道数据发送逻辑
// 输入：chnl_intf接口实例，通过接口与DUT交互
module chnl_initiator(chnl_intf intf);
  string name;             // 发起器名称，用于打印日志区分不同通道
  int idle_cycles = 1;     // 数据间空闲周期数，默认1个周期

  // 设置空闲周期数的函数：外部可调用该函数配置数据间的空闲时间
  function automatic void set_idle_cycles(int n);
    idle_cycles = n;  // 将输入的n赋值给idle_cycles
  endfunction

  // 设置发起器名称的函数：用于日志中区分不同通道（如chnl0/chnl1/chnl2）
  function automatic void set_name(string s);
    name = s;  // 将输入的字符串s赋值给name
  endfunction

  // 数据发送任务chnl_write：核心任务，实现单条数据的发送逻辑
  // 输入：32位数据data，需发送给DUT
  task automatic chnl_write(input logic[31:0] data);
    @(posedge intf.clk);  // 等待接口时钟上升沿，同步开始驱动信号
    
    // TODO1.1 已解决：通过接口的drv_ck时钟块驱动数据和有效信号
    // 遵循时钟块时序约束，避免信号竞争
    intf.drv_ck.ch_valid <= 1;  // 置高valid，表示数据有效
    intf.drv_ck.ch_data <= data; // 驱动数据到ch_data信号

    // 新增时序优化：等待时钟下降沿
    // 确保ch_valid和ch_data在时钟高电平期间稳定，避免DUT采样不稳定
    @(negedge intf.clk);
    
    // 等待DUT就绪：直到ch_ready为高电平，表示DUT可接收数据
    wait(intf.ch_ready === 'b1);
    
    // 打印发送日志：包含当前时间、发起器名称、发送数据值
    $display("%t channel initiator [%s] sent data %x", $time, name, data);

    // TODO1.2 已解决：根据idle_cycles插入指定数量的空闲周期
    // 循环调用chnl_idle（单周期空闲），实现多周期空闲
    // 若idle_cycles=0，无空闲；=1则1个周期空闲，以此类推
    repeat(idle_cycles) chnl_idle();
  endtask

  // 空闲周期任务chnl_idle：实现单个周期的空闲状态
  // 功能：将ch_valid置低，停止发送数据，进入空闲
  task automatic chnl_idle();
    @(posedge intf.clk);  // 等待时钟上升沿，同步驱动空闲信号
    
    // TODO1.1 已解决：通过drv_ck时钟块驱动空闲状态
    intf.drv_ck.ch_valid <= 0;  // 置低valid，表示无有效数据
    intf.drv_ck.ch_data <= 0;   // 数据信号清零（空闲时无效）
  endtask
endmodule

// 通道数据生成器chnl_generator：生成各通道的测试数据
// 功能：为每个通道生成特定格式的32位数据，并缓存生成的数据
module chnl_generator;
  int chnl_arr[$];  // 动态数组，缓存已生成的数据，用于后续比对（若需）
  int num;          // 数据计数器，记录当前生成的第几个数据
  int id;           // 通道ID（0/1/2），用于区分不同通道的数据格式

  // 初始化函数：为生成器配置通道ID，并重置数据计数器
  // 输入n：通道ID（0对应chnl0，1对应chnl1，2对应chnl2）
  function automatic void initialize(int n);
    id = n;    // 赋值通道ID
    num = 0;   // 重置数据计数器为0，从第0个数据开始生成
  endfunction

  // 数据生成函数：生成1个32位数据并返回，同时存入缓存数组
  function automatic int get_data();
    int data;  // 临时变量，存储生成的数据
    
    // 数据格式定义：
    // 高16位：0x00C0（固定前缀）
    // 中8位：通道ID左移16位（区分通道）
    // 低16位：数据计数器num（区分同通道内不同数据）
    data = 'h00C0_0000 + (id<<16) + num;
    
    num++;                // 数据计数器自增1，下次生成下一个数据
    chnl_arr.push_back(data);  // 将生成的数据存入缓存数组
    return data;          // 返回生成的数据给发起器
  endfunction
endmodule

// 测试平台主模块tb1_ref：实例化DUT、接口、测试组件，生成激励并驱动DUT
module tb1_ref;
  // 测试平台内部信号定义
  logic         clk;         // 全局时钟信号，连接DUT和接口
  logic         rstn;        // 全局低电平复位信号，连接DUT和接口
  logic [31:0]  mcdt_data;   // DUT输出的合并后数据
  logic         mcdt_val;    // DUT输出数据有效信号
  logic [ 1:0]  mcdt_id;     // DUT输出的通道ID（标识数据来自哪个输入通道）

  // 实例化待测设计（DUT）：mcdt（多通道数据合并器，假设功能是合并3个输入通道数据）
  mcdt dut(
     .clk_i       (clk                )  // 时钟输入
    ,.rstn_i      (rstn               )  // 复位输入
    // chnl0通道信号连接：接口输出→DUT输入
    ,.ch0_data_i  (chnl0_if.ch_data   )
    ,.ch0_valid_i (chnl0_if.ch_valid  )
    ,.ch0_ready_o (chnl0_if.ch_ready  )  // DUT输出→接口输入
    ,.ch0_margin_o(chnl0_if.ch_margin )
    // chnl1通道信号连接
    ,.ch1_data_i  (chnl1_if.ch_data   )
    ,.ch1_valid_i (chnl1_if.ch_valid  )
    ,.ch1_ready_o (chnl1_if.ch_ready  )
    ,.ch1_margin_o(chnl1_if.ch_margin )
    // chnl2通道信号连接
    ,.ch2_data_i  (chnl2_if.ch_data   )
    ,.ch2_valid_i (chnl2_if.ch_valid  )
    ,.ch2_ready_o (chnl2_if.ch_ready  )
    ,.ch2_margin_o(chnl2_if.ch_margin )
    // DUT输出信号：合并后的数据、有效信号、通道ID
    ,.mcdt_data_o (mcdt_data          )
    ,.mcdt_val_o  (mcdt_val           )
    ,.mcdt_id_o   (mcdt_id            )
  );
  
  // 时钟生成模块：生成周期为10ns的时钟（#5翻转一次，高低电平各5ns）
  initial begin 
    clk <= 0;          // 初始时钟为低电平
    forever begin       // 无限循环，持续生成时钟
      #5 clk <= !clk;  // 每5ns翻转时钟电平
    end
  end
  
  // 复位信号生成：生成异步低电平复位，复位持续10个时钟周期
  initial begin 
    #10 rstn <= 0;                 // 10ns时拉低复位
    repeat(10) @(posedge clk);     // 等待10个时钟上升沿（持续100ns）
    rstn <= 1;                     // 释放复位，DUT进入正常工作状态
  end
  
  // 测试组件初始化：配置数据生成器和发起器的参数
  initial begin 
    // 初始化3个通道的数据生成器，分别配置通道ID为0、1、2
    chnl0_gen.initialize(0);
    chnl1_gen.initialize(1);
    chnl2_gen.initialize(2);
    
    // 为3个通道的发起器设置名称，用于日志区分
    chnl0_init.set_name("chnl0_init");
    chnl1_init.set_name("chnl1_init");
    chnl2_init.set_name("chnl2_init");
    
    // 配置3个通道的空闲周期为0：数据连续发送，无空闲间隔
    chnl0_init.set_idle_cycles(0);
    chnl1_init.set_idle_cycles(0);
    chnl2_init.set_idle_cycles(0);   
  end

  // chnl0通道激励生成：复位释放后，发送100个数据
  initial begin
    @(posedge rstn);               // 等待复位释放（rstn上升沿）
    repeat(5) @(posedge clk);      // 额外等待5个时钟周期，确保DUT稳定
    repeat(100) begin              // 循环100次，发送100个数据
      // 调用发起器的write任务，发送生成器生成的数据
      chnl0_init.chnl_write(chnl0_gen.get_data());      
    end
    chnl0_init.chnl_idle();        // 发送完成后，进入空闲状态
  end
 
  // chnl1通道激励生成：逻辑与chnl0完全一致，发送100个数据
  initial begin
    @(posedge rstn);
    repeat(5) @(posedge clk);
    repeat(100) begin
      chnl1_init.chnl_write(chnl1_gen.get_data());  
    end
    chnl1_init.chnl_idle(); 
  end

  // chnl2通道激励生成：逻辑与chnl0完全一致，发送100个数据
  initial begin
    @(posedge rstn);
    repeat(5) @(posedge clk);
    repeat(100) begin
      chnl2_init.chnl_write(chnl2_gen.get_data());
    end
    chnl2_init.chnl_idle(); 
  end

  // 实例化3个通道接口：分别对应chnl0、chnl1、chnl2
  // 采用通配符连接（.*），自动连接clk和rstn信号
  chnl_intf chnl0_if(.*);
  chnl_intf chnl1_if(.*);
  chnl_intf chnl2_if(.*);

  // 实例化3个通道发起器：分别连接到对应的通道接口
  chnl_initiator chnl0_init(chnl0_if);
  chnl_initiator chnl1_init(chnl1_if);
  chnl_initiator chnl2_init(chnl2_if);

  // 实例化3个通道数据生成器：分别为3个通道生成测试数据
  chnl_generator chnl0_gen();
  chnl_generator chnl1_gen();
  chnl_generator chnl2_gen();

endmodule