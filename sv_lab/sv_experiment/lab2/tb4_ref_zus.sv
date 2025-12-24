// 时间单位定义：仿真时间单位为1ns，时间精度为1ps，用于控制仿真时序精度
`timescale 1ns/1ps

// ****************************** 接口定义 ******************************
// 通道接口：封装DUT与验证环境交互的信号，包含时钟、复位及数据传输信号
// 输入参数：clk（时钟）、rstn（低电平复位）
interface chnl_intf(input clk, input rstn);
  // 接口信号定义
  logic [31:0] ch_data;    // 32位数据信号：传输有效数据
  logic        ch_valid;   // 数据有效信号：高电平表示ch_data上数据有效
  logic        ch_ready;   // 接收准备信号：高电平表示接收端（DUT）可接收数据
  logic [ 5:0] ch_margin;  // FIFO余量信号：表示DUT内部对应通道FIFO的剩余空间（6位对应最大深度32）

  // 驱动时钟块：定义驱动端（验证环境）与接口信号的交互时序
  // 采样/驱动时钟沿：上升沿clk
  clocking drv_ck @(posedge clk);
    // 默认时序约束：输入信号（从接口读）延迟1ns采样，输出信号（向接口写）延迟1ns驱动
    default input #1ns output #1ns;
    output ch_data, ch_valid;  // 驱动端需要输出的信号：数据和有效信号
    input ch_ready, ch_margin; // 驱动端需要输入的信号：准备信号和FIFO余量
  endclocking
endinterface

// ****************************** 验证包定义 ******************************
// 通道验证包：封装所有验证相关的类（事务、生成器、发起者、代理、测试用例）
package chnl_pkg;
  // ****************************** 事务类 ******************************
  // 通道事务类：封装一次数据传输的元信息，作为验证环境中数据传输的载体
  class chnl_trans;
    int data;  // 传输的32位数据（对应接口ch_data）
    int id;    // 通道ID（0/1/2，标识数据所属通道）
    int num;   // 事务序号（标识该通道下的第几个传输事务）
  endclass: chnl_trans
  
  // ****************************** 发起者类 ******************************
  // 通道发起者类：作为验证环境的驱动端，负责将事务数据驱动到接口信号
  class chnl_initiator;
    local string name;          // 发起者名称（用于日志打印，区分不同通道）
    local int idle_cycles;      // 数据间空闲周期数（控制两次数据传输的间隔）
    local virtual chnl_intf intf; // 虚拟接口句柄：连接发起者与物理接口

    // 构造函数：初始化发起者名称和默认空闲周期（1个时钟周期）
    function new(string name = "chnl_initiator");
      this.name = name;
      this.idle_cycles = 1;
    endfunction

    // 设置空闲周期：外部可调用该函数修改数据间的空闲周期数
    function void set_idle_cycles(int n);
      this.idle_cycles = n;
    endfunction

    // 设置发起者名称：修改日志打印时的标识名称
    function void set_name(string s);
      this.name = s;
    endfunction

    // 绑定接口：将物理接口句柄传递给发起者的虚拟接口，建立驱动通路
    // 若接口句柄为空，打印错误信息（防止未实例化接口导致驱动失败）
    function void set_interface(virtual chnl_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction

    // 数据写入任务：将事务数据通过接口驱动到DUT
    task chnl_write(input chnl_trans t);
      @(posedge intf.clk);  // 等待时钟上升沿：确保时序对齐
      // USER TODO 1.1：通过时钟块drv_ck驱动信号（遵循时钟块时序约束）
      intf.drv_ck.ch_valid <= 1;  // 置高有效信号，标识数据有效
      intf.drv_ck.ch_data <= t.data; // 将事务数据驱动到接口数据信号
      
      @(negedge intf.clk);  // 等待时钟下降沿：避免竞争冒险，稳定采样
      wait(intf.ch_ready === 'b1); // 等待DUT准备就绪：确保DUT可接收数据
      $display("%t channel initiator [%s] sent data %x", $time, name, t.data); // 打印传输日志

      // USER TODO 1.2：根据设置的空闲周期，在两次数据间插入空闲
      repeat(this.idle_cycles) chnl_idle(); // 重复调用空闲任务，插入指定数量的空闲周期
    endtask
    
    // 空闲任务：驱动接口进入空闲状态（无数据传输）
    task chnl_idle();
      @(posedge intf.clk);  // 等待时钟上升沿：时序对齐
      // USER TODO 1.1：通过时钟块drv_ck驱动空闲状态信号
      intf.drv_ck.ch_valid <= 0;  // 拉低有效信号，标识无有效数据
      intf.drv_ck.ch_data <= 0;   // 数据信号置0（空闲状态下无意义，仅规范驱动）
    endtask
  endclass: chnl_initiator
  
  // ****************************** 生成器类 ******************************
  // 通道事务生成器：负责生成符合协议的事务数据，为发起者提供数据来源
  class chnl_generator;
    chnl_trans trans[$];  // 事务队列：存储已生成的事务（用于后续比对或回溯）
    int num;              // 事务计数：记录当前生成的事务序号
    int id;               // 通道ID：标识该生成器所属的通道（与发起者通道对应）

    // 构造函数：初始化生成器所属的通道ID，重置事务计数
    function new(int n);
      this.id = n;
      this.num = 0;
    endfunction

    // 获取事务：生成一个新的事务并返回，同时存入事务队列
    function chnl_trans get_trans();
      chnl_trans t = new();  // 实例化新事务
      // 构造事务数据：固定前缀（0x00C00000） + 通道ID偏移（左移16位） + 事务序号
      t.data = 'h00C0_0000 + (this.id<<16) + this.num;
      t.id = this.id;        // 赋值通道ID
      t.num = this.num;      // 赋值事务序号
      this.num++;            // 事务计数自增（下一个事务序号+1）
      this.trans.push_back(t); // 将生成的事务存入队列
      return t;              // 返回新生成的事务
    endfunction
  endclass: chnl_generator

  // ****************************** 代理类 ******************************
  // 通道代理类：封装生成器和发起者，对外提供统一的通道控制接口
  // 作用：简化测试用例的调用，无需单独操作生成器和发起者
  class chnl_agent;
    chnl_generator gen;    // 事务生成器实例：负责生成数据
    chnl_initiator init;   // 发起者实例：负责驱动数据
    local int ntrans;      // 传输事务总数：该代理需要生成并驱动的事务数量
    virtual chnl_intf vif; // 虚拟接口句柄：传递给发起者绑定接口

    // 构造函数：初始化生成器、发起者，设置默认传输事务数（1个）
    // 参数：name（发起者名称）、id（通道ID）、ntrans（默认传输数）
    function new(string name = "chnl_agent", int id = 0, int ntrans = 1);
      this.gen = new(id);       // 实例化生成器，绑定通道ID
      this.init = new(name);    // 实例化发起者，设置名称
      this.ntrans = ntrans;     // 初始化传输事务总数
    endfunction

    // 设置传输事务数：外部测试用例可修改代理需要传输的事务总数
    function void set_ntrans(int n);
      this.ntrans = n;
    endfunction

    // 绑定接口：将物理接口传递给代理，同时转发给发起者绑定
    function void set_interface(virtual chnl_intf vif);
      this.vif = vif;
      init.set_interface(vif);  // 调用发起者的接口绑定函数
    endfunction

    // 运行任务：执行数据传输流程（生成事务→驱动事务）
    task run();
      // 重复ntrans次：生成事务并调用发起者驱动
      repeat(this.ntrans) this.init.chnl_write(this.gen.get_trans());
      this.init.chnl_idle(); // 所有数据传输完成后，驱动接口进入空闲状态
    endtask
  endclass: chnl_agent

  // ****************************** 根测试类 ******************************
  // 根测试类：封装3个通道的代理，提供基础测试流程，作为所有测试用例的父类
  class chnl_root_test;
    chnl_agent agent[3];    // 3个通道的代理数组（对应DUT的3个输入通道）
    protected string name;  // 测试用例名称（用于日志打印）

    // 构造函数：实例化3个通道的代理，初始化测试名称和默认传输事务数
    // 参数：ntrans（每个通道默认传输数）、name（测试用例名称）
    function new(int ntrans = 100, string name = "chnl_root_test");
      foreach(agent[i]) begin
        // 实例化每个通道的代理：名称含通道号（chnl_agent0/1/2）、通道ID=i、传输数=ntrans
        this.agent[i] = new($sformatf("chnl_agent%0d",i), i, ntrans);
      end
      this.name = name;  // 初始化测试用例名称
      $display("%s instantiate objects", this.name); // 打印对象实例化日志
    endfunction

    // 基础运行任务：定义通用测试流程
    task run();
      $display("%s started testing DUT", this.name); // 打印测试开始日志

      // 并行执行3个通道的代理：3个通道同时开始数据传输
      fork
        agent[0].run();
        agent[1].run();
        agent[2].run();
      join  // 等待所有通道的事务传输完成

      // 等待DUT内部FIFO数据清空：FIFO余量ch_margin=0x20（32）表示FIFO空
      $display("%s waiting DUT transfering all of data", this.name);
      fork
        wait(agent[0].vif.ch_margin == 'h20); // 等待通道0 FIFO空
        wait(agent[1].vif.ch_margin == 'h20); // 等待通道1 FIFO空
        wait(agent[2].vif.ch_margin == 'h20); // 等待通道2 FIFO空
      join  // 等待所有通道FIFO数据处理完成

      $display("%s: 3 channel fifos have transferred all data", this.name);
      $display("%s finished testing DUT", this.name); // 打印测试完成日志
    endtask

    // 绑定接口：将3个通道的物理接口分别传递给对应通道的代理
    function void set_interface(virtual chnl_intf ch0_vif, virtual chnl_intf ch1_vif, virtual chnl_intf ch2_vif);
      agent[0].set_interface(ch0_vif);
      agent[1].set_interface(ch1_vif);
      agent[2].set_interface(ch2_vif);
    endfunction
  endclass

  // ****************************** 基础测试类 ******************************
  // 基础测试用例：继承根测试类，实现"带空闲周期的基础传输"场景
  // 特性：每个通道传输200个数据，数据间空闲周期随机1~3个时钟
  class chnl_basic_test extends chnl_root_test;
    // 构造函数：调用父类构造（设置传输数200、测试名称），配置空闲周期
    function new(int ntrans = 200, string name = "chnl_basic_test");
      super.new(ntrans, name); // 调用父类构造，初始化代理和传输数
      foreach(agent[i]) begin
        // 为每个通道的发起者设置随机空闲周期（1~3）
        this.agent[i].init.set_idle_cycles($urandom_range(1, 3));
      end
      $display("%s configured objects", this.name); // 打印配置完成日志
    endfunction
  endclass: chnl_basic_test

  // ****************************** 突发测试类 ******************************
  // USER TODO 4.2：突发传输测试用例（继承根测试类）
  // 特性：每个通道传输500个数据，数据间无空闲周期（突发传输）
  class chnl_burst_test extends chnl_root_test;
    // 构造函数：调用父类构造（设置传输数500、测试名称），配置空闲周期为0
    function new(int ntrans = 500, string name = "chnl_burst_test");
      super.new(ntrans, name); // 调用父类构造，初始化代理和传输数
      foreach(agent[i]) begin
        this.agent[i].init.set_idle_cycles(0); // 空闲周期设为0，实现突发传输
      end
      $display("%s configured objects", this.name); // 打印配置完成日志
    endfunction
  endclass: chnl_burst_test

  // ****************************** FIFO满测试类 ******************************
  // USER TODO 4.2：FIFO满触发测试用例（继承根测试类）
  // 特性：不固定传输数，当3个通道FIFO均满（margin=0）时立即停止传输，无需等所有数据发完
  class chnl_fifo_full_test extends chnl_root_test;
    // 构造函数：调用父类构造（设置超大传输数1e6，确保FIFO先满），配置突发传输
    function new(int ntrans = 1_000_000, string name = "chnl_fifo_full_test");
      super.new(ntrans, name); // 传输数设为1e6（远超FIFO容量，确保能触发满状态）
      foreach(agent[i]) begin
        this.agent[i].init.set_idle_cycles(0); // 突发传输，快速填满FIFO
      end
      $display("%s configured objects", this.name); // 打印配置完成日志
    endfunction

    // 重写运行任务：自定义"FIFO满触发停止"的测试流程
    task run();
      $display("%s started testing DUT", this.name); // 打印测试开始日志

      // 并行启动3个通道代理（非阻塞join_none，允许后续等待FIFO满）
      fork: fork_all_run  // 命名fork块，用于后续关闭
        agent[0].run();
        agent[1].run();
        agent[2].run();
      join_none  // 不等待代理运行完成，继续执行后续代码
      $display("%s: 3 agents running now", this.name);

      // 等待3个通道FIFO均满（ch_margin=0表示FIFO无剩余空间）
      $display("%s: waiting 3 channel fifos to be full", this.name);
      fork
        wait(agent[0].vif.ch_margin == 0); // 等待通道0 FIFO满
        wait(agent[1].vif.ch_margin == 0); // 等待通道1 FIFO满
        wait(agent[2].vif.ch_margin == 0); // 等待通道2 FIFO满
      join  // 所有通道FIFO均满后，继续执行

      $display("%s: 3 channel fifos have reached full", this.name);

      // 关闭代理的传输任务：停止继续发送数据
      $display("%s: stop 3 agents running", this.name);
      disable fork_all_run; // 关闭命名fork块，终止3个代理的run任务

      // 确保所有通道进入空闲状态：避免残留有效信号
      $display("%s: set and ensure all agents' initiator are idle state", this.name);
      fork
        agent[0].init.chnl_idle();
        agent[1].init.chnl_idle();
        agent[2].init.chnl_idle();
      join

      // 等待DUT处理完FIFO中剩余数据（FIFO空）
      $display("%s waiting DUT transfering all of data", this.name);
      fork
        wait(agent[0].vif.ch_margin == 'h20);
        wait(agent[1].vif.ch_margin == 'h20);
        wait(agent[2].vif.ch_margin == 'h20);
      join

      $display("%s: 3 channel fifos have transferred all data", this.name);
      $display("%s finished testing DUT", this.name); // 打印测试完成日志
    endtask
  endclass: chnl_fifo_full_test

endpackage: chnl_pkg


// ****************************** 测试平台模块 ******************************
// 测试平台模块：实例化DUT、接口、测试用例，生成时钟复位，执行测试流程
module tb4_ref;
  // 测试平台内部信号
  logic         clk;         // 时钟信号（提供给DUT和接口）
  logic         rstn;        // 低电平复位信号（提供给DUT和接口）
  logic [31:0]  mcdt_data;   // DUT输出数据（整合后的32位数据）
  logic         mcdt_val;    // DUT输出有效信号（标识输出数据有效）
  logic [ 1:0]  mcdt_id;     // DUT输出通道ID（标识输出数据所属原始通道）
  
  // 实例化DUT（多通道数据整合器mcdt）
  // 端口连接：时钟/复位 → 3个通道的接口信号 → 输出信号
  mcdt dut(
     .clk_i       (clk                )
    ,.rstn_i      (rstn               )
    ,.ch0_data_i  (chnl0_if.ch_data   )
    ,.ch0_valid_i (chnl0_if.ch_valid  )
    ,.ch0_ready_o (chnl0_if.ch_ready  )
    ,.ch0_margin_o(chnl0_if.ch_margin )
    ,.ch1_data_i  (chnl1_if.ch_data   )
    ,.ch1_valid_i (chnl1_if.ch_valid  )
    ,.ch1_ready_o (chnl1_if.ch_ready  )
    ,.ch1_margin_o(chnl1_if.ch_margin )
    ,.ch2_data_i  (chnl2_if.ch_data   )
    ,.ch2_valid_i (chnl2_if.ch_valid  )
    ,.ch2_ready_o (chnl2_if.ch_ready  )
    ,.ch2_margin_o(chnl2_if.ch_margin )
    ,.mcdt_data_o (mcdt_data          )
    ,.mcdt_val_o  (mcdt_val           )
    ,.mcdt_id_o   (mcdt_id            )
  );
  
  // ****************************** 时钟生成 ******************************
  // 生成50MHz时钟（周期10ns：5ns高电平，5ns低电平）
  initial begin 
    clk <= 0;
    forever begin
      #5 clk <= !clk; // 每5ns翻转一次时钟
    end
  end
  
  // ****************************** 复位生成 ******************************
  // 生成复位信号：初始10ns后拉低复位（有效），持续10个时钟周期后释放（拉高）
  initial begin 
    #10 rstn <= 0;          // 10ns时复位有效（低电平）
    repeat(10) @(posedge clk); // 等待10个时钟上升沿（约100ns）
    rstn <= 1;              // 释放复位（高电平）
  end

  // USER TODO 4.1：导入验证包中的所有类（使测试平台可使用包内定义的类）
  import chnl_pkg::*;

  // 实例化3个通道的接口（对应DUT的3个输入通道）
  // 时钟和复位信号通过位置关联（interface定义的input参数）
  chnl_intf chnl0_if(.*);
  chnl_intf chnl1_if(.*);
  chnl_intf chnl2_if(.*);

  // 声明3个测试用例实例
  chnl_basic_test basic_test;        // 基础测试用例
  chnl_burst_test burst_test;        // 突发传输测试用例
  chnl_fifo_full_test fifo_full_test;// FIFO满触发测试用例

  // ****************************** 测试执行流程 ******************************
  initial begin 
    // 实例化3个测试用例
    basic_test = new();
    burst_test = new();
    fifo_full_test = new();

    // USER TODO 4.4：为每个测试用例绑定接口（传递3个通道的物理接口）
    basic_test.set_interface(chnl0_if, chnl1_if, chnl2_if);
    burst_test.set_interface(chnl0_if, chnl1_if, chnl2_if);
    fifo_full_test.set_interface(chnl0_if, chnl1_if, chnl2_if);

    // USER TODO 4.5：按顺序执行测试用例（基础→突发→FIFO满）
    basic_test.run(); 
    burst_test.run();
    fifo_full_test.run();

    $display("*****************all of tests have been finished********************");
    $finish(); // 所有测试完成，终止仿真
  end

endmodule