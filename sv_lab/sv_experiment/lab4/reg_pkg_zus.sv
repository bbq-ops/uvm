`include "param_def.v"  // 引入外部参数定义文件，包含寄存器操作命令（如`WRITE、`READ、`IDLE）和地址宏（如`SLV0_RW_ADDR等）

package reg_pkg;  // 定义寄存器验证组件包，封装所有验证相关类，便于重用和管理

  // 寄存器事务类：封装寄存器操作的核心信息，作为验证组件间数据传递的载体
  class reg_trans;
    rand bit[7:0] addr;  // 8位寄存器地址，支持随机化
    rand bit[1:0] cmd;   // 2位操作命令（对应`WRITE/`READ/`IDLE），支持随机化
    rand bit[31:0] data; // 32位数据（写操作时为写入值，读操作时为返回值），支持随机化
    bit rsp;             // 响应标志（1表示操作完成且有效）

    // 约束块：限制随机化范围，确保生成的事务符合寄存器协议规范
    constraint cstr {
      soft cmd inside {`WRITE, `READ, `IDLE};  // 软约束：命令默认只能是预定义的合法值（可被覆盖）
      // 软约束：地址默认只能是预定义的从机地址（读写地址）（可被覆盖）
      soft addr inside {`SLV0_RW_ADDR, `SLV1_RW_ADDR, `SLV2_RW_ADDR, `SLV0_R_ADDR, `SLV1_R_ADDR, `SLV2_R_ADDR};
      // 条件约束：若地址高4位为0且命令为写操作，则数据高26位（31:6）必须为0（特定协议要求）
      addr[7:4]==0 && cmd==`WRITE -> soft data[31:6]==0;
      soft addr[7:5]==0;  // 软约束：地址高3位默认为0（可被覆盖）
      addr[4]==1 -> soft cmd == `READ;  // 条件约束：若地址第4位为1（可能为只读地址），命令默认为读（可被覆盖）
    };

    // 克隆函数：创建当前事务的深拷贝，避免组件间引用传递导致的数据混乱
    function reg_trans clone();
      reg_trans c = new();  // 实例化新事务对象
      // 复制所有成员变量值
      c.addr = this.addr;
      c.cmd = this.cmd;
      c.data = this.data;
      c.rsp = this.rsp;
      return c;  // 返回拷贝后的事务
    endfunction

    // 打印函数：格式化输出事务信息，用于调试和日志记录
    function string sprint();
      string s;  // 用于拼接字符串
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("reg_trans object content is as below: \n")};
      s = {s, $sformatf("addr = %2x: \n", this.addr)};  // 打印地址（十六进制）
      s = {s, $sformatf("cmd = %2b: \n", this.cmd)};    // 打印命令（二进制）
      s = {s, $sformatf("data = %8x: \n", this.data)};  // 打印数据（十六进制）
      s = {s, $sformatf("rsp = %0d: \n", this.rsp)};    // 打印响应标志（十进制）
      s = {s, $sformatf("=======================================\n")};
      return s;  // 返回拼接后的字符串
    endfunction
  endclass

  // 寄存器驱动类：将事务转换为接口信号，驱动到被测设计（DUT），并处理复位逻辑
  class reg_driver;
    local string name;  // 驱动实例名称（用于区分不同驱动，便于调试）
    local virtual reg_intf intf;  // 虚拟接口句柄（连接DUT的物理接口，用于信号驱动）
    mailbox #(reg_trans) req_mb;  // 请求邮箱：接收来自生成器的事务
    mailbox #(reg_trans) rsp_mb;  // 响应邮箱：向生成器返回处理后的事务（含响应）

    // 构造函数：初始化驱动名称
    function new(string name = "reg_driver");
      this.name = name;
    endfunction
  
    // 设置接口函数：绑定虚拟接口，若接口为空则报错（确保驱动能正常访问接口）
    function void set_interface(virtual reg_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;  // 绑定接口
    endfunction

    // 运行任务：启动驱动核心逻辑，并发执行事务驱动和复位处理
    task run();
      fork
        this.do_drive();  // 处理事务驱动
        this.do_reset();  // 处理复位逻辑
      join
    endtask

    // 复位处理任务：复位期间（rstn为低）将接口信号置为初始状态
    task do_reset();
      forever begin
        @(negedge intf.rstn);  // 等待复位信号下降沿（复位开始）
        // 复位时信号清零，命令置为IDLE
        intf.cmd_addr <= 0;
        intf.cmd <= `IDLE;
        intf.cmd_data_m2s <= 0;  // m2s：master to slave（主到从数据）
      end
    endtask

    // 事务驱动任务：从请求邮箱获取事务，执行寄存器操作，并返回响应
    task do_drive();
      reg_trans req, rsp;  // 请求事务和响应事务
      @(posedge intf.rstn);  // 等待复位释放（rstn为高）
      forever begin
        this.req_mb.get(req);  // 从邮箱获取请求事务
        this.reg_write(req);   // 执行寄存器操作（写/读/空闲）
        rsp = req.clone();     // 克隆请求事务作为响应
        rsp.rsp = 1;           // 标记响应有效
        this.rsp_mb.put(rsp);  // 将响应放入响应邮箱
      end
    endtask
  
    // 寄存器操作任务：根据事务命令驱动接口信号（区分写/读/空闲操作）
    task reg_write(reg_trans t);
      @(posedge intf.clk iff intf.rstn);  // 等待时钟上升沿，且复位已释放
      case(t.cmd)
        `WRITE: begin  // 写操作：驱动地址、写命令和数据到接口
                  intf.drv_ck.cmd_addr <= t.addr;  // drv_ck：驱动时钟块（同步驱动信号）
                  intf.drv_ck.cmd <= t.cmd;
                  intf.drv_ck.cmd_data_m2s <= t.data;
                end
        `READ:  begin  // 读操作：驱动地址和读命令，等待从机返回数据
                  intf.drv_ck.cmd_addr <= t.addr;
                  intf.drv_ck.cmd <= t.cmd;
                  repeat(2) @(negedge intf.clk);  // 等待2个时钟下降沿（等待从机数据返回）
                  t.data = intf.cmd_data_s2m;  // s2m：slave to master（从到主数据，即读取结果）
                end
        `IDLE:  begin  // 空闲操作：将接口置为空闲状态
                  this.reg_idle();
                end
        default: $error("command %b is illegal", t.cmd);  // 非法命令报错
      endcase
      // 打印驱动信息（时间、名称、地址、命令、数据）
      $display("%0t reg driver [%s] sent addr %2x, cmd %2b, data %8x", $time, name, t.addr, t.cmd, t.data);
    endtask
    
    // 空闲任务：将接口信号置为空闲状态（地址、数据清零，命令置为IDLE）
    task reg_idle();
      @(posedge intf.clk);  // 时钟上升沿同步
      intf.drv_ck.cmd_addr <= 0;
      intf.drv_ck.cmd <= `IDLE;
      intf.drv_ck.cmd_data_m2s <= 0;
    endtask
  endclass

  // 寄存器生成器类：随机生成符合协议的事务，发送给驱动并接收响应
  class reg_generator;
    rand bit[7:0] addr = -1;  // 地址约束变量（-1表示不约束，由事务自主随机）
    rand bit[1:0] cmd = -1;   // 命令约束变量（-1表示不约束）
    rand bit[31:0] data = -1; // 数据约束变量（-1表示不约束）

    mailbox #(reg_trans) req_mb;  // 请求邮箱：发送事务到驱动
    mailbox #(reg_trans) rsp_mb;  // 响应邮箱：接收驱动返回的响应
    reg_trans reg_req[$];  // 事务队列（存储生成的请求事务，可选用于后续处理）

    // 约束块：控制生成器对事务的约束（默认不干预事务随机化）
    constraint cstr{
      soft addr == -1;  // 软约束：默认addr为-1（不约束事务的addr）
      soft cmd == -1;   // 软约束：默认cmd为-1（不约束事务的cmd）
      soft data == -1;  // 软约束：默认data为-1（不约束事务的data）
    }

    // 构造函数：初始化请求和响应邮箱
    function new();
      this.req_mb = new();
      this.rsp_mb = new();
    endfunction

    // 启动任务：开始生成并发送事务
    task start();
      send_trans();  // 调用事务发送方法
    endtask

    // 事务发送任务：生成随机事务，发送给驱动，等待并处理响应
    task send_trans();
      reg_trans req, rsp;  // 请求和响应事务
      req = new();  // 实例化新事务
      // 随机化事务：若生成器变量>=0，则事务对应字段强制等于生成器变量（否则事务自主随机）
      assert(req.randomize with {local::addr >= 0 -> addr == local::addr;
                                 local::cmd >= 0 -> cmd == local::cmd;
                                 local::data >= 0 -> data == local::data;
                               })
        else $fatal("[RNDFAIL] register packet randomization failure!");  // 随机化失败则终止仿真
      $display(req.sprint());  // 打印生成的事务信息
      this.req_mb.put(req);    // 将事务放入请求邮箱（发送给驱动）
      this.rsp_mb.get(rsp);    // 从响应邮箱获取驱动返回的响应
      $display(rsp.sprint());  // 打印响应事务信息
      if(req.cmd == `READ) 
        this.data = rsp.data;  // 若为读操作，更新生成器的data为读取结果
      assert(rsp.rsp)  // 检查响应是否有效，无效则报错
        else $error("[RSPERR] %0t error response received!", $time);
    endtask

    // 打印函数：输出生成器当前状态（地址、命令、数据）
    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("reg_generator object content is as below: \n")};
      s = {s, $sformatf("addr = %2x: \n", this.addr)};
      s = {s, $sformatf("cmd = %2b: \n", this.cmd)};
      s = {s, $sformatf("data = %8x: \n", this.data)};
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction

    // 随机化后回调函数：随机化完成后打印生成器状态（用于调试）
    function void post_randomize();
      string s;
      s = {"AFTER RANDOMIZATION \n", this.sprint()};
      $display(s);
    endfunction
  endclass

  // 寄存器监视器类：从接口采集信号，还原为事务并发送给后续验证组件（如Checker/Scoreboard）
  class reg_monitor;
    local string name;  // 监视器实例名称（用于调试）
    local virtual reg_intf intf;  // 虚拟接口句柄（用于采集信号）
    mailbox #(reg_trans) mon_mb;  // 监视邮箱：发送采集到的事务

    // 构造函数：初始化监视器名称
    function new(string name="reg_monitor");
      this.name = name;
    endfunction

    // 设置接口函数：绑定虚拟接口，若接口为空则报错
    function void set_interface(virtual reg_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;  // 绑定接口
    endfunction

    // 运行任务：启动监视器的信号采集逻辑
    task run();
      this.mon_trans();  // 调用事务采集方法
    endtask

    // 事务采集任务：从接口采集信号，生成事务并发送到监视邮箱
    task mon_trans();
      reg_trans m;  // 采集到的事务
      forever begin
        // 等待时钟上升沿，且复位已释放、命令不为IDLE（即有效操作）
        @(posedge intf.clk iff (intf.rstn && intf.mon_ck.cmd != `IDLE));
        m = new();  // 实例化新事务
        m.addr = intf.mon_ck.cmd_addr;  // 采集地址（mon_ck：监视时钟块）
        m.cmd = intf.mon_ck.cmd;        // 采集命令
        if(intf.mon_ck.cmd == `WRITE) begin  // 写操作：采集主到从数据
          m.data = intf.mon_ck.cmd_data_m2s;
        end
        else if(intf.mon_ck.cmd == `READ) begin  // 读操作：等待从机返回数据后采集
          @(posedge intf.clk);  // 等待下一个时钟沿（确保数据稳定）
          m.data = intf.mon_ck.cmd_data_s2m;  // 采集从到主数据（读取结果）
        end
        mon_mb.put(m);  // 将采集到的事务放入监视邮箱
        // 打印监视信息（时间、名称、地址、命令、数据）
        $display("%0t %s monitored addr %2x, cmd %2b, data %8x", $time, this.name, m.addr, m.cmd, m.data);
      end
    endtask
  endclass

  // 寄存器代理类：集成驱动和监视器，提供统一接口，简化上层验证环境搭建
  class reg_agent;
    local string name;  // 代理实例名称
    reg_driver driver;  // 驱动实例
    reg_monitor monitor;  // 监视器实例
    local virtual reg_intf vif;  // 虚拟接口句柄

    // 构造函数：初始化代理名称，创建驱动和监视器实例（名称带层级标识）
    function new(string name = "reg_agent");
      this.name = name;
      this.driver = new({name, ".driver"});  // 驱动名称格式："代理名.driver"
      this.monitor = new({name, ".monitor"});  // 监视器名称格式："代理名.monitor"
    endfunction

    // 设置接口函数：统一为驱动和监视器绑定接口
    function void set_interface(virtual reg_intf vif);
      this.vif = vif;
      driver.set_interface(vif);  // 绑定驱动接口
      monitor.set_interface(vif);  // 绑定监视器接口
    endfunction

    // 运行任务：并发启动驱动和监视器
    task run();
      fork
        driver.run();  // 启动驱动
        monitor.run();  // 启动监视器
      join
    endtask
  endclass

endpackage  // 包定义结束