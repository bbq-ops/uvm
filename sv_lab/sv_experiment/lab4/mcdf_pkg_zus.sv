// 包含外部参数定义文件，用于获取宏定义（如`WRITE、`READ、`SLV0_RW_ADDR等）
`include "param_def.v"

// 定义MCDF（Multi-Channel Data Formatter，多通道数据格式化器）的验证包
// 包含参考模型、检查器、环境、测试用例等验证组件，用于验证MCDF的功能正确性
package mcdf_pkg;

  // 导入其他相关包：分别包含通道、寄存器、仲裁器、格式化器的验证组件及报告功能
  import chnl_pkg::*;      // 通道相关组件（如agent、generator等）
  import reg_pkg::*;       // 寄存器相关组件
  import arb_pkg::*;       // 仲裁器相关组件
  import fmt_pkg::*;       // 格式化器相关组件
  import rpt_pkg::*;       // 报告功能组件（之前定义的日志、统计功能）

  // 定义MCDF寄存器结构体：模拟MCDF内部寄存器的状态
  // packed修饰表示结构体按位打包，可直接作为整数操作
  typedef struct packed {
    bit[2:0] len;       // 数据长度配置（3位，用于控制输出数据包长度）
    bit[1:0] prio;      // 优先级配置（2位，控制通道仲裁优先级）
    bit en;             // 使能位（1位，1表示通道使能，0表示关闭）
    bit[7:0] avail;     // 可用数据量（8位，指示通道内可用数据的数量）
  } mcdf_reg_t;

  // 定义MCDF寄存器字段枚举：用于指定访问寄存器的具体字段
  typedef enum {
    RW_LEN,    // 读写字段：长度配置（对应mcdf_reg_t的len）
    RW_PRIO,   // 读写字段：优先级配置（对应mcdf_reg_t的prio）
    RW_EN,     // 读写字段：使能配置（对应mcdf_reg_t的en）
    RD_AVAIL   // 只读字段：可用数据量（对应mcdf_reg_t的avail）
  } mcdf_field_t;

  // MCDF参考模型类：模拟DUT（Device Under Test，被测设计）的行为逻辑
  // 接收输入激励，生成预期输出，用于与DUT的实际输出对比
  class mcdf_refmod;
    local virtual mcdf_intf intf;  // 虚拟接口：连接参考模型与DUT的物理接口，用于获取复位等信号
    local string name;             // 参考模型名称，用于日志输出
    mcdf_reg_t regs[3];            // 寄存器数组：模拟3个通道的寄存器状态（索引0/1/2对应3个通道）
    mailbox #(reg_trans) reg_mb;   // 寄存器transaction邮箱：接收来自寄存器监测器的寄存器操作信息
    mailbox #(mon_data_t) in_mbs[3];// 输入数据邮箱数组：接收3个通道的输入数据（来自通道监测器）
    mailbox #(fmt_trans) out_mbs[3];// 输出数据邮箱数组：发送参考模型生成的预期输出数据（给检查器）

    // 构造函数：初始化参考模型名称，创建输出邮箱
    function new(string name="mcdf_refmod");
      this.name = name;
      // 为每个通道的输出邮箱分配内存
      foreach(this.out_mbs[i]) this.out_mbs[i] = new();
    endfunction

    // 主运行任务：启动参考模型的所有核心功能
    task run();
      fork
        do_reset();          // 处理复位逻辑
        this.do_reg_update();// 处理寄存器更新
        do_packet(0);        // 处理通道0的数据包
        do_packet(1);        // 处理通道1的数据包
        do_packet(2);        // 处理通道2的数据包
      join
    endtask

    // 寄存器更新任务：从寄存器邮箱获取操作信息，更新内部寄存器状态
    task do_reg_update();
      reg_trans t;  // 寄存器transaction：存储寄存器操作（地址、命令、数据）
      forever begin
        this.reg_mb.get(t);  // 从邮箱获取寄存器操作
        // 若操作地址的高4位为0且为写命令（匹配通道配置寄存器的写操作）
        if(t.addr[7:4] == 0 && t.cmd == `WRITE) begin
          // 根据地址的[3:2]位确定通道号（0/1/2），更新对应寄存器的en、prio、len
          this.regs[t.addr[3:2]].en = t.data[0];       // 数据bit0对应en
          this.regs[t.addr[3:2]].prio = t.data[2:1];   // 数据bit1-2对应prio
          this.regs[t.addr[3:2]].len = t.data[5:3];    // 数据bit3-5对应len
        end
        // 若操作地址的高4位为1且为读命令（匹配可用数据量寄存器的读操作）
        else if(t.addr[7:4] == 1 && t.cmd == `READ) begin
          // 记录读取到的可用数据量（实际DUT返回的值）
          this.regs[t.addr[3:2]].avail = t.data[7:0];
        end
      end
    endtask

    // 数据包处理任务：根据寄存器配置，将输入数据处理为预期的格式化输出
    // 参数id：通道号（0/1/2）
    task do_packet(int id);
      fmt_trans ot;       // 预期输出的格式化transaction
      mon_data_t it;      // 输入的监测数据
	  bit[2:0] len;       // 从寄存器获取的长度配置

      forever begin
        this.in_mbs[id].peek(it);  // 查看（不取出）通道id的输入数据，等待数据到来
        ot = new();                // 创建新的输出transaction
        len = this.get_field_value(id, RW_LEN);  // 获取该通道的长度配置

        // 根据长度配置计算输出数据包长度：若len>3则为32，否则为4*(2^len)（即4<<len）
        ot.length = len > 3 ? 32 : 4 << len;
        ot.data = new[ot.length];  // 为输出数据数组分配内存
        ot.ch_id = id;             // 记录通道号

        // 从输入邮箱取出指定长度的数据，填入输出transaction
        foreach(ot.data[m]) begin
          this.in_mbs[id].get(it);  // 取出输入数据
          ot.data[m] = it.data;     // 复制数据到输出
        end

        this.out_mbs[id].put(ot);  // 将预期输出放入对应通道的输出邮箱（供检查器获取）
      end
    endtask

    // 获取寄存器字段值的函数：根据通道号和字段类型返回对应值
    function int get_field_value(int id, mcdf_field_t f);
      case(f)
        RW_LEN: return regs[id].len;    // 返回长度配置
        RW_PRIO: return regs[id].prio;  // 返回优先级配置
        RW_EN: return regs[id].en;      // 返回使能状态
        RD_AVAIL: return regs[id].avail;// 返回可用数据量
      endcase
    endfunction 

    // 复位处理任务：在复位信号有效时（rstn为低）初始化寄存器状态
    task do_reset();
      forever begin
        @(negedge intf.rstn);  // 等待复位信号下降沿（复位开始）
        // 初始化所有通道的寄存器默认值
        foreach(regs[i]) begin
          regs[i].len = 'h0;    // 长度默认0
          regs[i].prio = 'h3;   // 优先级默认最高（3）
          regs[i].en = 'h1;     // 默认使能
          regs[i].avail = 'h20; // 可用数据量默认32（0x20）
        end
      end
    endtask

    // 设置虚拟接口的函数：将外部接口句柄传递给参考模型
    function void set_interface(virtual mcdf_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;  // 保存接口句柄
    endfunction
    
  endclass

  // MCDF检查器类：负责比较DUT的实际输出与参考模型的预期输出，验证功能正确性
  class mcdf_checker;
    local string name;               // 检查器名称
    local int err_count;             // 错误计数器：记录比较失败的次数
    local int total_count;           // 总比较次数：记录所有比较的总次数
    local int chnl_count[3];         // 通道比较计数器：记录每个通道的比较次数
    local virtual mcdf_intf intf;    // 虚拟接口：连接检查器与DUT
    local mcdf_refmod refmod;        // 参考模型实例：用于生成预期输出
    mailbox #(mon_data_t) chnl_mbs[3];// 通道数据邮箱：接收来自通道监测器的实际输入数据（传给参考模型）
    mailbox #(fmt_trans) fmt_mb;     // 格式化输出邮箱：接收来自格式化器监测器的DUT实际输出
    mailbox #(reg_trans) reg_mb;     // 寄存器邮箱：接收来自寄存器监测器的实际寄存器操作（传给参考模型）
    mailbox #(fmt_trans) exp_mbs[3]; // 预期输出邮箱：从参考模型获取预期输出

    // 构造函数：初始化检查器名称，创建邮箱，实例化参考模型并建立连接
    function new(string name="mcdf_checker");
      this.name = name;
      // 创建通道数据邮箱和格式化输出邮箱
      foreach(this.chnl_mbs[i]) this.chnl_mbs[i] = new();
      this.fmt_mb = new();
      this.reg_mb = new();
      // 实例化参考模型，并将检查器的邮箱与参考模型的邮箱连接（数据流向：检查器→参考模型）
      this.refmod = new();
      foreach(this.refmod.in_mbs[i]) begin
        this.refmod.in_mbs[i] = this.chnl_mbs[i];  // 通道输入数据传给参考模型
        this.exp_mbs[i] = this.refmod.out_mbs[i];   // 从参考模型获取预期输出
      end
      this.refmod.reg_mb = this.reg_mb;  // 寄存器操作传给参考模型

      // 初始化计数器
      this.err_count = 0;
      this.total_count = 0;
      foreach(this.chnl_count[i]) this.chnl_count[i] = 0;
    endfunction

    // 设置虚拟接口的函数：同时为检查器和内部参考模型设置接口
    function void set_interface(virtual mcdf_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else begin
        this.intf = intf;              // 保存检查器接口
        this.refmod.set_interface(intf); // 为参考模型设置接口
      end
    endfunction

    // 主运行任务：启动比较任务和参考模型
    task run();
      fork
        this.do_compare();  // 执行实际与预期输出的比较
        this.refmod.run();  // 启动参考模型
      join
    endtask

    // 比较任务：从邮箱获取DUT实际输出和参考模型预期输出，进行比较并记录结果
    task do_compare();
      fmt_trans expt, mont;  // expt：预期输出；mont：实际监测输出
      bit cmp;               // 比较结果（1：一致；0：不一致）

      forever begin
        this.fmt_mb.get(mont);       // 获取DUT的实际输出
        this.exp_mbs[mont.ch_id].get(expt);  // 获取对应通道的预期输出
        cmp = mont.compare(expt);    // 调用transaction的比较方法（假设已实现）

        // 更新计数器
        this.total_count++;
        this.chnl_count[mont.ch_id]++;

        // 比较失败：记录错误并输出日志
        if(cmp == 0) begin
          this.err_count++;
          rpt_pkg::rpt_msg("[CMPFAIL]", 
            $sformatf("%0t %0dth times comparing but failed! MCDF monitored output packet is different with reference model output", $time, this.total_count),
            rpt_pkg::ERROR,
            rpt_pkg::TOP,
            rpt_pkg::LOG);
        end
        // 比较成功：输出成功日志
        else begin
          rpt_pkg::rpt_msg("[CMPSUCD]",
            $sformatf("%0t %0dth times comparing and succeeded! MCDF monitored output packet is the same with reference model output", $time, this.total_count),
            rpt_pkg::INFO,
            rpt_pkg::HIGH);
        end
      end
    endtask

    // 报告生成函数：汇总比较结果、邮箱状态等信息，输出报告
    function void do_report();
      string s;  // 报告字符串

      // 构建报告内容
      s = "\n---------------------------------------------------------------\n";
      s = {s, "CHECKER SUMMARY \n"}; 
      s = {s, $sformatf("total comparison count: %0d \n", this.total_count)}; 
      foreach(this.chnl_count[i]) s = {s, $sformatf(" channel[%0d] comparison count: %0d \n", i, this.chnl_count[i])};
      s = {s, $sformatf("total error count: %0d \n", this.err_count)}; 
      // 检查邮箱是否为空（非空表示有未处理的数据，可能存在问题）
      foreach(this.chnl_mbs[i]) begin
        if(this.chnl_mbs[i].num() != 0)
          s = {s, $sformatf("WARNING:: chnl_mbs[%0d] is not empty! size = %0d \n", i, this.chnl_mbs[i].num())}; 
      end
      if(this.fmt_mb.num() != 0)
          s = {s, $sformatf("WARNING:: fmt_mb is not empty! size = %0d \n", this.fmt_mb.num())}; 
      s = {s, "---------------------------------------------------------------\n"};
      // 调用报告函数输出汇总信息
      rpt_pkg::rpt_msg($sformatf("[%s]",this.name), s, rpt_pkg::INFO, rpt_pkg::TOP);
    endfunction
  endclass


  // MCDF环境类：集成所有验证组件（代理、检查器），负责组件的实例化、连接和协同工作
  class mcdf_env;
    chnl_agent chnl_agts[3];  // 通道代理数组：包含3个通道的驱动、监测器等
    reg_agent reg_agt;        // 寄存器代理：包含寄存器的驱动、监测器等
    fmt_agent fmt_agt;        // 格式化器代理：包含格式化器的驱动、监测器等
    mcdf_checker chker;       // 检查器实例
    protected string name;    // 环境名称

    // 构造函数：实例化所有组件，并建立组件间的连接（通过邮箱）
    function new(string name = "mcdf_env");
      this.name = name;
      this.chker = new();  // 实例化检查器

      // 实例化3个通道代理，并将代理的监测器邮箱连接到检查器的通道数据邮箱
      foreach(chnl_agts[i]) begin
        this.chnl_agts[i] = new($sformatf("chnl_agts[%0d]",i));
        this.chnl_agts[i].monitor.mon_mb = this.chker.chnl_mbs[i];
      end

      // 实例化寄存器代理，将其监测器邮箱连接到检查器的寄存器邮箱
      this.reg_agt = new("reg_agt");
      this.reg_agt.monitor.mon_mb = this.chker.reg_mb;

      // 实例化格式化器代理，将其监测器邮箱连接到检查器的格式化输出邮箱
      this.fmt_agt = new("fmt_agt");
      this.fmt_agt.monitor.mon_mb = this.chker.fmt_mb;

      $display("%s instantiated and connected objects", this.name);
    endfunction

    // 主运行任务：启动环境中所有组件的运行
    virtual task run();
      $display($sformatf("*****************%s started********************", this.name));
      this.do_config();  // 配置环境（预留接口，由子类实现）
      fork
        this.chnl_agts[0].run();  // 启动通道0代理
        this.chnl_agts[1].run();  // 启动通道1代理
        this.chnl_agts[2].run();  // 启动通道2代理
        this.reg_agt.run();       // 启动寄存器代理
        this.fmt_agt.run();       // 启动格式化器代理
        this.chker.run();         // 启动检查器
      join
    endtask

    // 环境配置虚函数：预留接口，可由子类重写以实现特定配置
    virtual function void do_config();
    endfunction

    // 报告生成函数：调用检查器的报告函数
    virtual function void do_report();
      this.chker.do_report();
    endfunction

  endclass

  // MCDF基础测试类：所有具体测试用例的父类，提供通用测试框架
  class mcdf_base_test;
    chnl_generator chnl_gens[3];  // 通道生成器数组：生成3个通道的输入激励
    reg_generator reg_gen;        // 寄存器生成器：生成寄存器操作激励
    fmt_generator fmt_gen;        // 格式化器生成器：生成格式化器配置激励
    mcdf_env env;                 // 环境实例：包含所有验证组件
    protected string name;        // 测试名称

    // 构造函数：实例化生成器和环境，建立生成器与代理的连接，初始化日志
    function new(string name = "mcdf_base_test");
      this.name = name;
      this.env = new("env");  // 实例化环境

      // 实例化3个通道生成器，并将生成器的请求/响应邮箱连接到通道代理的驱动
      foreach(this.chnl_gens[i]) begin
        this.chnl_gens[i] = new();
        this.env.chnl_agts[i].driver.req_mb = this.chnl_gens[i].req_mb;  // 激励请求
        this.env.chnl_agts[i].driver.rsp_mb = this.chnl_gens[i].rsp_mb;  // 响应反馈
      end

      // 实例化寄存器生成器，连接到寄存器代理的驱动
      this.reg_gen = new();
      this.env.reg_agt.driver.req_mb = this.reg_gen.req_mb;
      this.env.reg_agt.driver.rsp_mb = this.reg_gen.rsp_mb;

      // 实例化格式化器生成器，连接到格式化器代理的驱动
      this.fmt_gen = new();
      this.env.fmt_agt.driver.req_mb = this.fmt_gen.req_mb;
      this.env.fmt_agt.driver.rsp_mb = this.fmt_gen.rsp_mb;

      // 设置日志文件名（以测试名命名），并清空日志
      rpt_pkg::logname = {this.name, "_check.log"};
      rpt_pkg::clean_log();
      $display("%s instantiated and connected objects", this.name);
    endfunction

    // 主运行任务：启动环境，执行测试流程，生成报告并结束仿真
    virtual task run();
      fork
        env.run();  // 异步启动环境（使用join_none，不阻塞后续流程）
      join_none

      // 输出测试开始日志
      rpt_pkg::rpt_msg("[TEST]",
        $sformatf("=====================%s AT TIME %0t STARTED=====================", this.name, $time),
        rpt_pkg::INFO,
        rpt_pkg::HIGH);

      this.do_reg();        // 执行寄存器配置
      this.do_formatter();  // 执行格式化器配置
      this.do_data();       // 执行数据传输

      // 输出测试结束日志
      rpt_pkg::rpt_msg("[TEST]",
        $sformatf("=====================%s AT TIME %0t FINISHED=====================", this.name, $time),
        rpt_pkg::INFO,
        rpt_pkg::HIGH);

      this.do_report();  // 生成测试报告
      $finish();         // 结束仿真
    endtask

    // 寄存器配置虚任务：预留接口，由子类实现具体的寄存器配置
    virtual task do_reg();
    endtask

    // 格式化器配置虚任务：预留接口，由子类实现具体的格式化器配置
    virtual task do_formatter();
    endtask

    // 数据传输虚任务：预留接口，由子类实现具体的输入数据发送
    virtual task do_data();
    endtask

    // 报告生成虚函数：调用环境的报告函数和全局报告函数
    virtual function void do_report();
      this.env.do_report();  // 环境报告（包含检查器结果）
      rpt_pkg::do_report();  // 全局统计报告（消息计数）
    endfunction

    // 设置接口的函数：将外部所有接口传递给环境中的组件
    virtual function void set_interface(
      virtual chnl_intf ch0_vif,  // 通道0接口
      virtual chnl_intf ch1_vif,  // 通道1接口
      virtual chnl_intf ch2_vif,  // 通道2接口
      virtual reg_intf reg_vif,   // 寄存器接口
      virtual fmt_intf fmt_vif,   // 格式化器接口
      virtual mcdf_intf mcdf_vif  // MCDF主接口
    );
      this.env.chnl_agts[0].set_interface(ch0_vif);
      this.env.chnl_agts[1].set_interface(ch1_vif);
      this.env.chnl_agts[2].set_interface(ch2_vif);
      this.env.reg_agt.set_interface(reg_vif);
      this.env.fmt_agt.set_interface(fmt_vif);
      this.env.chker.set_interface(mcdf_vif);
    endfunction

    // 数值比较函数：比较两个值，输出比较结果日志，返回比较状态
    virtual function bit diff_value(int val1, int val2, string id = "value_compare");
      if(val1 != val2) begin  // 比较失败
        rpt_pkg::rpt_msg("[CMPERR]", 
          $sformatf("ERROR! %s val1 %8x != val2 %8x", id, val1, val2), 
          rpt_pkg::ERROR, 
          rpt_pkg::TOP);
        return 0;
      end
      else begin  // 比较成功
        rpt_pkg::rpt_msg("[CMPSUC]", 
          $sformatf("SUCCESS! %s val1 %8x == val2 %8x", id, val1, val2),
          rpt_pkg::INFO,
          rpt_pkg::HIGH);
        return 1;
      end
    endfunction

    // 寄存器空闲任务：发送空闲命令到寄存器
    virtual task idle_reg();
      // 随机化寄存器生成器，设置命令为IDLE，地址和数据为0
      void'(reg_gen.randomize() with {cmd == `IDLE; addr == 0; data == 0;});
      reg_gen.start();  // 启动生成器，发送激励
    endtask

    // 寄存器写任务：向指定地址写入数据
    virtual task write_reg(bit[7:0] addr, bit[31:0] data);
      // 随机化生成器，设置命令为WRITE，地址和数据为输入参数
      void'(reg_gen.randomize() with {cmd == `WRITE; addr == local::addr; data == local::data;});
      reg_gen.start();  // 发送写命令
    endtask

    // 寄存器读任务：从指定地址读取数据并返回
    virtual task read_reg(bit[7:0] addr, output bit[31:0] data);
      // 随机化生成器，设置命令为READ，地址为输入参数
      void'(reg_gen.randomize() with {cmd == `READ; addr == local::addr;});
      reg_gen.start();  // 发送读命令
      data = reg_gen.data;  // 获取读取到的数据
    endtask
  endclass

  // MCDF数据一致性基础测试类：继承自基础测试，实现具体的功能验证场景
  // 验证MCDF在不同配置下的数据传输一致性（输入数据经处理后与预期输出一致）
  class mcdf_data_consistence_basic_test extends mcdf_base_test;
    // 构造函数：调用父类构造函数，初始化测试名称
    function new(string name = "mcdf_data_consistence_basic_test");
      super.new(name);
    endfunction

    // 寄存器配置任务：配置3个通道的寄存器（长度、优先级、使能），并验证读写正确性
    task do_reg();
      bit[31:0] wr_val, rd_val;  // 写值和读回值

      // 配置通道0：长度=8（1<<3），优先级=0（0<<1），使能=1 → 总写值=0x09
      wr_val = (1<<3)+(0<<1)+1;
      this.write_reg(`SLV0_RW_ADDR, wr_val);  // 写入配置
      this.read_reg(`SLV0_RW_ADDR, rd_val);   // 读回配置
      void'(this.diff_value(wr_val, rd_val, "SLV0_WR_REG"));  // 验证读写一致性

      // 配置通道1：长度=16（2<<3），优先级=1（1<<1），使能=1 → 总写值=0x13
      wr_val = (2<<3)+(1<<1)+1;
      this.write_reg(`SLV1_RW_ADDR, wr_val);
      this.read_reg(`SLV1_RW_ADDR, rd_val);
      void'(this.diff_value(wr_val, rd_val, "SLV1_WR_REG"));

      // 配置通道2：长度=32（3<<3），优先级=2（2<<1），使能=1 → 总写值=0x1F
      wr_val = (3<<3)+(2<<1)+1;
      this.write_reg(`SLV2_RW_ADDR, wr_val);
      this.read_reg(`SLV2_RW_ADDR, rd_val);
      void'(this.diff_value(wr_val, rd_val, "SLV2_WR_REG"));

      this.idle_reg();  // 发送空闲命令
    endtask

    // 格式化器配置任务：配置格式化器为长FIFO、高带宽模式
    task do_formatter();
      // 随机化格式化器生成器，设置FIFO为长模式，带宽为高模式
      void'(fmt_gen.randomize() with {fifo == LONG_FIFO; bandwidth == HIGH_WIDTH;});
      fmt_gen.start();  // 发送配置
    endtask

    // 数据传输任务：生成3个通道的输入数据并发送，验证数据处理一致性
    task do_data();
      // 随机化通道0生成器：100笔交易，通道0，数据间无空闲，包间空闲1，数据大小8
      void'(chnl_gens[0].randomize() with {ntrans==100; ch_id==0; data_nidles==0; pkt_nidles==1; data_size==8; });
      // 随机化通道1生成器：100笔交易，通道1，数据间空闲1，包间空闲4，数据大小16
      void'(chnl_gens[1].randomize() with {ntrans==100; ch_id==1; data_nidles==1; pkt_nidles==4; data_size==16;});
      // 随机化通道2生成器：100笔交易，通道2，数据间空闲2，包间空闲8，数据大小32
      void'(chnl_gens[2].randomize() with {ntrans==100; ch_id==2; data_nidles==2; pkt_nidles==8; data_size==32;});

      // 并行启动3个通道的生成器，发送数据
      fork
        chnl_gens[0].start();
        chnl_gens[1].start();
        chnl_gens[2].start();
      join

      #10us;  // 等待10微秒，确保所有数据通过MCDF处理完成
    endtask
  endclass

endpackage