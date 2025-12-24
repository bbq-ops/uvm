/**
 * 文件名：chnl_pkg.sv
 * 功能：UVM通道（channel）验证组件包
 * 包含：通道事务项(chnl_trans)、驱动(chnl_driver)、临时生成器(chnl_generator)、监视器(chnl_monitor)、代理(chnl_agent)
 * 适用：基于UVM的数字电路验证，用于验证通道接口的数传功能
 */
package chnl_pkg;
  // 导入UVM核心包（包含UVM所有基类和方法）
  import uvm_pkg::*;
  // 包含UVM宏定义（如`uvm_object_utils、`uvm_info等）
  `include "uvm_macros.svh"

  // -----------------------------------------------------------------------------
  // 通道事务项（chnl_trans）：继承自uvm_sequence_item，是UVM中最小的事务单元
  // 作用：封装通道传输的所有数据和控制信息，用于组件间的事务传递
  // -----------------------------------------------------------------------------
  class chnl_trans extends uvm_sequence_item;
    // 随机成员变量：通道传输的核心数据和控制参数
    rand bit[31:0] data[];      // 动态数组：通道要传输的32位数据序列
    rand int ch_id;             // 通道ID：用于区分不同的通道（如0/1/2号通道）
    rand int pkt_id;            // 数据包ID：用于区分同一个通道的不同数据包
    rand int data_nidles;       // 数据间空闲周期数：两个数据之间的空闲clk数
    rand int pkt_nidles;        // 数据包间空闲周期数：两个数据包之间的空闲clk数
    bit rsp;                    // 响应标志：用于驱动向生成器返回事务处理完成的响应（非随机）

    // 约束块：限制随机变量的取值范围和关联关系（soft为软约束，可被重载）
    constraint cstr{
      soft data.size inside {[4:32]};  // 数据长度默认4~32个（soft：可被后续随机化重载）
      // 数据内容约束：按固定规则生成，便于后续校验（ch_id<<24：通道ID占高8位，pkt_id<<8：包ID占中8位，i：字节偏移）
      foreach(data[i]) data[i] == 'hC000_0000 + (this.ch_id<<24) + (this.pkt_id<<8) + i;
      soft ch_id == 0;                 // 默认通道ID为0
      soft pkt_id == 0;                // 默认数据包ID为0
      soft data_nidles inside {[0:2]}; // 数据间空闲周期默认0~2
      soft pkt_nidles inside {[1:10]}; // 数据包间空闲周期默认1~10
    };

    // UVM字段自动化宏：自动实现对象的拷贝、打印、比较、打包/解包等方法
    // UVM_ALL_ON：启用所有字段自动化功能
    `uvm_object_utils_begin(chnl_trans)
      `uvm_field_array_int(data, UVM_ALL_ON)    // 动态数组类型的字段注册
      `uvm_field_int(ch_id, UVM_ALL_ON)        // 整型字段注册
      `uvm_field_int(pkt_id, UVM_ALL_ON)
      `uvm_field_int(data_nidles, UVM_ALL_ON)
      `uvm_field_int(pkt_nidles, UVM_ALL_ON)
      `uvm_field_int(rsp, UVM_ALL_ON)
    `uvm_object_utils_end

    // 构造函数：初始化事务对象（继承自uvm_sequence_item的构造函数）
    // @param name：对象名称，默认"chnl_trans"
    function new (string name = "chnl_trans");
      super.new(name);  // 调用父类构造函数
    endfunction

    // NOTE:: field automation already implemented clone() method
    // 注释说明：字段自动化宏已经自动实现了clone()方法（深拷贝），无需手动编写
    // function chnl_trans clone();
    //   chnl_trans c = new();
    //   c.data = this.data;
    //   c.ch_id = this.ch_id;
    //   c.pkt_id = this.pkt_id;
    //   c.data_nidles = this.data_nidles;
    //   c.pkt_nidles = this.pkt_nidles;
    //   c.rsp = this.rsp;
    //   return c;
    // endfunction

    // NOTE:: field automation already implemented sprint() method
    // 注释说明：字段自动化宏已经自动实现了sprint()方法（格式化打印对象内容），无需手动编写
    // function string sprint();
    //   string s;
    //   s = {s, $sformatf("=======================================\n")};
    //   s = {s, $sformatf("chnl_trans object content is as below: \n")};
    //   foreach(data[i]) s = {s, $sformatf("data[%0d] = %8x \n", i, this.data[i])};
    //   s = {s, $sformatf("ch_id = %0d: \n", this.ch_id)};
    //   s = {s, $sformatf("pkt_id = %0d: \n", this.pkt_id)};
    //   s = {s, $sformatf("data_nidles = %0d: \n", this.data_nidles)};
    //   s = {s, $sformatf("pkt_nidles = %0d: \n", this.pkt_nidles)};
    //   s = {s, $sformatf("rsp = %0d: \n", this.rsp)};
    //   s = {s, $sformatf("=======================================\n")};
    //   return s;
    // endfunction
  endclass: chnl_trans
  
  // -----------------------------------------------------------------------------
  // 通道驱动（chnl_driver）：继承自uvm_driver #(chnl_trans)
  // 作用：接收事务项，将其转换为物理接口上的信号驱动（如valid、data、ready）
  // 模板参数：chnl_trans表示驱动处理的事务类型
  // -----------------------------------------------------------------------------
  class chnl_driver extends uvm_driver #(chnl_trans);
    local virtual chnl_intf intf;  // 本地虚接口：绑定到硬件的通道接口（local：仅本类可见）
    mailbox #(chnl_trans) req_mb;  // 请求邮箱：接收生成器发送的事务请求（mailbox：UVM中常用的进程间通信机制）
    mailbox #(chnl_trans) rsp_mb;  // 响应邮箱：向生成器返回事务处理完成的响应

    // UVM组件注册宏：将驱动类注册到UVM工厂，支持工厂创建
    `uvm_component_utils(chnl_driver)
  
    // 构造函数：初始化驱动组件
    // @param name：组件名称，默认"chnl_driver"
    // @param parent：父组件（UVM的树形结构）
    function new (string name = "chnl_driver", uvm_component parent);
      super.new(name, parent);  // 调用父类构造函数
    endfunction
  
    // 接口设置函数：将外部的虚接口绑定到驱动的本地接口
    // @param intf：外部传入的通道虚接口
    function void set_interface(virtual chnl_intf intf);
      if(intf == null)  // 校验接口是否为空，避免空指针错误
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;  // 绑定接口
    endfunction

    // UVM运行阶段（run_phase）：组件的核心执行逻辑，在reset后一直运行
    // @param phase：UVM的阶段对象（用于控制阶段跳转）
    task run_phase(uvm_phase phase);
      fork  // 并行执行复位处理和事务驱动（fork-join：两个任务同时运行，直到都结束）
       this.do_drive();  // 事务驱动任务：处理事务并驱动接口
       this.do_reset();  // 复位处理任务：响应复位信号，初始化接口
      join
    endtask

    // 复位处理任务：永久监控复位信号，复位时将接口信号置默认值
    task do_reset();
      forever begin  // 无限循环，持续监控复位
        @(negedge intf.rstn);  // 等待复位信号下降沿（rstn：低电平复位）
        intf.ch_valid <= 0;    // 复位时，数据有效信号置0
        intf.ch_data <= 0;     // 复位时，数据信号置0
      end
    endtask

    // 事务驱动任务：从请求邮箱获取事务，调用写接口方法处理，然后返回响应
    task do_drive();
      chnl_trans req, rsp;  // 声明请求和响应事务对象
      @(posedge intf.rstn); // 等待复位释放（rstn高电平）
      forever begin         // 无限循环，持续处理事务
        this.req_mb.get(req);  // 从请求邮箱中获取事务（阻塞：直到邮箱有数据）
        this.chnl_write(req);  // 调用写接口方法，将事务转换为信号驱动
        void'($cast(rsp, req.clone()));  // 克隆请求事务为响应事务（$cast：类型转换，void'：忽略返回值）
        rsp.rsp = 1;  // 设置响应标志为1，表示事务处理完成
        this.rsp_mb.put(rsp);  // 将响应事务放入响应邮箱，返回给生成器
      end
    endtask
  
    // 通道写操作任务：将事务中的数据逐位驱动到接口上，并处理空闲周期
    // @param t：要驱动的事务对象
    task chnl_write(input chnl_trans t);
      // 遍历事务中的每个数据，逐次驱动
      foreach(t.data[i]) begin
        @(posedge intf.clk);  // 等待时钟上升沿（同步时钟）
        intf.drv_ck.ch_valid <= 1;  // 置数据有效信号为1（drv_ck：驱动端的时钟块，用于同步信号）
        intf.drv_ck.ch_data <= t.data[i];  // 驱动数据到接口
        @(negedge intf.clk);  // 等待时钟下降沿
        wait(intf.ch_ready === 'b1);  // 等待接收端准备好（ch_ready：高电平表示准备好，阻塞）
        // 打印调试信息（UVM_HIGH：调试级别，仅在高verbosity时显示）
        `uvm_info(get_type_name(), $sformatf("sent data 'h%8x", t.data[i]), UVM_HIGH)
        // 处理数据间的空闲周期：调用空闲任务指定次数
        repeat(t.data_nidles) chnl_idle();
      end
      // 处理数据包间的空闲周期：调用空闲任务指定次数
      repeat(t.pkt_nidles) chnl_idle();
    endtask
    
    // 通道空闲任务：将接口信号置为空闲状态（valid=0，data=0）
    task chnl_idle();
      @(posedge intf.clk);  // 等待时钟上升沿
      intf.drv_ck.ch_valid <= 0;  // 数据有效信号置0
      intf.drv_ck.ch_data <= 0;   // 数据信号置0
    endtask
  endclass: chnl_driver
  
  // -----------------------------------------------------------------------------
  // 通道生成器（chnl_generator）：继承自uvm_component
  // 作用：临时的事务生成组件（后续会被UVM的sequence + sequencer替代）
  //      生成随机的事务对象，通过邮箱发送给驱动，同时接收驱动的响应
  // -----------------------------------------------------------------------------
  class chnl_generator extends uvm_component;
    // 随机配置参数：用于控制事务的生成规则（-1表示使用事务自身的默认约束）
    rand int pkt_id = 0;        // 初始数据包ID
    rand int ch_id = -1;        // 通道ID（-1：事务随机化时使用自身的soft约束）
    rand int data_nidles = -1;  // 数据间空闲周期（-1：事务随机化时使用自身的soft约束）
    rand int pkt_nidles = -1;   // 数据包间空闲周期（-1：事务随机化时使用自身的soft约束）
    rand int data_size = -1;    // 数据长度（-1：事务随机化时使用自身的soft约束）
    rand int ntrans = 10;       // 要生成的事务总数，默认10个

    mailbox #(chnl_trans) req_mb;  // 请求邮箱：向驱动发送事务请求
    mailbox #(chnl_trans) rsp_mb;  // 响应邮箱：接收驱动返回的事务响应

    // 约束块：限制配置参数的默认值（soft：可被重载）
    constraint cstr{
      soft ch_id == -1;
      soft pkt_id == 0;
      soft data_size == -1;
      soft data_nidles == -1;
      soft pkt_nidles == -1;
      soft ntrans == 10;
    }

    // UVM字段自动化宏：注册配置参数，支持打印和随机化
    `uvm_component_utils_begin(chnl_generator)
      `uvm_field_int(pkt_id, UVM_ALL_ON)
      `uvm_field_int(ch_id, UVM_ALL_ON)
      `uvm_field_int(data_nidles, UVM_ALL_ON)
      `uvm_field_int(pkt_nidles, UVM_ALL_ON)
      `uvm_field_int(data_size, UVM_ALL_ON)
      `uvm_field_int(ntrans, UVM_ALL_ON)
    `uvm_component_utils_end

    // 构造函数：初始化生成器组件，并创建邮箱（mailbox默认大小无限制）
    function new (string name = "chnl_generator", uvm_component parent);
      super.new(name, parent);
      this.req_mb = new();  // 初始化请求邮箱
      this.rsp_mb = new();  // 初始化响应邮箱
    endfunction

    // 启动生成器：生成指定数量的事务
    task start();
      repeat(ntrans) send_trans();  // 循环ntrans次，每次发送一个事务
    endtask

    // 发送单个事务：创建并随机化事务，发送给驱动，接收响应并校验
    task send_trans();
      chnl_trans req, rsp;  // 声明请求和响应事务对象
      // 使用UVM工厂创建事务对象（推荐方式，支持工厂重载）
      req = chnl_trans::type_id::create("req");;
      // 事务随机化：使用with约束重载事务的默认约束（根据生成器的配置参数）
      // 逻辑：如果生成器的参数>=0，则事务的对应参数等于该值；否则使用事务自身的soft约束
      assert(req.randomize with {local::ch_id >= 0 -> ch_id == local::ch_id; 
                                 local::pkt_id >= 0 -> pkt_id == local::pkt_id;
                                 local::data_nidles >= 0 -> data_nidles == local::data_nidles;
                                 local::pkt_nidles >= 0 -> pkt_nidles == local::pkt_nidles;
                                 local::data_size >0 -> data.size() == local::data_size; 
                               })
        else $fatal("[RNDFAIL] channel packet randomization failure!");  // 随机化失败则终止仿真
      this.pkt_id++;  // 数据包ID自增，用于区分后续的数据包
      // 打印事务内容（UVM_HIGH：调试级别）
      `uvm_info(get_type_name(), req.sprint(), UVM_HIGH)
      this.req_mb.put(req);  // 将事务放入请求邮箱，发送给驱动
      this.rsp_mb.get(rsp);  // 从响应邮箱获取驱动的响应（阻塞）
      // 打印响应内容（UVM_HIGH：调试级别）
      `uvm_info(get_type_name(), rsp.sprint(), UVM_HIGH)
      // 校验响应标志：如果rsp不为1，则报错
      assert(rsp.rsp)
        else $error("[RSPERR] %0t error response received!", $time);
    endtask

    // 自定义sprint方法：格式化打印生成器的配置参数（重载父类的sprint方法）
    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("chnl_generator object content is as below: \n")};
      s = {s, super.sprint()};  // 调用父类的sprint方法，打印注册的字段
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction

    // 随机化后回调函数：在生成器的配置参数随机化后，打印配置信息
    function void post_randomize();
      string s;
      s = {"AFTER RANDOMIZATION \n", this.sprint()};
      `uvm_info(get_type_name(), s, UVM_HIGH)
    endfunction
  endclass: chnl_generator

  // -----------------------------------------------------------------------------
  // 监视器数据类型（mon_data_t）：packed结构体
  // 作用：封装监视器收集到的接口数据（包含数据和通道ID，ID字段暂未使用）
  // packed：结构体按位打包，占用连续的位宽（这里32+2=34位）
  // -----------------------------------------------------------------------------
  typedef struct packed {
    bit[31:0] data;  // 收集到的32位数据
    bit[1:0] id;     // 通道ID（暂未赋值，预留字段）
  } mon_data_t;

  // -----------------------------------------------------------------------------
  // 通道监视器（chnl_monitor）：继承自uvm_monitor
  // 作用：被动监视物理接口上的信号，收集有效数据并发送给后续组件（如记分板）
  // 特性：被动组件，不驱动任何信号，仅观察
  // -----------------------------------------------------------------------------
  class chnl_monitor extends uvm_monitor;
    local virtual chnl_intf intf;  // 本地虚接口：绑定到硬件的通道接口
    mailbox #(mon_data_t) mon_mb;  // 监视器邮箱：向后续组件发送收集到的数据

    // UVM组件注册宏：将监视器类注册到UVM工厂
    `uvm_component_utils(chnl_monitor)

    // 构造函数：初始化监视器组件
    function new(string name="chnl_monitor", uvm_component parent);
      super.new(name, parent);
    endfunction

    // 接口设置函数：将外部的虚接口绑定到监视器的本地接口
    function void set_interface(virtual chnl_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction

    // UVM运行阶段：调用监视器的核心任务
    task run_phase(uvm_phase phase);
      this.mon_trans();  // 数据收集任务
    endtask

    // 数据收集任务：永久监控接口，收集有效数据（valid和ready同时为1时）
    task mon_trans();
      mon_data_t m;  // 声明监视器数据对象
      forever begin  // 无限循环，持续监控
        // 等待时钟上升沿，且满足条件：valid=1且ready=1（iff：条件满足时才触发）
        // mon_ck：监视器端的时钟块，用于同步信号采样
        @(posedge intf.clk iff (intf.mon_ck.ch_valid==='b1 && intf.mon_ck.ch_ready==='b1));
        m.data = intf.mon_ck.ch_data;  // 采样接口上的数据
        mon_mb.put(m);  // 将数据放入监视器邮箱，发送给后续组件
        // 打印调试信息（UVM_HIGH：调试级别）
        `uvm_info(get_type_name(), $sformatf("monitored channel data 'h%8x", m.data), UVM_HIGH)
      end
    endtask
  endclass: chnl_monitor
  
  // -----------------------------------------------------------------------------
  // 通道代理（chnl_agent）：继承自uvm_agent
  // 作用：封装驱动、监视器等子组件，提供统一的接口和管理（UVM的模块化设计）
  // 特性：作为顶层组件的子组件，简化组件的实例化和接口传递
  // -----------------------------------------------------------------------------
  class chnl_agent extends uvm_agent;
    chnl_driver driver;    // 驱动组件实例
    chnl_monitor monitor;  // 监视器组件实例
    local virtual chnl_intf vif;  // 本地虚接口：绑定到硬件的通道接口

    // UVM组件注册宏：将代理类注册到UVM工厂
    `uvm_component_utils(chnl_agent)

    // 构造函数：初始化代理组件
    function new(string name = "chnl_agent", uvm_component parent);
      super.new(name, parent);
    endfunction

    // UVM构建阶段（build_phase）：创建子组件（驱动和监视器）
    // 注：UVM的phase机制会自动按顺序执行各阶段，build_phase用于组件实例化
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);  // 调用父类的build_phase
      // 使用UVM工厂创建子组件（推荐方式）
      driver = chnl_driver::type_id::create("driver", this);
      monitor = chnl_monitor::type_id::create("monitor", this);
    endfunction

    // 接口设置函数：将外部的虚接口传递给驱动和监视器
    function void set_interface(virtual chnl_intf vif);
      this.vif = vif;          // 绑定本地接口
      driver.set_interface(vif);  // 传递接口给驱动
      monitor.set_interface(vif); // 传递接口给监视器
    endfunction

    // UVM运行阶段：原注释说明无需手动调用子组件的run方法（UVM的phase机制会自动调用）
    task run_phase(uvm_phase phase);
      // NOTE:: No more needed to call run manually
      // fork
      //   driver.run();
      //   monitor.run();
      // join
    endtask
  endclass: chnl_agent

endpackage