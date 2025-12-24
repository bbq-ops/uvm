// 定义一个名为chnl_pkg2的包，用于封装通道相关的验证组件
package chnl_pkg2;
  // 通道事务类：定义了需要在通道上传输的数据结构和属性
  class chnl_trans;
    rand bit[31:0] data[];      // 随机动态数组，存储传输的数据
    rand int ch_id;             // 通道ID，用于多通道区分
    rand int pkt_id;            // 包ID，用于标识同一通道中的不同数据包
    rand int data_nidles;       // 数据之间的空闲周期数
    rand int pkt_nidles;        // 数据包之间的空闲周期数
    bit rsp;                    // 响应标志，标识是否为响应事务
    local static int obj_id = 0;// 静态变量，用于记录事务对象的唯一ID（本地可见）

    // 约束块：限制随机变量的取值范围和关系
    constraint cstr{
      data.size inside {[4:8]}; // 数据数组大小在4到8之间
      // 数据值约束：按通道ID、包ID和索引生成可预测的数据，便于验证
      foreach(data[i]) data[i] == 'hC000_0000 + (this.ch_id<<24) + (this.pkt_id<<8) + i;
      soft ch_id == 0;          // 软约束：默认通道ID为0（可被覆盖）
      soft pkt_id == 0;         // 软约束：默认包ID为0（可被覆盖）
      data_nidles inside {[0:2]};// 数据间空闲周期在0到2之间
      pkt_nidles inside {[1:10]};// 数据包间空闲周期在1到10之间
    };

    // 构造函数：创建事务对象时自增obj_id，保证每个对象ID唯一
    function new();
      this.obj_id++;
    endfunction

    // 克隆函数：创建一个当前事务的副本并返回
    function chnl_trans clone();
      chnl_trans c = new();      // 创建新的事务对象
      // 复制所有成员变量的值
      c.data = this.data;
      c.ch_id = this.ch_id;
      c.pkt_id = this.pkt_id;
      c.data_nidles = this.data_nidles;
      c.pkt_nidles = this.pkt_nidles;
      c.rsp = this.rsp;
      return c;
    endfunction

    // 打印函数：格式化输出事务对象的所有属性信息
    function string sprint();
      string s;                  // 用于拼接字符串
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("chnl_trans object content is as below: \n")};
      s = {s, $sformatf("obj_id = %0d: \n", this.obj_id)};
      foreach(data[i]) s = {s, $sformatf("data[%0d] = %8x \n", i, this.data[i])};
      s = {s, $sformatf("ch_id = %0d: \n", this.ch_id)};
      s = {s, $sformatf("pkt_id = %0d: \n", this.pkt_id)};
      s = {s, $sformatf("data_nidles = %0d: \n", this.data_nidles)};
      s = {s, $sformatf("pkt_nidles = %0d: \n", this.pkt_nidles)};
      s = {s, $sformatf("rsp = %0d: \n", this.rsp)};
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction
  endclass: chnl_trans
  
  // 通道发起器类：负责将事务数据驱动到物理接口上
  class chnl_initiator;
    local string name;               // 发起器名称（本地可见）
    local virtual chnl_intf intf;    // 虚拟接口句柄，用于连接DUT（本地可见）
    mailbox #(chnl_trans) req_mb;    // 请求邮箱：接收来自生成器的事务
    mailbox #(chnl_trans) rsp_mb;    // 响应邮箱：向生成器返回响应

    // 构造函数：初始化发起器名称
    function new(string name = "chnl_initiator");
      this.name = name;
    endfunction
  
    // 设置名称函数：修改发起器的名称
    function void set_name(string s);
      this.name = s;
    endfunction
  
    // 设置接口函数：绑定物理接口到虚拟接口句柄
    function void set_interface(virtual chnl_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction

    // 运行任务：启动发起器的主逻辑
    task run();
      this.drive();  // 调用驱动任务
    endtask

    // 驱动任务：从邮箱获取事务并驱动到接口
    task drive();
      chnl_trans req, rsp;
      @(posedge intf.rstn);  // 等待复位释放（rstn为高电平）
      forever begin          // 循环处理事务
        this.req_mb.get(req); // 从请求邮箱获取事务
        this.chnl_write(req); // 将事务数据写入接口
        rsp = req.clone();    // 克隆请求事务作为响应
        rsp.rsp = 1;          // 标记为响应
        this.rsp_mb.put(rsp); // 将响应放入响应邮箱
      end
    endtask
  
    // 写入任务：将事务中的数据逐拍驱动到接口信号
    task chnl_write(input chnl_trans t);
      foreach(t.data[i]) begin       // 遍历数据数组
        @(posedge intf.clk);         // 等待时钟上升沿
        intf.drv_ck.ch_valid <= 1;   // 驱动valid信号为1（数据有效）
        intf.drv_ck.ch_data <= t.data[i]; // 驱动数据到接口
        wait(intf.ch_ready === 'b1); // 等待接收端准备好（ready为1）
        // 打印发送信息
        $display("%0t channel initiator [%s] sent data %x", $time, name, t.data[i]);
        repeat(t.data_nidles) chnl_idle(); // 插入数据间的空闲周期
      end
      repeat(t.pkt_nidles) chnl_idle();   // 插入数据包间的空闲周期
    endtask
    
    // 空闲任务：驱动接口为空闲状态（valid=0，data=0）
    task chnl_idle();
      @(posedge intf.clk);         // 等待时钟上升沿
      intf.drv_ck.ch_valid <= 0;   // 驱动valid为0（无有效数据）
      intf.drv_ck.ch_data <= 0;    // 数据信号置0
    endtask
  endclass: chnl_initiator
  
  // 通道生成器类：负责生成随机的事务并发送给发起器
  class chnl_generator;
    rand int pkt_id = -1;      // 包ID（-1表示使用随机值）
    rand int ch_id = -1;       // 通道ID（-1表示使用随机值）
    rand int data_nidles = -1; // 数据间空闲周期（-1表示使用随机值）
    rand int pkt_nidles = -1;  // 包间空闲周期（-1表示使用随机值）
    rand int data_size = -1;   // 数据大小（-1表示使用随机值）
    rand int ntrans = 10;      // 生成的事务总数（默认10个）

    mailbox #(chnl_trans) req_mb;  // 请求邮箱：发送事务给发起器
    mailbox #(chnl_trans) rsp_mb;  // 响应邮箱：接收发起器的响应

    // 约束块：控制生成器的随机参数
    constraint cstr{
      soft ch_id == -1;        // 软约束：默认通道ID使用随机值
      soft pkt_id == -1;       // 软约束：默认包ID使用随机值
      soft data_size == -1;    // 软约束：默认数据大小使用随机值
      soft data_nidles == -1;  // 软约束：默认数据间空闲使用随机值
      soft pkt_nidles == -1;   // 软约束：默认包间空闲使用随机值
      soft ntrans == 10;       // 软约束：默认生成10个事务
    }

    // 构造函数：初始化邮箱
    function new();
      this.req_mb = new();
      this.rsp_mb = new();
    endfunction

    // 运行任务：生成指定数量的事务
    task run();
      repeat(ntrans) send_trans();  // 循环生成ntrans个事务
    endtask

    // 发送事务任务：生成并随机化事务，发送给发起器并等待响应
    task send_trans();
      chnl_trans req, rsp;
      req = new();  // 创建新事务
      // 随机化事务，通过with约束将生成器参数传递给事务
      assert(req.randomize with {local::ch_id >= 0 -> ch_id == local::ch_id; 
                                 local::pkt_id >= 0 -> pkt_id == local::pkt_id;
                                 local::data_nidles >= 0 -> data_nidles == local::data_nidles;
                                 local::pkt_nidles >= 0 -> pkt_nidles == local::pkt_nidles;
                                 local::data_size >0 -> data.size() == local::data_size; 
                               })
        else $fatal("[RNDFAIL] channel packet randomization failure!");
      this.pkt_id++;  // 包ID自增（用于连续生成事务）
      $display(req.sprint());  // 打印事务信息
      this.req_mb.put(req);    // 将事务放入请求邮箱（发送给发起器）
      this.rsp_mb.get(rsp);    // 从响应邮箱获取响应
      $display(rsp.sprint());  // 打印响应信息
      assert(rsp.rsp)          // 检查响应是否有效
        else $error("[RSPERR] %0t error response received!", $time);
    endtask

    // 打印函数：格式化输出生成器的属性信息
    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("chnl_generator object content is as below: \n")};
      s = {s, $sformatf("ntrans = %0d: \n", this.ntrans)};
      s = {s, $sformatf("ch_id = %0d: \n", this.ch_id)};
      s = {s, $sformatf("pkt_id = %0d: \n", this.pkt_id)};
      s = {s, $sformatf("data_nidles = %0d: \n", this.data_nidles)};
      s = {s, $sformatf("pkt_nidles = %0d: \n", this.pkt_nidles)};
      s = {s, $sformatf("data_size = %0d: \n", this.data_size)};
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction

    // 随机化后回调函数：随机化完成后打印生成器状态
    function void post_randomize();
      string s;
      s = {"AFTER RANDOMIZATION \n", this.sprint()};
      $display(s);
    endfunction
  endclass: chnl_generator

  // 通道代理类：整合发起器，提供更高层的组件封装
  class chnl_agent;
    chnl_initiator init;       // 包含一个发起器实例
    local virtual chnl_intf vif; // 虚拟接口句柄（本地可见）

    // 构造函数：初始化发起器
    function new(string name = "chnl_agent");
      this.init = new(name);
    endfunction

    // 设置接口函数：将接口传递给内部的发起器
    function void set_interface(virtual chnl_intf vif);
      this.vif = vif;
      init.set_interface(vif);  // 发起器绑定接口
    endfunction

    // 运行任务：启动代理的主逻辑（调用发起器的运行任务）
    task run();
      fork
        init.run();  // 并行运行发起器
      join
    endtask
  endclass: chnl_agent

  // 根测试类：测试环境的顶层控制类，实例化并连接各组件
  class chnl_root_test;
    chnl_generator gen[3];    // 3个生成器（对应3个通道）
    chnl_agent agent[3];      // 3个代理（对应3个通道）
    protected string name;    // 测试名称（受保护，仅本类和子类可见）

    // 构造函数：初始化生成器和代理，连接组件
    function new(string name = "chnl_root_test");
      foreach(agent[i]) begin
        this.agent[i] = new($sformatf("chnl_agent%0d",i)); // 实例化代理并命名
        this.gen[i] = new();                               // 实例化生成器
        // USER TODO 2.1：连接生成器和代理的邮箱（实现通信）
        // 生成器的请求邮箱应与代理中发起器的请求邮箱绑定
        // gen[i].req_mb = agent[i].init.req_mb;
        // 生成器的响应邮箱应与代理中发起器的响应邮箱绑定
        // gen[i].rsp_mb = agent[i].init.rsp_mb;
      end
      this.name = name;
      $display("%s instantiate objects", this.name);
    endfunction

    // 运行任务：控制测试流程
    virtual task run();
      $display($sformatf("*****************%s started********************", this.name));
      this.do_config();  // 配置测试环境

      // 并行启动3个代理（发起器开始等待事务）
      fork
        agent[0].run();
        agent[1].run();
        agent[2].run();
      join_none

      // 并行启动3个生成器（开始生成事务）
      fork
        gen[0].run();
        gen[1].run();
        gen[2].run();
      join

      $display($sformatf("*****************%s finished********************", this.name));
      // USER TODO 1.3：将$finish从这里移到生成器中，当所有事务传输完成后停止测试
      $finish();
    endtask

    // 设置接口函数：为每个通道的代理绑定对应的物理接口
    virtual function void set_interface(virtual chnl_intf ch0_vif, virtual chnl_intf ch1_vif, virtual chnl_intf ch2_vif);
      agent[0].set_interface(ch0_vif);
      agent[1].set_interface(ch1_vif);
      agent[2].set_interface(ch2_vif);
    endfunction

    // 配置函数：随机化生成器参数，定制测试场景
    virtual function void do_config();
      // 配置gen[0]：生成100个事务，数据间无空闲，包间空闲1，数据大小8
      assert(gen[0].randomize() with {ntrans==100; data_nidles==0; pkt_nidles==1; data_size==8;})
        else $fatal("[RNDFAIL] gen[0] randomization failure!");

      // USER TODO 2.2：配置gen[1]
      // 要求：ntrans==50，data_nidles在[1:2]，pkt_nidles在[3:5]，data_size==6
      // assert(gen[1].randomize() with {ntrans==50; data_nidles inside [1:2]; pkt_nidles inside [3:5]; data_size==6;})
      //   else $fatal("[RNDFAIL] gen[1] randomization failure!");

      // USER TODO 2.3：配置gen[2]
      // 要求：ntrans==80，data_nidles在[0:1]，pkt_nidles在[1:2]，data_size==32
      // assert(gen[2].randomize() with {ntrans==80; data_nidles inside [0:1]; pkt_nidles inside [1:2]; data_size==32;})
      //   else $fatal("[RNDFAIL] gen[2] randomization failure!");
    endfunction
  endclass

  // 基础测试类：继承自根测试类，可定制基础测试场景
  class chnl_basic_test extends chnl_root_test;
    function new(string name = "chnl_basic_test");
      super.new(name);  // 调用父类构造函数
    endfunction
  endclass: chnl_basic_test

  // 突发测试类：测试通道突发传输能力
  // USER TODO 2.4：每个通道发送的数据包数量在[80:100]之间
  // data_nidles==0，pkt_nidles==1，data_size在{8,16,32}中
  class chnl_burst_test extends chnl_root_test;
    function new(string name = "chnl_burst_test");
      super.new(name);  // 调用父类构造函数
    endfunction
    // 重写配置函数，设置突发传输参数
    // virtual function void do_config();
    //   foreach(gen[i]) begin
    //     assert(gen[i].randomize() with {
    //       ntrans inside [80:100];
    //       data_nidles == 0;
    //       pkt_nidles == 1;
    //       data_size inside {8,16,32};
    //     }) else $fatal("[RNDFAIL] chnl_burst_test gen[%0d] randomization failure!", i);
    //   end
    // endfunction
  endclass: chnl_burst_test

  // FIFO满测试类：测试当从端FIFO满（ready=0）时的通道行为
  // USER TODO 2.5：持续发送数据包，直到所有从端通道同时拉高fifo_full（ready=0），然后停止测试
  class chnl_fifo_full_test extends chnl_root_test;
    function new(string name = "chnl_fifo_full_test");
      super.new(name);  // 调用父类构造函数
    endfunction
    // 重写运行任务，添加FIFO满的检测逻辑
    // virtual task run();
    //   $display($sformatf("*****************%s started********************", this.name));
    //   this.do_config();
    //   
    //   fork
    //     agent[0].run();
    //     agent[1].run();
    //     agent[2].run();
    //   join_none
    //   
    //   fork
    //     gen[0].run();
    //     gen[1].run();
    //     gen[2].run();
    //   join_none
    //   
    //   // 等待所有通道的ready信号同时为0（FIFO满）
    //   wait(agent[0].vif.ch_ready === 0 && agent[1].vif.ch_ready === 0 && agent[2].vif.ch_ready === 0);
    //   $display("%0t All channels FIFO full detected, stopping test...", $time);
    //   $finish();
    // endfunction
  endclass: chnl_fifo_full_test

endpackage