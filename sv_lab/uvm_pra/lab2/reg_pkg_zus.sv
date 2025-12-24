// 引入寄存器相关的参数定义文件（包含`WRITE、`READ、`IDLE、各类寄存器地址等宏定义）
`include "param_def.v"

/**
 * 文件名：reg_pkg.sv
 * 功能：UVM寄存器（reg）验证组件包
 * 包含：寄存器事务项(reg_trans)、驱动(reg_driver)、临时生成器(reg_generator)、监视器(reg_monitor)、代理(reg_agent)
 * 适用：基于UVM的数字电路验证，用于验证寄存器接口的读写/空闲功能
 */
package reg_pkg;
  // 导入UVM核心包（包含UVM所有基类和方法）
  import uvm_pkg::*;
  // 包含UVM宏定义（如`uvm_object_utils、`uvm_info等）
  `include "uvm_macros.svh"

  // -----------------------------------------------------------------------------
  // 寄存器事务项（reg_trans）：继承自uvm_sequence_item，是UVM中最小的事务单元
  // 作用：封装寄存器操作的所有数据和控制信息（地址、命令、数据、响应），用于组件间的事务传递
  // -----------------------------------------------------------------------------
  class reg_trans extends uvm_sequence_item;
    // 随机成员变量：寄存器操作的核心参数
    rand bit[7:0] addr;    // 寄存器地址（8位）
    rand bit[1:0] cmd;     // 寄存器操作命令（2位：对应`WRITE/`READ/`IDLE，由param_def.v定义）
    rand bit[31:0] data;   // 寄存器读写数据（32位）
    bit rsp;               // 响应标志：用于驱动向生成器返回事务处理完成的响应（非随机）

    // 约束块：限制随机变量的取值范围和关联关系（soft为软约束，可被重载）
    constraint cstr {
      // 约束1：命令默认只能是`WRITE（写）、`READ（读）、`IDLE（空闲）（由param_def.v定义）
      soft cmd inside {`WRITE, `READ, `IDLE};
      // 约束2：地址默认只能是预定义的寄存器地址（如SLV0_RW_ADDR：0号从机可读写地址，由param_def.v定义）
      soft addr inside {`SLV0_RW_ADDR, `SLV1_RW_ADDR, `SLV2_RW_ADDR, `SLV0_R_ADDR, `SLV1_R_ADDR, `SLV2_R_ADDR};
      // 约束3：如果地址高4位（bit7~4）为0 且 命令是写操作，那么数据的高26位（bit31~6）默认置0
      addr[7:4]==0 && cmd==`WRITE -> soft data[31:6]==0;
      // 约束4：地址的高3位（bit7~5）默认置0（限制地址范围）
      soft addr[7:5]==0;
      // 约束5：如果地址的第4位为1（bit4==1），那么命令默认只能是读操作（对应只读寄存器地址）
      addr[4]==1 -> soft cmd == `READ;
    };

    // UVM字段自动化宏：自动实现对象的拷贝、打印、比较、打包/解包等方法
    // UVM_ALL_ON：启用所有字段自动化功能
    `uvm_object_utils_begin(reg_trans)
      `uvm_field_int(addr, UVM_ALL_ON)    // 8位地址字段注册（整型，用uvm_field_int）
      `uvm_field_int(cmd, UVM_ALL_ON)     // 2位命令字段注册（整型，用uvm_field_int）
      `uvm_field_int(data, UVM_ALL_ON)    // 32位数据字段注册（整型，用uvm_field_int）
      `uvm_field_int(rsp, UVM_ALL_ON)     // 1位响应标志注册（bit类型，仍用uvm_field_int）
    `uvm_object_utils_end

    // 构造函数：初始化事务对象（继承自uvm_sequence_item的构造函数）
    // @param name：对象名称，默认"reg_trans"
    function new (string name = "reg_trans");
      super.new(name);  // 调用父类构造函数
    endfunction

    // NOTE:: field automation already implemented clone() method
    // 注释说明：字段自动化宏已经自动实现了clone()方法（深拷贝），无需手动编写
    // function reg_trans clone();
    //   reg_trans c = new();
    //   c.addr = this.addr;
    //   c.cmd = this.cmd;
    //   c.data = this.data;
    //   c.rsp = this.rsp;
    //   return c;
    // endfunction

    // NOTE:: field automation already implemented clone() method
    // 注释说明：字段自动化宏已经自动实现了sprint()方法（格式化打印对象内容），无需手动编写
    // function string sprint();
    //   string s;
    //   s = {s, $sformatf("=======================================\n")};
    //   s = {s, $sformatf("reg_trans object content is as below: \n")};
    //   s = {s, $sformatf("addr = %2x: \n", this.addr)};
    //   s = {s, $sformatf("cmd = %2b: \n", this.cmd)};
    //   s = {s, $sformatf("data = %8x: \n", this.data)};
    //   s = {s, $sformatf("rsp = %0d: \n", this.rsp)};
    //   s = {s, $sformatf("=======================================\n")};
    //   return s;
    // endfunction
  endclass

  // -----------------------------------------------------------------------------
  // 寄存器驱动（reg_driver）：继承自uvm_driver #(reg_trans)
  // 作用：接收事务项，将其转换为物理接口上的信号驱动（如cmd_addr、cmd、cmd_data_m2s）
  // 模板参数：reg_trans表示驱动处理的事务类型
  // -----------------------------------------------------------------------------
  class reg_driver extends uvm_driver #(reg_trans);
    local virtual reg_intf intf;  // 本地虚接口：绑定到硬件的寄存器接口（local：仅本类可见）
    mailbox #(reg_trans) req_mb;  // 请求邮箱：接收生成器发送的事务请求（mailbox：UVM中常用的进程间通信机制）
    mailbox #(reg_trans) rsp_mb;  // 响应邮箱：向生成器返回事务处理完成的响应

    // UVM组件注册宏：将驱动类注册到UVM工厂，支持工厂创建
    `uvm_component_utils(reg_driver)
  
    // 构造函数：初始化驱动组件
    // @param name：组件名称，默认"reg_driver"
    // @param parent：父组件（UVM的树形结构）
    function new (string name = "reg_driver", uvm_component parent);
      super.new(name, parent);  // 调用父类构造函数
    endfunction
  
    // 接口设置函数：将外部的虚接口绑定到驱动的本地接口
    // @param intf：外部传入的寄存器虚接口
    function void set_interface(virtual reg_intf intf);
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
        intf.cmd_addr <= 0;        // 复位时，寄存器地址置0
        intf.cmd <= `IDLE;         // 复位时，命令置为空闲（`IDLE由param_def.v定义）
        intf.cmd_data_m2s <= 0;    // 复位时，主机到从机的数据置0（m2s：master to slave）
      end
    endtask

    // 事务驱动任务：从请求邮箱获取事务，调用寄存器操作方法处理，然后返回响应
    task do_drive();
      reg_trans req, rsp;  // 声明请求和响应事务对象
      @(posedge intf.rstn); // 等待复位释放（rstn高电平）
      forever begin         // 无限循环，持续处理事务
        this.req_mb.get(req);  // 从请求邮箱中获取事务（阻塞：直到邮箱有数据）
        this.reg_write(req);   // 调用寄存器操作方法，将事务转换为信号驱动
        void'($cast(rsp, req.clone()));  // 克隆请求事务为响应事务（$cast：类型转换，void'：忽略返回值）
        rsp.rsp = 1;  // 设置响应标志为1，表示事务处理完成
        this.rsp_mb.put(rsp);  // 将响应事务放入响应邮箱，返回给生成器
      end
    endtask
  
    // 寄存器操作任务：根据事务的命令（写/读/空闲），驱动对应的接口信号
    // @param t：要驱动的事务对象
    task reg_write(reg_trans t);
      // 等待时钟上升沿，且复位信号有效（rstn高电平），确保操作在复位后执行
      @(posedge intf.clk iff intf.rstn);
      // 根据命令类型分支处理
      case(t.cmd)
        // 写操作：驱动地址、写命令、写数据到接口
        `WRITE: begin 
                  intf.drv_ck.cmd_addr <= t.addr;          // 驱动寄存器地址（drv_ck：驱动端时钟块，同步信号）
                  intf.drv_ck.cmd <= t.cmd;                // 驱动写命令
                  intf.drv_ck.cmd_data_m2s <= t.data;      // 驱动写数据（主机到从机）
                end
        // 读操作：驱动地址、读命令，然后采样从机返回的数据（s2m：slave to master）
        `READ:  begin 
                  intf.drv_ck.cmd_addr <= t.addr;          // 驱动寄存器地址
                  intf.drv_ck.cmd <= t.cmd;                // 驱动读命令
                  repeat(2) @(negedge intf.clk);           // 等待2个时钟下降沿，让从机返回数据
                  t.data = intf.cmd_data_s2m;              // 采样从机返回的读数据，更新事务的data字段
                end
        // 空闲操作：调用空闲任务，将接口信号置为空闲状态
        `IDLE:  begin 
                  this.reg_idle(); 
                end
        // 默认情况：命令非法，打印错误信息
        default: $error("command %b is illegal", t.cmd);
      endcase
      // 打印调试信息（UVM_HIGH：调试级别，仅在高verbosity时显示）
      `uvm_info(get_type_name(), $sformatf("sent addr %2x, cmd %2b, data %8x", t.addr, t.cmd, t.data), UVM_HIGH)
    endtask
    
    // 寄存器空闲任务：将接口信号置为空闲状态（地址0、命令空闲、数据0）
    task reg_idle();
      @(posedge intf.clk);  // 等待时钟上升沿
      intf.drv_ck.cmd_addr <= 0;        // 地址置0
      intf.drv_ck.cmd <= `IDLE;         // 命令置为空闲
      intf.drv_ck.cmd_data_m2s <= 0;    // 主机到从机的数据置0
    endtask
  endclass

  // -----------------------------------------------------------------------------
  // 寄存器生成器（reg_generator）：继承自uvm_component
  // 作用：临时的事务生成组件（后续会被UVM的sequence + sequencer替代）
  //      生成随机的寄存器事务对象，通过邮箱发送给驱动，同时接收驱动的响应
  // -----------------------------------------------------------------------------
  class reg_generator extends uvm_component;
    // 随机配置参数：用于控制事务的生成规则（-1表示使用事务自身的默认约束）
    rand bit[7:0] addr = -1;    // 寄存器地址（-1：事务随机化时使用自身的soft约束）
    rand bit[1:0] cmd = -1;     // 寄存器命令（-1：事务随机化时使用自身的soft约束）
    rand bit[31:0] data = -1;   // 寄存器数据（-1：事务随机化时使用自身的soft约束）

    mailbox #(reg_trans) req_mb;  // 请求邮箱：向驱动发送事务请求
    mailbox #(reg_trans) rsp_mb;  // 响应邮箱：接收驱动返回的事务响应

    // 约束块：限制配置参数的默认值（soft：可被重载）
    constraint cstr{
      soft addr == -1;   // 默认值-1，表示不强制事务的addr字段
      soft cmd == -1;    // 默认值-1，表示不强制事务的cmd字段
      soft data == -1;   // 默认值-1，表示不强制事务的data字段
    }

    // UVM字段自动化宏：注册配置参数，支持打印和随机化
    `uvm_component_utils_begin(reg_generator)
      `uvm_field_int(addr, UVM_ALL_ON)
      `uvm_field_int(cmd, UVM_ALL_ON)
      `uvm_field_int(data, UVM_ALL_ON)
    `uvm_component_utils_end

    // 构造函数：初始化生成器组件，并创建邮箱（mailbox默认大小无限制）
    function new (string name = "reg_generator", uvm_component parent);
      super.new(name, parent);
      this.req_mb = new();  // 初始化请求邮箱
      this.rsp_mb = new();  // 初始化响应邮箱
    endfunction

    // 启动生成器：生成一个事务（当前版本仅发送一次，可扩展为循环发送）
    task start();
      send_trans();  // 调用发送事务任务
    endtask

    // 发送单个事务：创建并随机化事务，发送给驱动，接收响应并校验/更新数据
    task send_trans();
      reg_trans req, rsp;  // 声明请求和响应事务对象
      req = new();  // 创建事务对象（注：推荐使用UVM工厂创建：reg_trans::type_id::create("req")）
      // 事务随机化：使用with约束重载事务的默认约束（根据生成器的配置参数）
      // 逻辑：如果生成器的参数>=0，则事务的对应参数等于该值；否则使用事务自身的soft约束
      assert(req.randomize with {local::addr >= 0 -> addr == local::addr;
                                 local::cmd >= 0 -> cmd == local::cmd;
                                 local::data >= 0 -> data == local::data;
                               })
        else $fatal("[RNDFAIL] register packet randomization failure!");  // 随机化失败则终止仿真
      // 打印事务内容（UVM_HIGH：调试级别）
      `uvm_info(get_type_name(), req.sprint(), UVM_HIGH)
      this.req_mb.put(req);  // 将事务放入请求邮箱，发送给驱动
      this.rsp_mb.get(rsp);  // 从响应邮箱获取驱动的响应（阻塞）
      // 打印响应内容（UVM_HIGH：调试级别）
      `uvm_info(get_type_name(), rsp.sprint(), UVM_HIGH)
      // 如果是读操作，将响应的data更新到生成器的data参数中（记录读回的数据）
      if(req.cmd == `READ) 
        this.data = rsp.data;
      // 校验响应标志：如果rsp不为1，则报错
      assert(rsp.rsp)
        else $error("[RSPERR] %0t error response received!", $time);
    endtask

    // 自定义sprint方法：格式化打印生成器的配置参数（重载父类的sprint方法）
    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("reg_generator object content is as below: \n")};
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
  endclass

  // -----------------------------------------------------------------------------
  // 寄存器监视器（reg_monitor）：继承自uvm_monitor
  // 作用：被动监视物理接口上的信号，收集寄存器操作的有效数据并发送给后续组件（如记分板）
  // 特性：被动组件，不驱动任何信号，仅观察
  // -----------------------------------------------------------------------------
  class reg_monitor extends uvm_monitor;
    local virtual reg_intf intf;  // 本地虚接口：绑定到硬件的寄存器接口
    mailbox #(reg_trans) mon_mb;  // 监视器邮箱：向后续组件（如记分板）发送收集到的事务

    // UVM组件注册宏：将监视器类注册到UVM工厂
    `uvm_component_utils(reg_monitor)

    // 构造函数：初始化监视器组件
    function new(string name="reg_monitor", uvm_component parent);
      super.new(name, parent);
    endfunction

    // 接口设置函数：将外部的虚接口绑定到监视器的本地接口
    function void set_interface(virtual reg_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction

    // UVM运行阶段：调用监视器的核心任务
    task run_phase(uvm_phase phase);
      this.mon_trans();  // 数据收集任务
    endtask

    // 数据收集任务：永久监控接口，收集寄存器操作的有效数据（命令非空闲时）
    task mon_trans();
      reg_trans m;  // 声明监视器的事务对象
      forever begin  // 无限循环，持续监控
        // 等待时钟上升沿，且满足条件：复位有效（rstn高）且命令非空闲（cmd != `IDLE）
        // mon_ck：监视器端的时钟块，用于同步信号采样
        @(posedge intf.clk iff (intf.rstn && intf.mon_ck.cmd != `IDLE));
        m = new();  // 创建新的事务对象，存储收集到的数据（注：推荐使用UVM工厂创建）
        m.addr = intf.mon_ck.cmd_addr;  // 采样寄存器地址
        m.cmd = intf.mon_ck.cmd;        // 采样寄存器命令
        // 根据命令类型采样数据
        if(intf.mon_ck.cmd == `WRITE) begin
          m.data = intf.mon_ck.cmd_data_m2s;  // 写操作：采样主机到从机的数据
        end
        else if(intf.mon_ck.cmd == `READ) begin
          @(posedge intf.clk);                // 读操作：等待一个时钟，采样从机返回的数据
          m.data = intf.mon_ck.cmd_data_s2m;  // 采样从机到主机的数据
        end
        mon_mb.put(m);  // 将收集到的事务放入监视器邮箱，发送给后续组件
        // 打印调试信息（UVM_HIGH：调试级别）
        `uvm_info(get_type_name(), $sformatf("monitored addr %2x, cmd %2b, data %8x", m.addr, m.cmd, m.data), UVM_HIGH)
      endtask
    endtask
  endclass: reg_monitor

  // -----------------------------------------------------------------------------
  // 寄存器代理（reg_agent）：继承自uvm_agent
  // 作用：封装驱动、监视器等子组件，提供统一的接口和管理（UVM的模块化设计）
  // 特性：作为顶层组件的子组件，简化组件的实例化和接口传递
  // -----------------------------------------------------------------------------
  class reg_agent extends uvm_agent;
    reg_driver driver;    // 驱动组件实例
    reg_monitor monitor;  // 监视器组件实例
    local virtual reg_intf vif;  // 本地虚接口：绑定到硬件的寄存器接口

    // UVM组件注册宏：将代理类注册到UVM工厂
    `uvm_component_utils(reg_agent)

    // 构造函数：初始化代理组件
    function new(string name = "reg_agent", uvm_component parent);
      super.new(name, parent);
    endfunction

    // UVM构建阶段（build_phase）：创建子组件（驱动和监视器）
    // 注：UVM的phase机制会自动按顺序执行各阶段，build_phase用于组件实例化
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);  // 调用父类的build_phase
      // 使用UVM工厂创建子组件（推荐方式，支持工厂重载）
      driver = reg_driver::type_id::create("driver", this);
      monitor = reg_monitor::type_id::create("monitor", this);
    endfunction

    // 接口设置函数：将外部的虚接口传递给驱动和监视器
    function void set_interface(virtual reg_intf vif);
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
  endclass

endpackage