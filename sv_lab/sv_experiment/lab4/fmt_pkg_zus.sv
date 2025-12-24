// 格式化模块（formatter）验证组件包
// 功能：封装格式化模块的事务定义、驱动、生成器、监视器、代理等核心验证组件
// 依赖：导入rpt_pkg包，用于日志报告和消息统计
package fmt_pkg;
  import rpt_pkg::*;

  // FIFO深度类型枚举：定义格式化模块内部FIFO的容量等级
  typedef enum {
    SHORT_FIFO,  // 短FIFO（容量最小）
    MED_FIFO,    // 中等FIFO（默认容量）
    LONG_FIFO,   // 长FIFO
    ULTRA_FIFO   // 超大FIFO（容量最大）
  } fmt_fifo_t;

  // 带宽等级枚举：定义数据传输/消费的带宽等级（对应消费周期）
  typedef enum {
    LOW_WIDTH,   // 低带宽（消费周期最长）
    MED_WIDTH,   // 中等带宽（默认带宽）
    HIGH_WIDTH,  // 高带宽
    ULTRA_WIDTH  // 超大带宽（消费周期最短）
  } fmt_bandwidth_t;

  // 格式化事务类（fmt_trans）：描述格式化模块的核心数据传输单元
  // 作用：封装接口传输的所有关键信息，支持克隆、打印、比较操作
  class fmt_trans;
    rand fmt_fifo_t fifo;              // FIFO深度配置（随机化字段）
    rand fmt_bandwidth_t bandwidth;    // 带宽配置（随机化字段）
    bit [9:0] length;                  // 数据长度（10位宽，最大支持1024）
    bit [31:0] data[];                 // 动态数据数组（存储32位宽的有效数据）
    bit [1:0] ch_id;                   // 通道ID（2位宽，支持4个通道）
    bit rsp;                           // 响应标志（1=配置成功响应，0=失败）

    // 随机约束：设置默认值（soft修饰，可被覆盖）
    constraint cstr{
      soft fifo == MED_FIFO;        // FIFO默认中等深度
      soft bandwidth == MED_WIDTH;  // 带宽默认中等等级
    };

    // 克隆函数：创建事务对象的副本（浅拷贝，动态数组直接赋值）
    // 返回值：新的fmt_trans对象，与原对象属性完全一致
    function fmt_trans clone();
      fmt_trans c = new();          // 实例化新事务对象
      c.fifo = this.fifo;           // 复制FIFO配置
      c.bandwidth = this.bandwidth; // 复制带宽配置
      c.length = this.length;       // 复制数据长度
      c.data = this.data;           // 复制数据数组（SystemVerilog动态数组赋值为浅拷贝）
      c.ch_id = this.ch_id;         // 复制通道ID
      c.rsp = this.rsp;             // 复制响应标志
      return c;                     // 返回克隆对象
    endfunction

    // 打印函数：格式化输出事务对象的所有属性
    // 返回值：拼接好的完整事务信息字符串
    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("fmt_trans object content is as below: \n")};
      s = {s, $sformatf("fifo = %s \n", this.fifo)};          // 打印FIFO类型
      s = {s, $sformatf("bandwidth = %s \n", this.bandwidth)};// 打印带宽类型
      s = {s, $sformatf("length = %0d \n", this.length)};     // 打印数据长度（十进制）
      foreach(data[i]) s = {s, $sformatf("data[%0d] = %8x \n", i, this.data[i])};// 打印每个数据（十六进制）
      s = {s, $sformatf("ch_id = %0d \n", this.ch_id)};       // 打印通道ID
      s = {s, $sformatf("rsp = %0d \n", this.rsp)};           // 打印响应标志
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction

    // 比较函数：对比当前事务（sobj）与目标事务（tobj）的关键属性
    // 参数 t：待比较的目标fmt_trans对象
    // 返回值：1=比较成功（关键属性一致），0=比较失败
    // 核心比较字段：length（数据长度）、ch_id（通道ID）、data（数据内容）
    function bit compare(fmt_trans t);
      string s;
      compare = 1;  // 初始化比较结果为成功（1）
      // 构建比较日志头部
      s = "\n=======================================\n";
      s = {s, $sformatf("COMPARING fmt_trans object at time %0t \n", $time)};

      // 比较数据长度
      if(this.length != t.length) begin
        compare = 0;  // 长度不一致，标记失败
        s = {s, $sformatf("sobj length %0d != tobj length %0d \n", this.length, t.length)};
      end

      // 比较通道ID
      if(this.ch_id != t.ch_id) begin
        compare = 0;  // ID不一致，标记失败
        s = {s, $sformatf("sobj ch_id %0d != tobj ch_id %0d\n", this.ch_id, t.ch_id)};
      end

      // 逐元素比较数据数组（需确保两事务data数组长度一致）
      foreach(this.data[i]) begin
        if(this.data[i] != t.data[i]) begin
          compare = 0;  // 数据不一致，标记失败
          s = {s, $sformatf("sobj data[%0d] %8x != tobj data[%0d] %8x\n", i, this.data[i], i, t.data[i])};
        end
      end

      // 补充比较结果日志
      if(compare == 1) s = {s, "COMPARED SUCCESS!\n"};
      else  s = {s, "COMPARED FAILURE!\n"};
      s = {s, "=======================================\n"};

      // 调用rpt_pkg的日志函数记录比较结果（中等严重度，确保输出）
      rpt_pkg::rpt_msg("[CMPOBJ]", s, rpt_pkg::INFO, rpt_pkg::MEDIUM);
    endfunction
  endclass

  // 格式化驱动类（fmt_driver）：驱动DUT（被测模块）的格式化接口
  // 核心功能：接收配置请求、处理复位、接收DUT数据、消费FIFO数据
  class fmt_driver;
    local string name;                      // 驱动实例名称（用于日志区分）
    local virtual fmt_intf intf;            // 虚拟接口（连接DUT的物理接口）
    mailbox #(fmt_trans) req_mb;            // 请求邮箱：接收来自生成器的配置请求
    mailbox #(fmt_trans) rsp_mb;            // 响应邮箱：向生成器返回配置结果

    local mailbox #(bit[31:0]) fifo;        // 内部数据FIFO：缓存从DUT接收的数据
    local int fifo_bound;                   // FIFO容量边界（最大存储深度）
    local int data_consum_peroid;           // 数据消费周期（每N个时钟消费1个数据）

    // 构造函数：初始化驱动名称和默认参数
    // 参数 name：驱动名称（默认"fmt_driver"）
    function new(string name = "fmt_driver");
      this.name = name;
      this.fifo = new();                    // 初始化内部数据FIFO
      this.fifo_bound = 4096;               // 默认FIFO容量4096
      this.data_consum_peroid = 1;          // 默认消费周期1个时钟
    endfunction

    // 接口绑定函数：将虚拟接口与DUT物理接口关联
    // 参数 intf：待绑定的fmt_intf虚拟接口
    function void set_interface(virtual fmt_intf intf);
      if(intf == null)
        // 接口为空时报错，提示检查接口实例化
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;                   // 绑定接口成功
    endfunction

    // 主运行任务：启动驱动的所有核心子任务（并行执行）
    task run();
      fork
        this.do_receive();  // 接收DUT发送的数据
        this.do_consume();  // 消费内部FIFO中的数据
        this.do_config();   // 处理生成器的配置请求
        this.do_reset();    // 处理复位信号
      join
    endtask

    // 配置处理任务：从请求邮箱获取配置，更新驱动参数并返回响应
    task do_config();
      fmt_trans req, rsp;
      forever begin
        this.req_mb.get(req);  // 阻塞获取配置请求

        // 根据请求的FIFO类型设置FIFO容量边界
        case(req.fifo)
          SHORT_FIFO: this.fifo_bound = 64;    // 短FIFO容量64
          MED_FIFO: this.fifo_bound = 256;     // 中等FIFO容量256
          LONG_FIFO: this.fifo_bound = 512;    // 长FIFO容量512
          ULTRA_FIFO: this.fifo_bound = 2048;  // 超大FIFO容量2048
        endcase
        this.fifo = new(this.fifo_bound);  // 按新容量重建内部FIFO

        // 根据请求的带宽类型设置数据消费周期
        case(req.bandwidth)
          LOW_WIDTH: this.data_consum_peroid = 8;   // 低带宽：8个时钟消费1个数据
          MED_WIDTH: this.data_consum_peroid = 4;   // 中等带宽：4个时钟消费1个数据
          HIGH_WIDTH: this.data_consum_peroid = 2;  // 高带宽：2个时钟消费1个数据
          ULTRA_WIDTH: this.data_consum_peroid = 1; // 超大带宽：1个时钟消费1个数据
        endcase

        rsp = req.clone();  // 克隆请求对象作为响应
        rsp.rsp = 1;        // 标记响应成功
        this.rsp_mb.put(rsp);  // 向生成器返回响应
      end
    endtask

    // 复位处理任务：复位信号拉低时（negedge rstn）初始化接口信号
    task do_reset();
      forever begin
        @(negedge intf.rstn);  // 等待复位信号下降沿（复位开始）
        intf.fmt_grant <= 0;    // 复位时拉低授权信号（拒绝DUT请求）
      end
    endtask

    // 数据接收任务：接收DUT的请求，授权后读取数据存入内部FIFO
    task do_receive();
      forever begin
        @(posedge intf.fmt_req);  // 等待DUT的请求信号（fmt_req上升沿）

        // 等待内部FIFO有足够空间容纳DUT发送的数据
        forever begin
          @(posedge intf.clk);
          // FIFO剩余空间 = 容量 - 当前存储数量，需>=DUT发送的数据长度
          if((this.fifo_bound - this.fifo.num()) >= intf.fmt_length)
            break;  // 空间足够，退出等待
        end

        intf.drv_ck.fmt_grant <= 1;  // 给出授权信号（允许DUT发送数据）
        @(posedge intf.fmt_start);   // 等待DUT开始发送数据（fmt_start上升沿）

        // 异步拉低授权信号（不阻塞后续数据接收）
        fork
          begin
            @(posedge intf.clk);
            intf.drv_ck.fmt_grant <= 0;  // 下一个时钟拉低授权
          end
        join_none

        // 接收DUT发送的所有数据（共fmt_length个）
        repeat(intf.fmt_length) begin
          @(negedge intf.clk);          // 时钟下降沿采样数据（避免竞争）
          this.fifo.put(intf.fmt_data); // 将采样到的数据存入内部FIFO
        end
      end
    endtask

    // 数据消费任务：从内部FIFO中读取数据并消费（模拟数据处理）
    task do_consume();
      bit[31:0] data;
      forever begin
        // 尝试从FIFO取数据（非阻塞：无数据时返回0，不阻塞）
        void'(this.fifo.try_get(data));
        // 随机等待1~data_consum_peroid个时钟周期（模拟消费延迟）
        repeat($urandom_range(1, this.data_consum_peroid)) @(posedge intf.clk);
      end
    endtask
  endclass

  // 格式化生成器类（fmt_generator）：生成格式化模块的配置请求事务
  // 核心功能：随机生成配置参数，向驱动发送请求并接收响应
  class fmt_generator;
    rand fmt_fifo_t fifo = MED_FIFO;        // 生成的FIFO配置（默认中等深度）
    rand fmt_bandwidth_t bandwidth = MED_WIDTH;  // 生成的带宽配置（默认中等带宽）

    mailbox #(fmt_trans) req_mb;            // 请求邮箱：与驱动的req_mb绑定
    mailbox #(fmt_trans) rsp_mb;            // 响应邮箱：与驱动的rsp_mb绑定

    // 随机约束：设置默认配置（soft修饰，可通过外部约束覆盖）
    constraint cstr{
      soft fifo == MED_FIFO;
      soft bandwidth == MED_WIDTH;
    }

    // 构造函数：初始化请求和响应邮箱
    function new();
      this.req_mb = new();
      this.rsp_mb = new();
    endfunction

    // 启动任务：开始生成事务（对外提供的启动接口）
    task start();
      send_trans();  // 调用事务发送函数
    endtask

    // 事务发送任务：生成并随机化事务，发送给驱动并验证响应
    // generate transaction and put into local mailbox
    task send_trans();
      fmt_trans req, rsp;
      req = new();  // 实例化配置请求事务

      // 随机化请求事务：本地配置非默认值时，强制事务配置与本地一致
      assert(req.randomize with {
        local::fifo != MED_FIFO -> fifo == local::fifo;  // 本地FIFO非默认时，事务沿用
        local::bandwidth != MED_WIDTH -> bandwidth == local::bandwidth;  // 本地带宽非默认时，事务沿用
      })
        else $fatal("[RNDFAIL] formatter packet randomization failure!");  // 随机化失败则终止仿真

      $display(req.sprint());  // 打印随机化后的请求事务
      this.req_mb.put(req);    // 将请求发送到驱动
      this.rsp_mb.get(rsp);    // 阻塞等待驱动的响应
      $display(rsp.sprint());  // 打印驱动返回的响应事务

      // 检查响应标志：rsp=1为成功，否则报错
      assert(rsp.rsp)
        else $error("[RSPERR] %0t error response received!", $time);
    endfunction

    // 打印函数：格式化输出生成器的当前配置
    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("fmt_generator object content is as below: \n")};
      s = {s, $sformatf("fifo = %s \n", this.fifo)};          // 打印FIFO配置
      s = {s, $sformatf("bandwidth = %s \n", this.bandwidth)};// 打印带宽配置
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction

    // 随机化后回调函数：随机化完成后自动打印生成器配置
    function void post_randomize();
      string s;
      s = {"AFTER RANDOMIZATION \n", this.sprint()};
      $display(s);
    endfunction

  endclass

  // 格式化监视器类（fmt_monitor）：监控DUT的格式化接口，采集事务
  // 核心功能：捕获接口上的有效事务，提取关键信息并传递给后续组件（如校验器）
  class fmt_monitor;
    local string name;                      // 监视器实例名称（用于日志区分）
    local virtual fmt_intf intf;            // 虚拟接口（连接DUT的物理接口）
    mailbox #(fmt_trans) mon_mb;            // 监控事务邮箱：向校验器传递采集到的事务

    // 构造函数：初始化监视器名称
    function new(string name="fmt_monitor");
      this.name = name;
    endfunction

    // 接口绑定函数：将虚拟接口与DUT物理接口关联
    function void set_interface(virtual fmt_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction

    // 主运行任务：启动事务监控
    task run();
      this.mon_trans();  // 调用事务采集任务
    endtask

    // 事务采集任务：监控接口信号，提取事务信息并放入邮箱
    task mon_trans();
      fmt_trans m;
      string s;
      forever begin
        // 等待事务开始信号（fmt_start上升沿）
        @(posedge intf.mon_ck.fmt_start);
        m = new();  // 实例化监控事务对象

        // 采集事务关键信息（从接口信号读取）
        m.length = intf.mon_ck.fmt_length;  // 采集数据长度
        m.ch_id = intf.mon_ck.fmt_chid;     // 采集通道ID
        m.data = new[m.length];             // 根据长度初始化数据数组

        // 逐时钟采集数据（共m.length个）
        foreach(m.data[i]) begin
          @(posedge intf.clk);
          m.data[i] = intf.mon_ck.fmt_data;  // 时钟上升沿采样数据
        end

        mon_mb.put(m);  // 将采集到的事务放入邮箱，供后续组件使用

        // 打印监控日志（包含时间、监视器名称、事务信息）
        s = $sformatf("=======================================\n");
        s = {s, $sformatf("%0t %s monitored a packet: \n", $time, this.name)};
        s = {s, $sformatf("length = %0d \n", m.length)};
        s = {s, $sformatf("chid = %0d \n", m.ch_id)};
        foreach(m.data[i]) s = {s, $sformatf("data[%0d] = %8x \n", i, m.data[i])};
        s = {s, $sformatf("=======================================\n")};
        $display(s);
      end
    endtask
  endclass

  // 格式化代理类（fmt_agent）：集成驱动和监视器，提供统一的组件接口
  // 作用：简化验证环境搭建，统一管理驱动和监视器的接口绑定、运行控制
  class fmt_agent;
    local string name;          // 代理实例名称（用于区分不同代理）
    fmt_driver driver;          // 驱动实例（代理内部包含）
    fmt_monitor monitor;        // 监视器实例（代理内部包含）
    local virtual fmt_intf vif; // 虚拟接口（统一绑定给驱动和监视器）

    // 构造函数：初始化代理名称，创建驱动和监视器实例
    // 参数 name：代理名称（默认"fmt_agent"）
    function new(string name = "fmt_agent");
      this.name = name;
      // 驱动名称格式：代理名.driver（如"uart_fmt_agent.driver"）
      this.driver = new({name, ".driver"});
      // 监视器名称格式：代理名.monitor（如"uart_fmt_agent.monitor"）
      this.monitor = new({name, ".monitor"});
    endfunction

    // 接口绑定函数：统一为驱动和监视器绑定虚拟接口
    function void set_interface(virtual fmt_intf vif);
      this.vif = vif;
      driver.set_interface(vif);  // 驱动绑定接口
      monitor.set_interface(vif); // 监视器绑定接口
    endfunction

    // 主运行任务：并行启动驱动和监视器
    task run();
      fork
        driver.run();  // 启动驱动
        monitor.run(); // 启动监视器
      join
    endtask
  endclass

endpackage