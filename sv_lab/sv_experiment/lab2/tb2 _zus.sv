// 设置时间单位为1ns，时间精度为1ps，用于仿真时的时间计算
`timescale 1ns/1ps

// 定义通道接口(interface)，封装通道相关信号，简化模块间连接
// 输入clk(时钟)和rstn(异步复位，低有效)
interface chnl_intf(input clk, input rstn);
  logic [31:0] ch_data;    // 32位通道数据信号
  logic        ch_valid;   // 数据有效信号(高有效：表示ch_data上数据有效)
  logic        ch_ready;   // 接收就绪信号(高有效：表示接收端可接收数据)
  logic [ 5:0] ch_margin;  // FIFO余量信号(表示通道FIFO剩余空间，6位最大表示64)

  // 定义驱动时钟块(drv_ck)，用于激励端同步驱动信号
  // 时钟块在clk上升沿采样/驱动，避免仿真竞争冒险
  clocking drv_ck @(posedge clk);
    default input #1ns output #1ns;  // 输入信号延迟1ns采样，输出信号延迟1ns驱动
    output ch_data, ch_valid;        // 激励端需要驱动的信号
    input ch_ready, ch_margin;       // 激励端需要采样的信号
  endclocking
endinterface

// 通道发起器模块：负责通过通道接口发送数据，控制数据发送时序
module chnl_initiator(chnl_intf intf);
  string name;         // 发起器名称(用于打印信息区分不同通道)
  int idle_cycles = 1; // 数据间的空闲周期数(默认1个周期)

  // 设置空闲周期的函数：外部可调用此函数配置数据发送间隔
  function automatic void set_idle_cycles(int n);
    idle_cycles = n;
  endfunction

  // 设置发起器名称的函数：用于调试时区分不同通道的打印信息
  function automatic void set_name(string s);
    name = s;
  endfunction

  // 发送数据的任务：通过接口发送一个32位数据
  task automatic chnl_write(input logic[31:0] data);
    @(posedge intf.clk);  // 等待时钟上升沿，同步到时钟边沿
    // 驱动有效信号和数据：使用接口的时钟块保证同步驱动
    intf.drv_ck.ch_valid <= 1;  // 拉高有效信号，指示数据有效
    intf.drv_ck.ch_data <= data; // 驱动数据到总线上
    @(negedge intf.clk);  // 等待时钟下降沿，避免与接收端采样冲突
    wait(intf.ch_ready === 'b1); // 等待接收端就绪(ready=1)，确保数据被接收
    // 打印发送信息：时间、通道名称、发送的数据
    $display("%t channel initiator [%s] sent data %x", $time, name, data);
    // 发送完成后，根据配置插入空闲周期
    repeat(idle_cycles) chnl_idle();  // 重复调用idle任务，插入指定数量的空闲周期
  endtask

  // 空闲任务：使通道进入空闲状态(无数据发送)
  task automatic chnl_idle();
    @(posedge intf.clk);  // 等待时钟上升沿
    // 驱动无效信号和空数据：表示当前周期无有效数据
    intf.drv_ck.ch_valid <= 0;  // 拉低有效信号
    intf.drv_ck.ch_data <= 0;   // 数据总线置0
  endtask
endmodule

// 通道数据生成器：生成特定格式的通道数据，用于测试
module chnl_generator;
  int chnl_arr[$];  // 动态数组：存储已生成的数据(可用于后续校验)
  int num;          // 数据计数器：记录当前通道已生成的数据个数
  int id;           // 通道ID：区分不同通道(0/1/2)

  // 初始化函数：设置通道ID，重置数据计数器
  function automatic void initialize(int n);
    id = n;    // 配置通道ID
    num = 0;   // 计数器清零
  endfunction

  // 生成数据的函数：按固定格式生成数据，并存入数组
  function automatic int get_data();
    int data;
    // 数据格式：高8位固定为0x00C0，中间16位为通道ID左移16位，低16位为计数器
    // 例如：通道0的第0个数据为0x00C0_0000，第1个为0x00C0_0001，以此类推
    data = 'h00C0_0000 + (id<<16) + num;
    num++;                // 计数器自增
    chnl_arr.push_back(data);  // 将生成的数据存入数组
    return data;          // 返回生成的数据
  endfunction
endmodule

// 测试平台顶层模块：实例化DUT、接口、发起器、生成器，实现测试流程
module tb2_ref;
  logic         clk;         // 全局时钟信号
  logic         rstn;        // 全局复位信号(低有效)
  logic [31:0]  mcdt_data;   // DUT输出的合并数据
  logic         mcdt_val;    // DUT输出数据的有效信号
  logic [ 1:0]  mcdt_id;     // DUT输出数据所属的通道ID

  // 实例化DUT(mcdt：多通道数据合并器)
  // 连接各通道接口信号和输出信号
  mcdt dut(
     .clk_i       (clk                )  // 时钟输入
    ,.rstn_i      (rstn               )  // 复位输入
    ,.ch0_data_i  (chnl0_if.ch_data   )  // 通道0数据输入
    ,.ch0_valid_i (chnl0_if.ch_valid  )  // 通道0有效信号输入
    ,.ch0_ready_o (chnl0_if.ch_ready  )  // 通道0就绪信号输出
    ,.ch0_margin_o(chnl0_if.ch_margin )  // 通道0 FIFO余量输出
    ,.ch1_data_i  (chnl1_if.ch_data   )  // 通道1数据输入
    ,.ch1_valid_i (chnl1_if.ch_valid  )  // 通道1有效信号输入
    ,.ch1_ready_o (chnl1_if.ch_ready  )  // 通道1就绪信号输出
    ,.ch1_margin_o(chnl1_if.ch_margin )  // 通道1 FIFO余量输出
    ,.ch2_data_i  (chnl2_if.ch_data   )  // 通道2数据输入
    ,.ch2_valid_i (chnl2_if.ch_valid  )  // 通道2有效信号输入
    ,.ch2_ready_o (chnl2_if.ch_ready  )  // 通道2就绪信号输出
    ,.ch2_margin_o(chnl2_if.ch_margin )  // 通道2 FIFO余量输出
    ,.mcdt_data_o (mcdt_data          )  // 合并后的数据输出
    ,.mcdt_val_o  (mcdt_val           )  // 合并数据的有效信号
    ,.mcdt_id_o   (mcdt_id            )  // 合并数据的通道ID
  );
  
  // 时钟生成：5ns翻转一次，周期10ns(100MHz)
  initial begin 
    clk <= 0;
    forever begin
      #5 clk <= !clk;  // 每5ns时钟取反
    end
  end
  
  // 复位生成：初始10ns后拉低复位，持续10个时钟周期后释放复位
  initial begin 
    #10 rstn <= 0;       // 10ns时复位有效(低电平)
    repeat(10) @(posedge clk);  // 等待10个时钟周期
    rstn <= 1;           // 释放复位(高电平)
  end
  
  // 测试主流程：依次执行基础测试、突发测试、FIFO满测试
  initial begin 
    basic_test();        // 执行基础功能测试
    burst_test();        // 执行突发传输测试
    fifo_full_test();    // 执行FIFO满状态测试
    $display("*****************all of tests have been finished********************");
    $finish();           // 所有测试完成，结束仿真
  end

  // 基础测试任务：验证通道基本发送功能
  // 每个通道以1-3个随机空闲周期发送100个数据
  task automatic basic_test();
    // 初始化各通道数据生成器(设置通道ID)
    chnl0_gen.initialize(0);
    chnl1_gen.initialize(1);
    chnl2_gen.initialize(2);
    // 初始化各通道发起器(设置名称和随机空闲周期)
    chnl0_init.set_name("chnl0_init");
    chnl1_init.set_name("chnl1_init");
    chnl2_init.set_name("chnl2_init");
    chnl0_init.set_idle_cycles($urandom_range(1, 3));  // 通道0空闲周期：1-3
    chnl1_init.set_idle_cycles($urandom_range(1, 3));  // 通道1空闲周期：1-3
    chnl2_init.set_idle_cycles($urandom_range(1, 3));  // 通道2空闲周期：1-3
    $display("basic_test initialized components");
    wait (rstn === 1'b1);  // 等待复位释放
    repeat(5) @(posedge clk);  // 复位释放后再等待5个时钟周期
    $display("basic_test started testing DUT");
    // 并行发送数据：3个通道同时发送100个数据(fork-join实现并行)
    fork
      repeat(100) chnl0_init.chnl_write(chnl0_gen.get_data());  // 通道0发送100个
      repeat(100) chnl1_init.chnl_write(chnl1_gen.get_data());  // 通道1发送100个
      repeat(100) chnl2_init.chnl_write(chnl2_gen.get_data());  // 通道2发送100个
    join
    // 等待所有通道FIFO清空：margin=0x20(32，表示FIFO空)
    fork
      wait(chnl0_init.intf.ch_margin == 'h20);
      wait(chnl1_init.intf.ch_margin == 'h20);
      wait(chnl2_init.intf.ch_margin == 'h20);
    join
    $display("basic_test finished testing DUT");
  endtask

  // 突发测试任务：验证无空闲周期的连续传输能力
  // 每个通道空闲周期为0，连续发送500个数据
  task automatic burst_test();
    // 初始化各组件
    chnl0_gen.initialize(0);
    chnl1_gen.initialize(1);
    chnl2_gen.initialize(2);
    chnl0_init.set_name("chnl0_init");
    chnl1_init.set_name("chnl1_init");
    chnl2_init.set_name("chnl2_init");
    chnl0_init.set_idle_cycles(0);  // 空闲周期设为0(无间隔连续发送)
    chnl1_init.set_idle_cycles(0);
    chnl2_init.set_idle_cycles(0);
    $display("burst_test initialized components");
    wait (rstn === 1'b1);  // 等待复位释放
    repeat(5) @(posedge clk);  // 等待稳定
    $display("burst_test started testing DUT");
    // 并行突发发送：每个通道连续发送500个数据，完成后进入空闲状态
    fork
      begin
        repeat(500) chnl0_init.chnl_write(chnl0_gen.get_data());
        chnl0_init.chnl_idle();  // 发送完成后进入空闲
      end
      begin
        repeat(500) chnl1_init.chnl_write(chnl1_gen.get_data());
        chnl1_init.chnl_idle();
      end
      begin
        repeat(500) chnl2_init.chnl_write(chnl2_gen.get_data());
        chnl2_init.chnl_idle();
      end
    join
    // 等待所有通道FIFO清空
    fork
      wait(chnl0_init.intf.ch_margin == 'h20);
      wait(chnl1_init.intf.ch_margin == 'h20);
      wait(chnl2_init.intf.ch_margin == 'h20);
    join
    $display("burst_test finished testing DUT");
  endtask

  // FIFO满测试任务：验证通道FIFO满状态的处理能力
  // 持续发送数据直到所有通道FIFO满，然后停止并等待FIFO清空
  task automatic fifo_full_test();
    // 初始化各组件(无空闲周期，最大化发送速率)
    chnl0_gen.initialize(0);
    chnl1_gen.initialize(1);
    chnl2_gen.initialize(2);
    chnl0_init.set_name("chnl0_init");
    chnl1_init.set_name("chnl1_init");
    chnl2_init.set_name("chnl2_init");
    chnl0_init.set_idle_cycles(0);
    chnl1_init.set_idle_cycles(0);
    chnl2_init.set_idle_cycles(0);
    $display("fifo_full_test started testing DUT");
    // 并行持续发送数据：使用fork-join_none在后台运行，不阻塞当前流程
    fork: fork_all_run  // 命名fork块，用于后续停止
      forever chnl0_init.chnl_write(chnl0_gen.get_data());  // 通道0无限发送
      forever chnl1_init.chnl_write(chnl1_gen.get_data());  // 通道1无限发送
      forever chnl2_init.chnl_write(chnl2_gen.get_data());  // 通道2无限发送
    join_none
    $display("fifo_full_test: 3 initiators running now");

    // 等待所有通道FIFO满：margin=0(表示FIFO无剩余空间)
    $display("fifo_full_test: waiting 3 channel fifos to be full");
    fork
      wait(chnl0_init.intf.ch_margin == 0);
      wait(chnl1_init.intf.ch_margin == 0);
      wait(chnl2_init.intf.ch_margin == 0);
    join
    $display("fifo_full_test: 3 channel fifos have reached full");

    // 停止所有发送任务：通过disable终止命名fork块
    $display("fifo_full_test: stop 3 initiators running");
    disable fork_all_run;
    // 确保所有发起器进入空闲状态
    $display("fifo_full_test: set and ensure all agents' initiator are idle state");
    fork
      chnl0_init.chnl_idle();
      chnl1_init.chnl_idle();
      chnl2_init.chnl_idle();
    join

    // 等待所有通道FIFO中的数据被完全传输(清空)
    $display("fifo_full_test waiting DUT transfering all of data");
    fork
      wait(chnl0_init.intf.ch_margin == 'h20);
      wait(chnl1_init.intf.ch_margin == 'h20);
      wait(chnl2_init.intf.ch_margin == 'h20);
    join
    $display("fifo_full_test: 3 channel fifos have transferred all data");

    $display("fifo_full_test finished testing DUT");
  endtask
  
  // 实例化3个通道接口，连接全局时钟和复位
  chnl_intf chnl0_if(.*);  // .*表示信号按名称自动连接(clk、rstn)
  chnl_intf chnl1_if(.*);
  chnl_intf chnl2_if(.*);

  // 实例化3个通道发起器，分别连接到对应的通道接口
  chnl_initiator chnl0_init(chnl0_if);
  chnl_initiator chnl1_init(chnl1_if);
  chnl_initiator chnl2_init(chnl2_if);

  // 实例化3个通道数据生成器，分别用于3个通道
  chnl_generator chnl0_gen();
  chnl_generator chnl1_gen();
  chnl_generator chnl2_gen();

endmodule