// ###########################################################################
// 包名：chnl_pkg2
// 功能：AXI-like 通道测试平台核心包，包含事务定义、发起器、生成器、代理、测试类
// 设计理念：模块化分离（生成器与代理解耦）、灵活随机化（支持动态约束覆盖）、可扩展测试场景
// ###########################################################################
package chnl_pkg2;

  // #########################################################################
  // 类名：chnl_trans
  // 功能：通道事务（Transaction）类，封装单次数据传输的所有属性
  // 作用：作为生成器、发起器、响应之间的数据载体
  // #########################################################################
  class chnl_trans;
    rand bit[31:0] data[];        // 动态数据数组：存储待传输的32位数据
    rand int ch_id;               // 通道ID：标识数据所属通道（0/1/2）
    rand int pkt_id;              // 包ID：标识同一通道内的数据包序号
    rand int data_nidles;         // 数据间空闲周期：相邻数据位之间的空闲时钟数
    rand int pkt_nidles;          // 包间空闲周期：相邻数据包之间的空闲时钟数
    bit rsp;                      // 响应标志：1=收到响应，0=未收到（发起器设置）
    local static int obj_id = 0;  // 静态对象计数器（局部可见）：统计事务对象创建个数

    // 约束块：限制事务属性的合法范围，保证数据符合传输协议
    constraint cstr{
      data.size inside {[4:8]};  // 数据数组长度：4~8个32位数据（即16~32字节）
      
      // 数据内容约束：固定格式便于验证（C000_0000 + 通道偏移 + 包偏移 + 数据索引）
      foreach(data[i]) data[i] == 'hC000_0000 + (this.ch_id<<24) + (this.pkt_id<<8) + i;
      
      soft ch_id == 0;           // 软约束：默认通道0（允许外部覆盖）
      soft pkt_id == 0;          // 软约束：默认包ID 0（允许外部覆盖）
      data_nidles inside {[0:2]};// 数据间空闲：0~2个时钟（避免过长阻塞）
      pkt_nidles inside {[1:10]};// 包间空闲：1~10个时钟（平衡传输效率与稳定性）
    };

    // 构造函数：创建事务对象时自动递增对象计数器
    function new();
      this.obj_id++;  // 静态变量共享，所有对象共用一个计数器，统计总创建数
    endfunction

    // 克隆函数：复制当前事务对象的所有属性（深拷贝核心数据）
    // 用途：发起器发送请求后，克隆请求事务作为响应载体
    function chnl_trans clone();
      chnl_trans c = new();       // 创建新事务对象（会触发obj_id自增）
      c.data = this.data;         // 复制数据数组
      c.ch_id = this.ch_id;       // 复制通道ID
      c.pkt_id = this.pkt_id;     // 复制包ID
      c.data_nidles = this.data_nidles; // 复制数据间空闲
      c.pkt_nidles = this.pkt_nidles; // 复制包间空闲
      c.rsp = this.rsp;           // 复制响应标志
      return c;                   // 返回克隆后的新对象
    endfunction

    // 打印函数：格式化输出事务对象的所有属性
    // 用途：调试时查看事务内容，验证数据正确性
    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("chnl_trans object content is as below: \n")};
      s = {s, $sformatf("obj_id = %0d: \n", this.obj_id)};  // 打印对象编号
      foreach(data[i]) s = {s, $sformatf("data[%0d] = %8x \n", i, this.data[i])}; // 打印所有数据
      s = {s, $sformatf("ch_id = %0d: \n", this.ch_id)};     // 打印通道ID
      s = {s, $sformatf("pkt_id = %0d: \n", this.pkt_id)};   // 打印包ID
      s = {s, $sformatf("data_nidles = %0d: \n", this.data_nidles)}; // 打印数据间空闲
      s = {s, $sformatf("pkt_nidles = %0d: \n", this.pkt_nidles)}; // 打印包间空闲
      s = {s, $sformatf("rsp = %0d: \n", this.rsp)};         // 打印响应标志
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction
  endclass: chnl_trans
  
  // #########################################################################
  // 类名：chnl_initiator
  // 功能：通道发起器（Initiator）类，驱动接口信号完成数据发送
  // 作用：从生成器获取事务请求，通过物理接口（chnl_intf）发送数据，返回响应
  // #########################################################################
  class chnl_initiator;
    local string name;                // 发起器名称（局部可见）：用于日志区分多个发起器
    local virtual chnl_intf intf;     // 虚拟接口句柄（局部可见）：连接物理接口，驱动信号
    mailbox #(chnl_trans) req_mb;     // 请求邮箱：接收生成器发送的事务请求
    mailbox #(chnl_trans) rsp_mb;     // 响应邮箱：向生成器返回处理后的事务（带响应标志）
  
    // 构造函数：初始化发起器名称（默认值为"chnl_initiator"）
    function new(string name = "chnl_initiator");
      this.name = name;
    endfunction
  
    // 名称设置函数：动态修改发起器名称
    function void set_name(string s);
      this.name = s;
    endfunction
  
    // 接口绑定函数：将虚拟接口与物理接口关联（必须调用，否则无法驱动信号）
    function void set_interface(virtual chnl_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;  // 绑定成功，后续可通过intf驱动接口信号
    endfunction

    // 运行函数：启动发起器核心逻辑（对外接口）
    task run();
      this.drive();  // 调用驱动任务，开始数据发送
    endtask

    // 驱动任务：核心逻辑，循环处理请求并发送数据
    task drive();
      chnl_trans req, rsp;
      @(posedge intf.rstn);  // 等待复位释放（rstn高电平）：复位期间不驱动信号
      forever begin           // 无限循环，持续处理请求
        this.req_mb.get(req); // 从请求邮箱获取一个事务请求
        this.chnl_write(req); // 调用写接口任务，发送事务数据
        rsp = req.clone();    // 克隆请求事务作为响应载体
        rsp.rsp = 1;          // 设置响应标志（表示数据已发送完成）
        this.rsp_mb.put(rsp); // 将响应事务放入响应邮箱，返回给生成器
      end
    endtask
  
    // 写接口任务：根据事务属性，驱动接口信号发送数据
    task chnl_write(input chnl_trans t);
      foreach(t.data[i]) begin  // 遍历事务中的所有数据
        @(posedge intf.clk);    // 时钟上升沿触发：符合时序要求
        intf.drv_ck.ch_valid <= 1;  // 驱动valid信号为1：表示数据有效
        intf.drv_ck.ch_data <= t.data[i]; // 驱动data信号：发送当前数据
        wait(intf.ch_ready === 'b1); // 等待从机ready信号为1：表示从机已准备接收
        $display("%0t channel initiator [%s] sent data %x", $time, name, t.data[i]); // 打印发送日志
        repeat(t.data_nidles) chnl_idle(); // 数据间空闲：按事务配置插入空闲周期
      end
      repeat(t.pkt_nidles) chnl_idle(); // 包间空闲：所有数据发送完成后插入空闲周期
    endtask
    
    // 空闲任务：驱动接口进入空闲状态（valid=0，data=0）
    task chnl_idle();
      @(posedge intf.clk);
      intf.drv_ck.ch_valid <= 0;  // 数据无效
      intf.drv_ck.ch_data <= 0;   // 数据总线清零
    endtask
  endclass: chnl_initiator
  
  // #########################################################################
  // 类名：chnl_generator
  // 功能：通道生成器（Generator）类，随机生成事务请求
  // 作用：按配置随机生成符合约束的事务，发送给发起器，接收响应并验证
  // 设计亮点：支持动态约束覆盖，默认值为-1表示"不约束"，灵活适配不同测试场景
  // #########################################################################
  class chnl_generator;
    rand int pkt_id = -1;        // 包ID（默认-1：不约束，由事务自身软约束决定）
    rand int ch_id = -1;         // 通道ID（默认-1：不约束，由事务自身软约束决定）
    rand int data_nidles = -1;   // 数据间空闲（默认-1：不约束）
    rand int pkt_nidles = -1;    // 包间空闲（默认-1：不约束）
    rand int data_size = -1;     // 数据长度（默认-1：不约束，由事务自身约束决定）
    rand int ntrans = 10;        // 总事务数（默认10：生成10个数据包，支持外部覆盖）

    mailbox #(chnl_trans) req_mb; // 请求邮箱：向发起器发送事务请求
    mailbox #(chnl_trans) rsp_mb; // 响应邮箱：接收发起器返回的响应事务

    // 约束块：软约束默认值，允许外部通过randomize(with{})覆盖
    constraint cstr{
      soft ch_id == -1;        // 软约束：默认不指定通道ID
      soft pkt_id == -1;       // 软约束：默认不指定包ID
      soft data_size == -1;    // 软约束：默认不指定数据长度
      soft data_nidles == -1;  // 软约束：默认不指定数据间空闲
      soft pkt_nidles == -1;   // 软约束：默认不指定包间空闲
      soft ntrans == 10;       // 软约束：默认生成10个事务
    }

    // 构造函数：初始化请求/响应邮箱（邮箱必须实例化，否则无法通信）
    function new();
      this.req_mb = new();
      this.rsp_mb = new();
    endfunction

    // 运行函数：启动生成器核心逻辑，生成指定数量的事务
    task run();
      repeat(ntrans) send_trans(); // 循环ntrans次，每次生成一个事务
    endtask

    // 事务生成与发送任务：核心逻辑，随机化事务并完成请求/响应交互
    task send_trans();
      chnl_trans req, rsp;
      req = new();  // 创建新事务对象（触发obj_id自增）
      
      // 事务随机化：带条件约束（仅当生成器对应属性>=0时，才约束事务）
      assert(req.randomize with {
        local::ch_id >= 0 -> ch_id == local::ch_id;  // 生成器ch_id>=0时，事务ch_id强制匹配
        local::pkt_id >= 0 -> pkt_id == local::pkt_id; // 生成器pkt_id>=0时，事务pkt_id强制匹配
        local::data_nidles >= 0 -> data_nidles == local::data_nidles; // 强制数据间空闲
        local::pkt_nidles >= 0 -> pkt_nidles == local::pkt_nidles; // 强制包间空闲
        local::data_size >0 -> data.size() == local::data_size; // 数据长度>0时，强制事务数据长度
      })
        else $fatal("[RNDFAIL] channel packet randomization failure!"); // 随机化失败则终止仿真
      
      this.pkt_id++;  // 包ID自增：同一生成器的事务按顺序编号
      $display(req.sprint());  // 打印生成的事务信息（调试用）
      this.req_mb.put(req);    // 将事务放入请求邮箱，发送给发起器
      this.rsp_mb.get(rsp);    // 从响应邮箱获取发起器返回的响应
      $display(rsp.sprint());  // 打印响应事务信息（验证用）
      
      assert(rsp.rsp)  // 验证响应标志：确保发起器已处理该事务
        else $error("[RSPERR] %0t error response received!", $time);
    endtask

    // 打印函数：格式化输出生成器的配置属性
    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("chnl_generator object content is as below: \n")};
      s = {s, $sformatf("ntrans = %0d: \n", this.ntrans)};         // 总事务数
      s = {s, $sformatf("ch_id = %0d: \n", this.ch_id)};           // 通道ID（-1表示未约束）
      s = {s, $sformatf("pkt_id = %0d: \n", this.pkt_id)};         // 包ID（当前编号）
      s = {s, $sformatf("data_nidles = %0d: \n", this.data_nidles)}; // 数据间空闲（-1表示未约束）
      s = {s, $sformatf("pkt_nidles = %0d: \n", this.pkt_nidles)}; // 包间空闲（-1表示未约束）
      s = {s, $sformatf("data_size = %0d: \n", this.data_size)};   // 数据长度（-1表示未约束）
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction

    // 随机化后回调函数：生成器随机化完成后自动调用，打印配置信息
    function void post_randomize();
      string s;
      s = {"AFTER RANDOMIZATION \n", this.sprint()};
      $display(s);  // 调试用：确认生成器的最终配置
    endfunction
  endclass: chnl_generator

  // #########################################################################
  // 类名：chnl_agent
  // 功能：通道代理（Agent）类，封装发起器，简化测试类的接口
  // 作用：作为发起器的"容器"，对外提供统一的接口（设置名称、绑定接口、启动）
  // 设计亮点：与生成器解耦（生成器移至测试类），提高复用性
  // #########################################################################
  class chnl_agent;
    chnl_initiator init;          // 包含的发起器对象
    local virtual chnl_intf vif;  // 虚拟接口句柄（局部可见）：传递给发起器
  
    // 构造函数：初始化发起器（默认名称为"chnl_agent"）
    function new(string name = "chnl_agent");
      this.init = new(name);
    endfunction
  
    // 接口绑定函数：将外部接口传递给内部发起器（代理模式）
    function void set_interface(virtual chnl_intf vif);
      this.vif = vif;
      init.set_interface(vif);  // 转发接口给发起器
    endfunction
  
    // 运行函数：启动代理（本质是启动内部发起器）
    task run();
      fork
        init.run();  // 启动发起器
      join
    endtask
  endclass: chnl_agent

  // #########################################################################
  // 类名：chnl_root_test
  // 功能：根测试类（Root Test），测试平台的顶层控制类
  // 作用：实例化生成器、代理，配置测试参数，启动测试流程，管理测试生命周期
  // #########################################################################
  class chnl_root_test;
    chnl_generator gen[3];  // 生成器数组：3个生成器（对应3个通道）
    chnl_agent agent[3];    // 代理数组：3个代理（对应3个通道）
    protected string name;  // 测试名称（保护成员：仅本类及子类可见）

    // 构造函数：实例化3个生成器和3个代理，初始化测试名称
    function new(string name = "chnl_root_test");
      foreach(agent[i]) begin
        this.agent[i] = new($sformatf("chnl_agent%0d",i));  // 代理名称：chnl_agent0/1/2
        this.gen[i] = new();                                // 实例化生成器
        // USER TODO 2.1：连接生成器与代理的邮箱（关键通信链路）
        // 原理：生成器的req_mb需与代理内发起器的req_mb关联，才能传递事务
        // 实现代码：
        // agent[i].init.req_mb = this.gen[i].req_mb;  // 请求邮箱绑定
        // agent[i].init.rsp_mb = this.gen[i].rsp_mb;  // 响应邮箱绑定
      end
      this.name = name;
      $display("%s instantiate objects", this.name);  // 打印测试初始化日志
    endfunction

    // 运行函数：测试核心流程（虚拟函数：允许子类重写）
    virtual task run();
      $display($sformatf("*****************%s started********************", this.name));
      this.do_config();  // 调用配置函数，设置生成器参数
      
      // 启动3个代理（发起器）：使用join_none，让代理后台运行
      fork
        agent[0].run();
        agent[1].run();
        agent[2].run();
      join_none
      
      // 启动3个生成器：使用join，等待所有生成器完成事务生成
      fork
        gen[0].run();
        gen[1].run();
        gen[2].run();
      join
      
      $display($sformatf("*****************%s finished********************", this.name));
      
      // USER TODO 1.3：将$finish从测试类移至生成器
      // 原因：测试应在所有生成器完成事务发送后自动结束，而非测试类强制终止
      // 实现方案：在生成器的run()任务最后（repeat循环结束后）添加$finish();
      $finish();  // 临时：终止仿真（需迁移）
    endtask

    // 接口绑定函数：将3个通道的物理接口绑定到对应代理（虚拟函数：允许子类重写）
    virtual function void set_interface(virtual chnl_intf ch0_vif, virtual chnl_intf ch1_vif, virtual chnl_intf ch2_vif);
      agent[0].set_interface(ch0_vif);  // 通道0接口绑定
      agent[1].set_interface(ch1_vif);  // 通道1接口绑定
      agent[2].set_interface(ch2_vif);  // 通道2接口绑定
    endfunction

    // 配置函数：设置生成器的随机化参数（虚拟函数：允许子类重写，适配不同测试场景）
    virtual function void do_config();
      // 配置生成器0：固定参数（ntrans=100，data_nidles=0，pkt_nidles=1，data_size=8）
      assert(gen[0].randomize() with {ntrans==100; data_nidles==0; pkt_nidles==1; data_size==8;})
        else $fatal("[RNDFAIL] gen[0] randomization failure!");

      // USER TODO 2.2：配置生成器1
      // 需求：ntrans=50（生成50个事务），data_nidles=1~2，pkt_nidles=3~5，data_size=6
      // 实现代码：
      // assert(gen[1].randomize() with {ntrans==50; data_nidles inside {[1:2]}; pkt_nidles inside {[3:5]}; data_size==6;})
      //   else $fatal("[RNDFAIL] gen[1] randomization failure!");

      // USER TODO 2.3：配置生成器2
      // 需求：ntrans=80（生成80个事务），data_nidles=0~1，pkt_nidles=1~2，data_size=32
      // 注意：需修改chnl_trans的data.size约束（默认[4:8]），否则data_size=32会随机化失败
      // 实现代码：
      // assert(gen[2].randomize() with {ntrans==80; data_nidles inside {[0:1]}; pkt_nidles inside {[1:2]}; data_size==32;})
      //   else $fatal("[RNDFAIL] gen[2] randomization failure!");
    endfunction
  endclass

  // #########################################################################
  // 类名：chnl_basic_test
  // 功能：基础测试类（继承根测试类）
  // 作用：实现最基础的测试场景（使用根测试类的默认配置）
  // #########################################################################
  class chnl_basic_test extends chnl_root_test;
    // 构造函数：调用父类构造函数，设置测试名称
    function new(string name = "chnl_basic_test");
      super.new(name);  // 继承父类的实例化和配置逻辑
    endfunction
  endclass: chnl_basic_test

  // #########################################################################
  // 类名：chnl_burst_test
  // 功能：突发测试类（继承根测试类）
  // 作用：测试突发传输场景（高吞吐、固定空闲周期）
  // 需求：每个通道发送80~100个数据包，data_nidles=0，pkt_nidles=1，data_size=8/16/32
  // #########################################################################
  class chnl_burst_test extends chnl_root_test;
    // 构造函数：调用父类构造函数，设置测试名称
    function new(string name = "chnl_burst_test");
      super.new(name);
    endfunction
    
    // USER TODO：重写do_config()函数，配置3个生成器的突发传输参数
    // 实现思路：
    // 1. 每个生成器的ntrans约束在[80:100]
    // 2. data_nidles强制为0（无数据间空闲，突发传输）
    // 3. pkt_nidles强制为1（最小包间空闲，高吞吐）
    // 4. data_size约束在{8,16,32}（支持不同突发长度）
    // 示例代码（gen[0]）：
    // virtual function void do_config();
    //   assert(gen[0].randomize() with {ntrans inside {[80:100]}; data_nidles==0; pkt_nidles==1; data_size inside {8,16,32};})
    //     else $fatal("[RNDFAIL] gen[0] burst mode randomization failure!");
    //   // 同理配置gen[1]和gen[2]
    // endfunction
  endclass: chnl_burst_test

  // #########################################################################
  // 类名：chnl_fifo_full_test
  // 功能：FIFO满测试类（继承根测试类）
  // 作用：测试从机FIFO满（ready=0）时的传输行为，验证发起器的阻塞与恢复逻辑
  // 需求：持续发送数据，直到所有从机通道同时置位FIFO满（ready=0），然后停止测试
  // #########################################################################
  class chnl_fifo_full_test extends chnl_root_test;
    // 构造函数：调用父类构造函数，设置测试名称
    function new(string name = "chnl_fifo_full_test");
      super.new(name);
    endfunction
    
    // USER TODO：实现FIFO满测试逻辑
    // 实现思路：
    // 1. 重写run()函数：在启动生成器后，添加FIFO满检测逻辑
    // 2. 检测条件：所有通道的intf.ch_ready == 0（同时满）
    // 3. 检测到后，停止生成器并终止测试
    // 示例代码：
    // virtual task run();
    //   super.do_config();  // 继承配置（可修改为高吞吐模式，快速填满FIFO）
    //   fork
    //     agent[0].run(); agent[1].run(); agent[2].run();
    //     gen[0].run(); gen[1].run(); gen[2].run();
    //     begin // FIFO满检测线程
    //       wait(intf0.ch_ready == 0 && intf1.ch_ready == 0 && intf2.ch_ready == 0);
    //       $display("All channels FIFO full, stopping test...");
    //       $finish();
    //     end
    //   join
    // endtask
  endclass: chnl_fifo_full_test

endpackage