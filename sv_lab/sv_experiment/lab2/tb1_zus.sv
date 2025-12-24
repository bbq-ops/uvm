// 时间单位定义：1ns为时间单位，1ps为时间精度（用于仿真时序控制）
`timescale 1ns/1ps

// 通道接口定义：用于连接数据发起端(initiator)和DUT，封装了数据传输相关信号及时钟块
interface chnl_intf(input clk, input rstn);  // 接口输入：系统时钟clk、异步复位rstn（低有效）
  logic [31:0] ch_data;      // 32位数据信号：传输的有效数据
  logic        ch_valid;     // 数据有效信号：高电平表示ch_data上的数据有效
  logic        ch_ready;     // 接收准备好信号：高电平表示接收端可接收数据（握手信号）
  logic [ 5:0] ch_margin;    // 通道余量信号：表示接收端剩余可接收数据的空间（用于流量控制）

  // 驱动时钟块：定义在clk上升沿同步驱动信号，用于确保信号同步性
  clocking drv_ck @(posedge clk);
    default input #1ns output #1ns;  // 输入信号延迟1ns采样，输出信号延迟1ns驱动（避免竞争冒险）
    output ch_data, ch_valid;        // 从发起端输出的信号（驱动方向）
    input ch_ready, ch_margin;       // 从接收端输入的信号（采样方向）
  endclocking
endinterface

// 通道发起器模块：负责通过接口向DUT发送数据，支持配置空闲周期和名称
module chnl_initiator(chnl_intf intf);  // 输入：通道接口实例
  string name;         // 发起器名称（用于打印信息区分不同通道）
  int idle_cycles = 1; // 数据间的空闲周期数（默认1个周期）

  // 配置空闲周期的函数：设置两个连续数据之间的空闲周期数
  function automatic void set_idle_cycles(int n);
    idle_cycles = n;  // 赋值外部输入的空闲周期数n
  endfunction

  // 配置名称的函数：设置发起器的名称（用于日志打印）
  function automatic void set_name(string s);
    name = s;  // 赋值外部输入的名称字符串s
  endfunction

  // 数据发送任务：通过接口向DUT发送一个32位数据
  task automatic chnl_write(input logic[31:0] data);
    @(posedge intf.clk);  // 等待时钟上升沿（同步到时钟）
    
    // TODO 1.1：应使用接口的drv_ck时钟块驱动信号（原代码直接驱动接口信号，建议修改为intf.drv_ck.xxx）
    intf.ch_valid <= 1;   // 驱动valid为高，表示数据有效
    intf.ch_data <= data; // 驱动数据到ch_data信号
    
    wait(intf.ch_ready === 'b1);  // 等待接收端ready为高（握手成功）
    // 打印发送信息：时间、发起器名称、发送的数据值
    $display("%t channel initiator [%s] sent data %x", $time, name, data);
    
    // TODO 1.2：根据idle_cycles插入空闲周期（原代码仅插入1个周期，需扩展为n个周期）
    chnl_idle();  // 调用空闲任务，插入空闲周期
  endtask

  // 空闲任务：在数据发送间隙插入空闲周期（驱动无效信号）
  task automatic chnl_idle();
    @(posedge intf.clk);  // 等待时钟上升沿（同步到时钟）
    
    // TODO 1.1：应使用接口的drv_ck时钟块驱动信号（建议修改为intf.drv_ck.xxx）
    intf.ch_valid <= 0;   // 驱动valid为低，表示无有效数据
    intf.ch_data <= 0;    // 数据信号清零（无效状态）
  endtask
endmodule

// 通道数据生成器：生成特定格式的测试数据，区分不同通道
module chnl_generator;
  int chnl_arr[$];  // 动态数组：存储已生成的数据（用于后续校验）
  int num;          // 数据计数器：记录当前通道已生成的数据个数
  int id;           // 通道ID：区分不同的生成器（0/1/2）

  // 初始化函数：设置通道ID并重置计数器
  function automatic void initialize(int n);
    id = n;    // 赋值通道ID（0/1/2对应三个通道）
    num = 0;   // 重置数据计数器（从0开始生成数据）
  endfunction

  // 生成数据的函数：按照固定格式生成数据并存储
  function automatic int get_data();
    int data;
    // 数据格式：固定前缀'h00C0_0000 + 通道ID左移16位（区分通道） + 计数器（区分同一通道的不同数据）
    data = 'h00C0_0000 + (id<<16) + num;
    num++;                // 计数器自增（下一个数据序号+1）
    chnl_arr.push_back(data);  // 将生成的数据存入数组（供后续比对）
    return data;          // 返回生成的数据
  endfunction
endmodule

// 测试平台模块：实例化DUT、接口、发起器和生成器，构建完整的测试环境
module tb1;
  logic         clk;        // 系统时钟
  logic         rstn;       // 异步复位（低有效）
  logic [31:0]  mcdt_data;  // DUT输出数据
  logic         mcdt_val;   // DUT输出数据有效信号
  logic [ 1:0]  mcdt_id;    // DUT输出数据对应的通道ID

  // 实例化DUT（多通道数据合并器）：连接各通道接口信号和输出信号
  mcdt dut(
     .clk_i       (clk                )  // 系统时钟输入
    ,.rstn_i      (rstn               )  // 异步复位输入（低有效）
    // 通道0信号连接
    ,.ch0_data_i  (chnl0_if.ch_data   )
    ,.ch0_valid_i (chnl0_if.ch_valid  )
    ,.ch0_ready_o (chnl0_if.ch_ready  )
    ,.ch0_margin_o(chnl0_if.ch_margin )
    // 通道1信号连接
    ,.ch1_data_i  (chnl1_if.ch_data   )
    ,.ch1_valid_i (chnl1_if.ch_valid  )
    ,.ch1_ready_o (chnl1_if.ch_ready  )
    ,.ch1_margin_o(chnl1_if.ch_margin )
    // 通道2信号连接
    ,.ch2_data_i  (chnl2_if.ch_data   )
    ,.ch2_valid_i (chnl2_if.ch_valid  )
    ,.ch2_ready_o (chnl2_if.ch_ready  )
    ,.ch2_margin_o(chnl2_if.ch_margin )
    // DUT输出信号
    ,.mcdt_data_o (mcdt_data          )
    ,.mcdt_val_o  (mcdt_val           )
    ,.mcdt_id_o   (mcdt_id            )
  );
  
  // 时钟生成：产生周期为10ns的时钟（5ns高电平，5ns低电平）
  initial begin 
    clk <= 0;         // 初始时钟为低
    forever begin     // 永久循环生成时钟
      #5 clk <= !clk; // 每5ns翻转一次（周期10ns）
    end
  end
  
  // 复位触发：产生复位信号（先有效后释放）
  initial begin 
    #10 rstn <= 0;        // 10ns后拉低复位（复位有效）
    repeat(10) @(posedge clk);  // 等待10个时钟周期（保持复位）
    rstn <= 1;            // 释放复位（复位无效）
  end
  
  // 验证组件初始化：配置生成器和发起器的参数
  initial begin 
    // 初始化三个通道的数据生成器（分别设置ID为0、1、2）
    chnl0_gen.initialize(0);
    chnl1_gen.initialize(1);
    chnl2_gen.initialize(2);
    // 设置三个发起器的名称（用于打印区分）
    chnl0_init.set_name("chnl0_init");
    chnl1_init.set_name("chnl1_init");
    chnl2_init.set_name("chnl2_init");
    // 设置三个发起器的数据间空闲周期为0（连续发送）
    chnl0_init.set_idle_cycles(0);
    chnl1_init.set_idle_cycles(0);
    chnl2_init.set_idle_cycles(0);   
  end

  // 通道0发送任务：复位释放后发送100个数据
  initial begin
    @(posedge rstn);       // 等待复位释放（rstn上升沿）
    repeat(5) @(posedge clk);  // 额外等待5个时钟周期（确保系统稳定）
    repeat(100) begin      // 循环发送100个数据
      // 从生成器获取数据并通过发起器发送
      chnl0_init.chnl_write(chnl0_gen.get_data());      
    end
    chnl0_init.chnl_idle();  // 发送完成后进入空闲状态
  end
 
  // 通道1发送任务：与通道0逻辑相同，发送100个数据
  initial begin
    @(posedge rstn);
    repeat(5) @(posedge clk);
    repeat(100) begin
      chnl1_init.chnl_write(chnl1_gen.get_data());  
    end
    chnl1_init.chnl_idle(); 
  end

  // 通道2发送任务：与通道0/1逻辑相同，发送100个数据
  initial begin
    @(posedge rstn);
    repeat(5) @(posedge clk);
    repeat(100) begin
      chnl2_init.chnl_write(chnl2_gen.get_data());
    end
    chnl2_init.chnl_idle(); 
  end
  
  // 实例化三个通道的接口（复用当前模块的clk和rstn，通过.*简化连接）
  chnl_intf chnl0_if(.*);
  chnl_intf chnl1_if(.*);
  chnl_intf chnl2_if(.*);

  // 实例化三个通道的发起器（分别连接到对应的接口）
  chnl_initiator chnl0_init(chnl0_if);
  chnl_initiator chnl1_init(chnl1_if);
  chnl_initiator chnl2_init(chnl2_if);

  // 实例化三个通道的数据生成器
  chnl_generator chnl0_gen();
  chnl_generator chnl1_gen();
  chnl_generator chnl2_gen();

endmodule