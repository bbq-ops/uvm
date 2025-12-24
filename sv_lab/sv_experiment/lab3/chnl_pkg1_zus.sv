// 定义通道数据包相关的包，包含事务、发起器、生成器、代理和测试类
package chnl_pkg1;

  // 通道事务类：定义了通过通道传输的数据结构及约束
  class chnl_trans;
    rand bit[31:0] data[];      // 动态数组，存储要传输的数据
    rand int ch_id;             // 通道ID，用于区分不同通道
    rand int pkt_id;            // 包ID，用于区分同一通道的不同数据包
    rand int data_nidles;       // 数据间的空闲周期数（数据传输间隙）
    rand int pkt_nidles;        // 包间的空闲周期数（数据包传输间隙）
    bit rsp;                    // 响应标志，用于标识是否收到响应
    local static int obj_id = 0;// 静态变量，记录事务对象的唯一ID（局部可见）

    // 约束块：定义随机变量的取值范围和关联关系
    constraint cstr{
      data.size inside {[4:8]};  // 数据长度为4到8个32位数据
      // 数据值约束：按通道ID、包ID和索引生成固定格式数据
      foreach(data[i]) data[i] == 'hC000_0000 + (this.ch_id<<24) + (this.pkt_id<<8) + i;
      soft ch_id == 0;           // 软约束：默认通道ID为0（可被覆盖）
      soft pkt_id == 0;          // 软约束：默认包ID为0（可被覆盖）
      data_nidles inside {[0:2]};// 数据间空闲周期为0到2
      pkt_nidles inside {[1:10]};// 包间空闲周期为1到10
    };

    // 构造函数：创建对象时自增obj_id，保证每个对象ID唯一
    function new();
      this.obj_id++;  // 每次实例化事务对象，ID加1
    endfunction

    // 克隆函数：复制当前事务对象的属性到新对象
    function chnl_trans clone();
      chnl_trans c = new();  // 创建新的事务对象（此时obj_id会自增）
      // 复制成员变量
      c.data = this.data;
      c.ch_id = this.ch_id;
      c.pkt_id = this.pkt_id;
      c.data_nidles = this.data_nidles;
      c.pkt_nidles = this.pkt_nidles;
      c.rsp = this.rsp;
      // 【注意】不能复制obj_id，原因：
      // 1. obj_id是local静态变量，只能在类内部访问，外部无法直接赋值
      // 2. 新对象通过new()已生成唯一ID，复制会破坏ID的唯一性
      return c;
    endfunction

    // 打印函数：格式化输出事务对象的所有属性
    function string sprint();
      string s;  // 用于拼接输出字符串
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("chnl_trans object content is as below: \n")};
      s = {s, $sformatf("obj_id = %0d: \n", this.obj_id)};  // 输出对象唯一ID
      foreach(data[i]) s = {s, $sformatf("data[%0d] = %8x \n", i, this.data[i])};  // 输出数据
      s = {s, $sformatf("ch_id = %0d: \n", this.ch_id)};        // 输出通道ID
      s = {s, $sformatf("pkt_id = %0d: \n", this.pkt_id)};      // 输出包ID
      s = {s, $sformatf("data_nidles = %0d: \n", this.data_nidles)};  // 输出数据间空闲数
      s = {s, $sformatf("pkt_nidles = %0d: \n", this.pkt_nidles)};    // 输出包间空闲数
      s = {s, $sformatf("rsp = %0d: \n", this.rsp)};            // 输出响应标志
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction
  endclass: chnl_trans
  
  // 通道发起器类：负责将事务数据驱动到接口上
  class chnl_initiator;
    local string name;               // 发起器名称（局部可见）
    local virtual chnl_intf intf;    // 接口句柄，用于连接DUT（局部可见）
    mailbox #(chnl_trans) req_mb;    // 请求邮箱：接收来自生成器的事务
    mailbox #(chnl_trans) rsp_mb;    // 响应邮箱：向生成器返回响应

    // 构造函数：初始化发起器名称
    function new(string name = "chnl_initiator");
      this.name = name;
    endfunction
  
    // 设置名称函数：修改发起器名称
    function void set_name(string s);
      this.name = s;
    endfunction
  
    // 设置接口函数：绑定物理接口，若接口为空则报错
    function void set_interface(virtual chnl_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;  // 绑定接口
    endfunction

    // 运行任务：启动驱动流程
    task run();
      this.drive();  // 调用驱动任务
    endtask

    // 驱动任务：从请求邮箱获取事务并驱动到接口，完成后返回响应
    task drive();
      chnl_trans req, rsp;
      @(posedge intf.rstn);  // 等待复位释放（rstn为高电平）
      forever begin  // 循环处理事务
        this.req_mb.get(req);  // 从邮箱获取事务
        this.chnl_write(req);  // 将事务数据写入接口
        rsp = req.clone();     // 克隆请求事务作为响应
        rsp.rsp = 1;           // 标记响应完成
        this.rsp_mb.put(rsp);  // 将响应放入响应邮箱
      end
    endtask
  
    // 写入任务：将事务中的数据逐笔驱动到接口
    task chnl_write(input chnl_trans t);
      foreach(t.data[i]) begin  // 遍历数据数组
        @(posedge intf.clk);    // 时钟上升沿驱动
        intf.drv_ck.ch_valid <= 1;  // 置位有效信号
        intf.drv_ck.ch_data <= t.data[i];  // 驱动数据
        wait(intf.ch_ready === 'b1);  // 等待接收端准备好
        $display("%0t channel initiator [%s] sent data %x", $time, name, t.data[i]);
        repeat(t.data_nidles) chnl_idle();  // 插入数据间空闲周期
      end
      repeat(t.pkt_nidles) chnl_idle();  // 插入包间空闲周期
    endtask
    
    // 空闲任务：驱动空闲状态（valid为0，数据为0）
    task chnl_idle();
      @(posedge intf.clk);  // 时钟上升沿
      intf.drv_ck.ch_valid <= 0;  // 无效信号
      intf.drv_ck.ch_data <= 0;   // 数据清零
    endtask
  endclass: chnl_initiator
  
  // 通道生成器类：负责生成事务并通过邮箱传递给发起器
  class chnl_generator;
    int pkt_id;               // 包计数器，用于生成pkt_id
    int ch_id;                // 通道ID，标识当前生成器所属通道
    int ntrans;               // 要生成的事务总数
    mailbox #(chnl_trans) req_mb;  // 请求邮箱：发送事务给发起器
    mailbox #(chnl_trans) rsp_mb;  // 响应邮箱：接收发起器的响应

    // 构造函数：初始化通道ID、事务总数和邮箱
    function new(int ch_id, int ntrans);
      this.ch_id = ch_id;    // 绑定通道ID
      this.pkt_id = 0;       // 初始化包计数器
      this.ntrans = ntrans;  // 设置事务总数
      this.req_mb = new();   // 实例化请求邮箱
      this.rsp_mb = new();   // 实例化响应邮箱
    endfunction

    // 运行任务：按总数生成事务
    task run();
      repeat(ntrans) send_trans();  // 重复生成ntrans个事务
      // 【1.3 TODO实现】所有事务完成后结束仿真
      $finish();  // 当所有事务传输完成后，调用$finish停止仿真
    endtask

    // 发送事务任务：生成随机事务并通过邮箱传递，等待响应
    task send_trans();
      chnl_trans req, rsp;
      req = new();  // 创建新事务
      // 随机化事务，约束通道ID和包ID为当前生成器的计数器
      assert(req.randomize with {ch_id == local::ch_id; pkt_id == local::pkt_id;})
        else $fatal("[RNDFAIL] channel packet randomization failure!");
      this.pkt_id++;  // 包计数器自增
      $display(req.sprint());  // 打印生成的事务信息
      this.req_mb.put(req);    // 将事务放入请求邮箱
      this.rsp_mb.get(rsp);    // 等待响应邮箱的响应
      $display(rsp.sprint());  // 打印响应信息
      // 检查响应是否有效
      assert(rsp.rsp)
        else $error("[RSPERR] %0t error response received!", $time);
    endtask
  endclass: chnl_generator

  // 通道代理类：整合生成器和发起器，作为通道的顶层组件
  class chnl_agent;
    chnl_generator gen;   // 生成器实例
    chnl_initiator init;  // 发起器实例
    local virtual chnl_intf vif;  // 接口句柄（局部可见）

    // 构造函数：实例化生成器和发起器
    function new(string name = "chnl_agent", int id = 0, int ntrans = 1);
      this.gen = new(id, ntrans);  // 实例化生成器，指定通道ID和事务数
      this.init = new(name);       // 实例化发起器，指定名称
    endfunction

    // 设置接口函数：将接口传递给发起器
    function void set_interface(virtual chnl_intf vif);
      this.vif = vif;
      init.set_interface(vif);  // 发起器绑定接口
    endfunction

    // 运行任务：启动生成器和发起器（并行执行）
    task run();
      // 连接生成器和发起器的邮箱（请求和响应通道）
      this.init.req_mb = this.gen.req_mb;
      this.init.rsp_mb = this.gen.rsp_mb;
      fork
        gen.run();  // 启动生成器
        init.run(); // 启动发起器
      join_any  // 任一完成则退出（实际由生成器控制结束）
    endtask
  endclass: chnl_agent

  // 根测试类：作为所有测试的基类，管理多个通道代理
  class chnl_root_test;
    chnl_agent agent[3];  // 3个通道代理（支持3个通道）
    protected string name;  // 测试名称（受保护，仅子类可见）

    // 构造函数：实例化3个通道代理，指定事务数和名称
    function new(int ntrans = 100, string name = "chnl_root_test");
      foreach(agent[i]) begin  // 遍历3个通道
        // 实例化代理：名称为"chnl_agent0/1/2"，通道ID为i，事务数为ntrans
        this.agent[i] = new($sformatf("chnl_agent%0d",i), i, ntrans);
      end
      this.name = name;
      $display("%s instantiate objects", this.name);  // 打印测试初始化信息
    endfunction

    // 运行任务：启动所有通道代理（并行执行）
    task run();
      $display($sformatf("*****************%s started********************", this.name));
      fork
        agent[0].run();  // 启动通道0
        agent[1].run();  // 启动通道1
        agent[2].run();  // 启动通道2
      join  // 等待所有通道完成
      $display($sformatf("*****************%s finished********************", this.name));
      // 【1.3 TODO说明】原$finish移至generator的run()中，确保所有事务完成后结束
    endtask

    // 设置接口函数：为3个通道代理分别绑定接口
    function void set_interface(virtual chnl_intf ch0_vif, virtual chnl_intf ch1_vif, virtual chnl_intf ch2_vif);
      agent[0].set_interface(ch0_vif);  // 通道0绑定接口
      agent[1].set_interface(ch1_vif);  // 通道1绑定接口
      agent[2].set_interface(ch2_vif);  // 通道2绑定接口
    endfunction
  endclass

  // 基础测试类：继承根测试，定制基础测试场景
  // 需求：每个通道发送200个数据，数据间空闲[0:2]，包间空闲[3:5]
  class chnl_basic_test extends chnl_root_test;
    // 约束重写：在构造函数中通过super调用父类，并修改约束
    function new(int ntrans = 200, string name = "chnl_basic_test");
      super.new(ntrans, name);  // 调用父类构造，设置事务数为200
    endfunction
    // 【1.1 TODO实现】在chnl_trans的约束中补充：
    // data_nidles inside {[0:2]};  // 数据间空闲已满足
    // pkt_nidles inside {[3:5]};   // 包间空闲修改为3到5（覆盖原约束）
  endclass: chnl_basic_test

  // 突发测试类：预留，可用于测试突发传输场景
  class chnl_burst_test extends chnl_root_test;
    // 可在此处定义突发传输的特殊约束，如连续多包、短空闲等
  endclass: chnl_burst_test

  // FIFO满测试类：预留，可用于测试DUT的FIFO满状态下的行为
  class chnl_fifo_full_test extends chnl_root_test;
    // 可在此处设计使DUT的FIFO填满的场景，测试背压机制
  endclass: chnl_fifo_full_test

endpackage