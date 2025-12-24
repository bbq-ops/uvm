// 导入MCDF相关的参数定义（如寄存器地址、命令类型、FIFO类型等）
`include "param_def.v"

// MCDF验证顶层包：包含所有验证组件（参考模型、Checker、覆盖率、环境、测试用例）
package mcdf_pkg;

  // 导入依赖的子包：每个子包对应MCDF的一个功能模块（通道、寄存器、仲裁器、格式化器、日志）
  import chnl_pkg::*;    // 通道（Channel）相关：agent、transaction、generator等
  import reg_pkg::*;     // 寄存器（Register）相关：agent、transaction、命令类型（`WRITE/`READ/`IDLE）等
  import arb_pkg::*;     // 仲裁器（Arbiter）相关：接口、优先级定义等
  import fmt_pkg::*;     // 格式化器（Formatter）相关：agent、transaction、FIFO/带宽定义等
  import rpt_pkg::*;     // 日志（Report）相关：日志输出、级别定义（ERROR/INFO）等

  // -----------------------------------------------------------------------------
  // 1. 数据类型定义：MCDF寄存器配置结构体和字段枚举
  // -----------------------------------------------------------------------------
  // MCDF通道配置寄存器结构体（打包结构体，对应硬件寄存器布局）
  typedef struct packed {
    bit[2:0] len;    // 包长度配置（0→4B，1→8B，2→16B，3→32B，>3默认32B）
    bit[1:0] prio;   // 通道优先级（0最高，3最低）
    bit en;          // 通道使能（1=使能，0=禁用）
    bit[7:0] avail;  // 通道可用状态（只读，显示当前可传输数据量）
  } mcdf_reg_t;

  // 寄存器字段枚举：标识寄存器的可操作字段（用于参考模型读取字段值）
  typedef enum {
    RW_LEN,   // 读写：包长度字段
    RW_PRIO,  // 读写：优先级字段
    RW_EN,    // 读写：使能字段
    RD_AVAIL  // 只读：可用状态字段
  } mcdf_field_t;

  // -----------------------------------------------------------------------------
  // 2. 参考模型（mcdf_refmod）：模拟MCDF的正确行为，提供预期输出
  // 核心功能：接收寄存器配置和输入数据，生成预期的格式化输出（fmt_trans）
  // -----------------------------------------------------------------------------
  class mcdf_refmod;
    local virtual mcdf_intf intf;       // MCDF顶层接口（用于复位监听）
    local string name;                  // 参考模型名称
    mcdf_reg_t regs[3];                 // 3个通道的配置寄存器副本（与DUT寄存器同步）
    mailbox #(reg_trans) reg_mb;        // 接收寄存器交易的mailbox（来自reg_agent的monitor）
    mailbox #(mon_data_t) in_mbs[3];    // 接收3个通道输入数据的mailbox（来自chnl_agent的monitor）
    mailbox #(fmt_trans) out_mbs[3];    // 输出预期格式化包的mailbox（给checker对比）

    // 构造函数：初始化输出mailbox
    function new(string name="mcdf_refmod");
      this.name = name;
      foreach(this.out_mbs[i]) this.out_mbs[i] = new();  // 初始化3个通道的预期输出mailbox
    endfunction

    // 主运行任务：并行执行复位、寄存器更新、数据包处理
    task run();
      fork
        do_reset();         // 处理复位逻辑
        this.do_reg_update();// 处理寄存器配置更新
        do_packet(0);       // 处理通道0的输入数据，生成预期输出
        do_packet(1);       // 处理通道1的输入数据，生成预期输出
        do_packet(2);       // 处理通道2的输入数据，生成预期输出
      join
    endtask

    // 寄存器更新任务：从reg_mb获取寄存器交易，同步更新本地寄存器副本
    task do_reg_update();
      reg_trans t;  // 寄存器交易对象（包含cmd/addr/data）
      forever begin
        this.reg_mb.get(t);  // 阻塞获取寄存器交易

        // 处理RW寄存器写操作（地址高4位为0：`SLV0_RW_ADDR等）
        if(t.addr[7:4] == 0 && t.cmd == `WRITE) begin
          this.regs[t.addr[3:2]].en   = t.data[0];    // 最低位：通道使能
          this.regs[t.addr[3:2]].prio = t.data[2:1];  // 1-2位：优先级
          this.regs[t.addr[3:2]].len  = t.data[5:3];  // 3-5位：包长度配置
        end
        // 处理RO寄存器读操作（地址高4位为1：`SLV0_R_ADDR等）
        else if(t.addr[7:4] == 1 && t.cmd == `READ) begin
          this.regs[t.addr[3:2]].avail = t.data[7:0]; // 读取可用状态（DUT返回值写入本地副本）
        end
      end
    endtask

    // 数据包处理任务：根据寄存器配置，将输入数据组装为预期的格式化包
    // id：通道ID（0/1/2）
    task do_packet(int id);
      fmt_trans ot;       // 预期的格式化输出包
      mon_data_t it;      // 输入的通道数据（来自channel monitor）
      bit[2:0] len;       // 当前通道的包长度配置

      forever begin
        this.in_mbs[id].peek(it);  // 窥视输入数据（不取出，确保数据存在）
        ot = new();                // 实例化预期输出包

        // 获取当前通道的包长度配置（通过字段枚举获取）
        len = this.get_field_value(id, RW_LEN);
        // 计算实际包长度：len>3时为32B，否则为4<<len（0→4B，1→8B，2→16B，3→32B）
        ot.length = len > 3 ? 32 : 4 << len;
        ot.data = new[ot.length];  // 分配数据缓冲区
        ot.ch_id = id;             // 标记通道ID

        // 从输入mailbox读取对应长度的数据，填充到预期包中
        foreach(ot.data[m]) begin
          this.in_mbs[id].get(it);  // 取出输入数据
          ot.data[m] = it.data;     // 复制数据到预期包
        end

        this.out_mbs[id].put(ot);  // 将预期包放入输出mailbox，供checker对比
      end
    endtask

    // 辅助函数：获取指定通道和字段的寄存器值
    // id：通道ID；f：寄存器字段枚举
    function int get_field_value(int id, mcdf_field_t f);
      case(f)
        RW_LEN:   return regs[id].len;    // 返回包长度配置
        RW_PRIO:  return regs[id].prio;   // 返回优先级配置
        RW_EN:    return regs[id].en;     // 返回通道使能状态
        RD_AVAIL: return regs[id].avail;  // 返回可用状态
      endcase
    endfunction 

    // 复位处理任务：复位时初始化寄存器默认值
    task do_reset();
      forever begin
        @(negedge intf.rstn);  // 监听复位下降沿（复位开始）
        foreach(regs[i]) begin
          regs[i].len  = 'h0;   // 默认包长度配置：4B
          regs[i].prio = 'h3;   // 默认优先级：最低（3）
          regs[i].en   = 'h1;   // 默认使能：开启
          regs[i].avail = 'h20; // 默认可用状态：32B
        end
      end
    endtask

    // 接口绑定函数：将DUT的mcdf接口绑定到参考模型
    function void set_interface(virtual mcdf_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction
    
  endclass

  // -----------------------------------------------------------------------------
  // 3. 校验器（mcdf_checker）：验证DUT行为正确性
  // 核心功能：1. 对比DUT输出与参考模型预期输出；2. 检查通道禁用、仲裁器优先级等功能
  // -----------------------------------------------------------------------------
  class mcdf_checker;
    local string name;                      // Checker名称
    local int err_count;                    // 总错误数
    local int total_count;                  // 总对比次数
    local int chnl_count[3];                // 每个通道的对比次数
    local virtual chnl_intf chnl_vifs[3];   // 3个通道的接口（用于检查通道禁用）
    local virtual arb_intf arb_vif;         // 仲裁器接口（用于检查优先级）
    local virtual mcdf_intf mcdf_vif;       // MCDF顶层接口（用于监听通道使能）
    local mcdf_refmod refmod;               // 参考模型实例（用于获取预期输出）
    mailbox #(mon_data_t) chnl_mbs[3];      // 接收通道输入数据的mailbox（来自chnl_agent monitor）
    mailbox #(fmt_trans) fmt_mb;            // 接收DUT格式化输出的mailbox（来自fmt_agent monitor）
    mailbox #(reg_trans) reg_mb;            // 接收寄存器交易的mailbox（来自reg_agent monitor）
    mailbox #(fmt_trans) exp_mbs[3];        // 接收参考模型预期输出的mailbox（绑定到refmod.out_mbs）

    // 构造函数：初始化mailbox和参考模型，绑定数据通路
    function new(string name="mcdf_checker");
      this.name = name;
      // 初始化输入mailbox
      foreach(this.chnl_mbs[i]) this.chnl_mbs[i] = new();
      this.fmt_mb = new();
      this.reg_mb = new();
      this.refmod = new();  // 实例化参考模型

      // 绑定参考模型的输入/输出mailbox：参考模型从chnl_mbs取输入，exp_mbs存预期输出
      foreach(this.refmod.in_mbs[i]) begin
        this.refmod.in_mbs[i] = this.chnl_mbs[i];
        this.exp_mbs[i] = this.refmod.out_mbs[i];
      end
      this.refmod.reg_mb = this.reg_mb;  // 绑定寄存器交易mailbox

      // 初始化统计变量
      this.err_count = 0;
      this.total_count = 0;
      foreach(this.chnl_count[i]) this.chnl_count[i] = 0;
    endfunction

    // 接口绑定函数：绑定所有需要的DUT接口
    function void set_interface(virtual mcdf_intf mcdf_vif, virtual chnl_intf chnl_vifs[3], virtual arb_intf arb_vif);
      if(mcdf_vif == null)
        $error("mcdf interface handle is NULL, please check if target interface has been intantiated");
      else begin
        this.mcdf_vif = mcdf_vif;
        this.refmod.set_interface(mcdf_vif);  // 同时绑定参考模型的接口
      end
      if(chnl_vifs[0] == null || chnl_vifs[1] == null || chnl_vifs[2] == null)
        $error("chnl interface handle is NULL, please check if target interface has been intantiated");
      else this.chnl_vifs = chnl_vifs;
      if(arb_vif == null)
        $error("arb interface handle is NULL, please check if target interface has been intantiated");
      else this.arb_vif = arb_vif;
    endfunction

    // 主运行任务：并行执行所有检查任务和参考模型
    task run();
      fork
        this.do_channel_disable_check(0);  // 检查通道0禁用功能
        this.do_channel_disable_check(1);  // 检查通道1禁用功能
        this.do_channel_disable_check(2);  // 检查通道2禁用功能
        this.do_arbiter_priority_check();  // 检查仲裁器优先级功能
        this.do_compare();                 // 对比DUT与参考模型输出
        this.refmod.run();                 // 启动参考模型
      join
    endtask

    // 数据对比任务：核心校验逻辑，对比DUT输出与参考模型预期输出
    task do_compare();
      fmt_trans expt, mont;  // expt：预期输出；mont：DUT监控输出
      bit cmp;                // 对比结果（1=一致，0=不一致）

      forever begin
        this.fmt_mb.get(mont);          // 从DUT获取监控输出包
        this.exp_mbs[mont.ch_id].get(expt);  // 从参考模型获取对应通道的预期包
        cmp = mont.compare(expt);       // 调用fmt_trans的compare方法对比包内容

        // 更新统计计数
        this.total_count++;
        this.chnl_count[mont.ch_id]++;

        // 输出对比结果日志
        if(cmp == 0) begin  // 对比失败
          this.err_count++;
          rpt_pkg::rpt_msg("[CMPFAIL]", 
            $sformatf("%0t %0dth times comparing but failed! MCDF monitored output packet is different with reference model output", $time, this.total_count),
            rpt_pkg::ERROR,  // 日志级别：错误
            rpt_pkg::TOP,    // 日志层级：顶层
            rpt_pkg::LOG);   // 输出到日志文件
        end
        else begin  // 对比成功
          rpt_pkg::rpt_msg("[CMPSUCD]",
            $sformatf("%0t %0dth times comparing and succeeded! MCDF monitored output packet is the same with reference model output", $time, this.total_count),
            rpt_pkg::INFO,   // 日志级别：信息
            rpt_pkg::HIGH);  // 日志优先级：高
        end
      end
    endtask

    // 通道禁用检查任务：验证通道禁用时，不会出现valid和ready同时为高的情况
    // id：通道ID（0/1/2）
    task do_channel_disable_check(int id);
      forever begin
        // 触发条件：时钟上升沿、复位释放、当前通道禁用
        @(posedge this.mcdf_vif.clk iff (this.mcdf_vif.rstn && this.mcdf_vif.mon_ck.chnl_en[id]===0));
        // 错误场景：通道禁用时，valid和ready同时为高（不允许传输数据）
        if(this.chnl_vifs[id].mon_ck.ch_valid===1 && this.chnl_vifs[id].mon_ck.ch_ready===1)
          rpt_pkg::rpt_msg("[CHKERR]", 
            $sformatf("ERROR! %0t when channel disabled, ready signal raised when valid high",$time), 
            rpt_pkg::ERROR, 
            rpt_pkg::TOP);
      end
    endtask

    // 仲裁器优先级检查任务：验证仲裁器会授予当前最高优先级的通道请求
    task do_arbiter_priority_check();
      int id;  // 最高优先级且有请求的通道ID
      forever begin
        // 触发条件：时钟上升沿、复位释放、仲裁器收到请求
        @(posedge this.arb_vif.clk iff (this.arb_vif.rstn && this.arb_vif.mon_ck.f2a_id_req===1));
        id = this.get_slave_id_with_prio();  // 获取最高优先级的请求通道

        if(id >= 0) begin  // 存在有效请求通道
          @(posedge this.arb_vif.clk);
          // 错误场景：最高优先级通道未被授予授权
          if(this.arb_vif.mon_ck.a2s_acks[id] !== 1)
            rpt_pkg::rpt_msg("[CHKERR]",
              $sformatf("ERROR! %0t arbiter received f2a_id_req===1 and channel[%0d] raising request with high priority, but is not granted by arbiter", $time, id),
              rpt_pkg::ERROR,
              rpt_pkg::TOP);
        end
      end
    endtask

    // 辅助函数：查找当前最高优先级且有请求的通道ID
    function int get_slave_id_with_prio();
      int id=-1;    // 初始化无效ID
      int prio=999; // 初始化一个极大的优先级值（优先级数值越小越高）
      foreach(this.arb_vif.mon_ck.slv_prios[i]) begin
        // 找到优先级更高且有请求的通道
        if(this.arb_vif.mon_ck.slv_prios[i] < prio && this.arb_vif.mon_ck.slv_reqs[i]===1) begin
          id = i;
          prio = this.arb_vif.mon_ck.slv_prios[i];
        end
      end
      return id;  // 返回最高优先级通道ID（-1表示无有效请求）
    endfunction

    // 报告函数：输出Checker的校验统计结果
    function void do_report();
      string s;
      s = "\n---------------------------------------------------------------\n";
      s = {s, "CHECKER SUMMARY \n"}; 
      s = {s, $sformatf("total comparison count: %0d \n", this.total_count)}; 
      foreach(this.chnl_count[i]) s = {s, $sformatf(" channel[%0d] comparison count: %0d \n", i, this.chnl_count[i])};
      s = {s, $sformatf("total error count: %0d \n", this.err_count)}; 
      // 警告：mailbox非空（可能有未处理的数据，说明测试不完整）
      foreach(this.chnl_mbs[i]) begin
        if(this.chnl_mbs[i].num() != 0)
          s = {s, $sformatf("WARNING:: chnl_mbs[%0d] is not empty! size = %0d \n", i, this.chnl_mbs[i].num())}; 
      end
      if(this.fmt_mb.num() != 0)
          s = {s, $sformatf("WARNING:: fmt_mb is not empty! size = %0d \n", this.fmt_mb.num())}; 
      s = {s, "---------------------------------------------------------------\n"};
      rpt_pkg::rpt_msg($sformatf("[%s]",this.name), s, rpt_pkg::INFO, rpt_pkg::TOP);
    endfunction
  endclass

  // -----------------------------------------------------------------------------
  // 4. 覆盖率收集器（mcdf_coverage）：收集功能覆盖率，确保测试场景覆盖全面
  // 核心功能：覆盖寄存器操作、通道禁用、仲裁器优先级、格式化器配置等场景
  // -----------------------------------------------------------------------------
  class mcdf_coverage;
    local virtual chnl_intf chnl_vifs[3];  // 3个通道接口
    local virtual arb_intf arb_vif;        // 仲裁器接口
    local virtual mcdf_intf mcdf_vif;      // MCDF顶层接口
    local virtual reg_intf reg_vif;        // 寄存器接口
    local virtual fmt_intf fmt_vif;        // 格式化器接口
    local string name;                     // 覆盖率收集器名称
    local int delay_req_to_grant;          // 格式化器请求到授权的延迟（用于覆盖率收集）

    // 覆盖率组1：寄存器读写场景覆盖（合法地址+命令组合）
    covergroup cg_mcdf_reg_write_read;
      addr: coverpoint reg_vif.mon_ck.cmd_addr {  // 寄存器地址覆盖
        type_option.weight = 0;  // 该coverpoint不单独计算覆盖率，仅用于cross
        bins slv0_rw_addr = {`SLV0_RW_ADDR};  // 通道0读写寄存器地址
        bins slv1_rw_addr = {`SLV1_RW_ADDR};  // 通道1读写寄存器地址
        bins slv2_rw_addr = {`SLV2_RW_ADDR};  // 通道2读写寄存器地址
        bins slv0_r_addr  = {`SLV0_R_ADDR };  // 通道0只读寄存器地址
        bins slv1_r_addr  = {`SLV1_R_ADDR };  // 通道1只读寄存器地址
        bins slv2_r_addr  = {`SLV2_R_ADDR };  // 通道2只读寄存器地址
      }
      cmd: coverpoint reg_vif.mon_ck.cmd {  // 寄存器命令覆盖
        type_option.weight = 0;
        bins write = {`WRITE};  // 写命令
        bins read  = {`READ};   // 读命令
        bins idle  = {`IDLE};   // 空闲命令
      }
      // 地址×命令交叉覆盖：确保所有合法地址+命令组合都被覆盖
      cmdXaddr: cross cmd, addr {
        bins slv0_rw_addr = binsof(addr.slv0_rw_addr);
        bins slv1_rw_addr = binsof(addr.slv1_rw_addr);
        bins slv2_rw_addr = binsof(addr.slv2_rw_addr);
        bins slv0_r_addr  = binsof(addr.slv0_r_addr );
        bins slv1_r_addr  = binsof(addr.slv1_r_addr );
        bins slv2_r_addr  = binsof(addr.slv2_r_addr );
        bins write        = binsof(cmd.write);
        bins read         = binsof(cmd.read );
        bins idle         = binsof(cmd.idle );
        // 关键组合：写命令+读写寄存器
        bins write_slv0_rw_addr  = binsof(cmd.write) && binsof(addr.slv0_rw_addr);
        bins write_slv1_rw_addr  = binsof(cmd.write) && binsof(addr.slv1_rw_addr);
        bins write_slv2_rw_addr  = binsof(cmd.write) && binsof(addr.slv2_rw_addr);
        // 关键组合：读命令+读写寄存器
        bins read_slv0_rw_addr   = binsof(cmd.read) && binsof(addr.slv0_rw_addr);
        bins read_slv1_rw_addr   = binsof(cmd.read) && binsof(addr.slv1_rw_addr);
        bins read_slv2_rw_addr   = binsof(cmd.read) && binsof(addr.slv2_rw_addr);
        // 关键组合：读命令+只读寄存器
        bins read_slv0_r_addr    = binsof(cmd.read) && binsof(addr.slv0_r_addr); 
        bins read_slv1_r_addr    = binsof(cmd.read) && binsof(addr.slv1_r_addr); 
        bins read_slv2_r_addr    = binsof(cmd.read) && binsof(addr.slv2_r_addr); 
      }
    endgroup

    // 覆盖率组2：寄存器非法访问场景覆盖（非法地址/非法数据）
    covergroup cg_mcdf_reg_illegal_access;
      addr: coverpoint reg_vif.mon_ck.cmd_addr {  // 地址覆盖（合法+非法）
        type_option.weight = 0;
        bins legal_rw = {`SLV0_RW_ADDR, `SLV1_RW_ADDR, `SLV2_RW_ADDR};  // 合法读写地址
        bins legal_r = {`SLV0_R_ADDR, `SLV1_R_ADDR, `SLV2_R_ADDR};      // 合法只读地址
        bins illegal = {[8'h20:$], 8'hC, 8'h1C};  // 非法地址（0x20以上+特定地址）
      }
      cmd: coverpoint reg_vif.mon_ck.cmd {  // 命令覆盖（写/读）
        type_option.weight = 0;
        bins write = {`WRITE};
        bins read  = {`READ};
      }
      wdata: coverpoint reg_vif.mon_ck.cmd_data_m2s {  // 写数据覆盖（合法+非法）
        type_option.weight = 0;
        bins legal = {[0:'h3F]};    // 合法数据（低6位有效，保留位为0）
        bins illegal = {['h40:$]};  // 非法数据（保留位为1）
      }
      rdata: coverpoint reg_vif.mon_ck.cmd_data_s2m {  // 读数据覆盖（合法）
        type_option.weight = 0;
        bins legal = {[0:'hFF]};    // 合法数据（8位有效）
        illegal_bins illegal = default;  // 非法数据（默认不允许）
      }
      // 命令×地址×数据交叉覆盖：覆盖所有非法访问场景
      cmdXaddrXdata: cross cmd, addr, wdata, rdata {
        bins addr_legal_rw = binsof(addr.legal_rw);
        bins addr_legal_r = binsof(addr.legal_r);
        bins addr_illegal = binsof(addr.illegal);
        bins cmd_write = binsof(cmd.write);
        bins cmd_read = binsof(cmd.read);
        bins wdata_legal = binsof(wdata.legal);
        bins wdata_illegal = binsof(wdata.illegal);
        bins rdata_legal = binsof(rdata.legal);
        // 关键非法场景：写命令+非法地址
        bins write_illegal_addr = binsof(cmd.write) && binsof(addr.illegal);
        // 关键非法场景：读命令+非法地址
        bins read_illegal_addr  = binsof(cmd.read) && binsof(addr.illegal);
        // 关键非法场景：写命令+合法读写地址+非法数据
        bins write_illegal_rw_data = binsof(cmd.write) && binsof(addr.legal_rw) && binsof(wdata.illegal);
        // 关键非法场景：写命令+合法只读地址+非法数据（只读寄存器不允许写）
        bins write_illegal_r_data = binsof(cmd.write) && binsof(addr.legal_r) && binsof(wdata.illegal);
      }
    endgroup

    // 覆盖率组3：通道禁用场景覆盖（使能状态×valid信号组合）
    covergroup cg_channel_disable;
      ch0_en: coverpoint mcdf_vif.mon_ck.chnl_en[0] {  // 通道0使能状态
        type_option.weight = 0;
        wildcard bins en  = {1'b1};  // 使能
        wildcard bins dis = {1'b0};  // 禁用
      }
      ch1_en: coverpoint mcdf_vif.mon_ck.chnl_en[1] {  // 通道1使能状态
        type_option.weight = 0;
        wildcard bins en  = {1'b1};
        wildcard bins dis = {1'b0};
      }
      ch2_en: coverpoint mcdf_vif.mon_ck.chnl_en[2] {  // 通道2使能状态
        type_option.weight = 0;
        wildcard bins en  = {1'b1};
        wildcard bins dis = {1'b0};
      }
      ch0_vld: coverpoint chnl_vifs[0].mon_ck.ch_valid {  // 通道0 valid信号
        type_option.weight = 0;
        bins hi = {1'b1};  // 高电平
        bins lo = {1'b0};  // 低电平
      }
      ch1_vld: coverpoint chnl_vifs[1].mon_ck.ch_valid {  // 通道1 valid信号
        type_option.weight = 0;
        bins hi = {1'b1};
        bins lo = {1'b0};
      }
      ch2_vld: coverpoint chnl_vifs[2].mon_ck.ch_valid {  // 通道2 valid信号
        type_option.weight = 0;
        bins hi = {1'b1};
        bins lo = {1'b0};
      }
      // 使能状态×valid信号交叉覆盖：确保所有组合都被覆盖
      chenXchvld: cross ch0_en, ch1_en, ch2_en, ch0_vld, ch1_vld, ch2_vld {
        bins ch0_en  = binsof(ch0_en.en);
        bins ch0_dis = binsof(ch0_en.dis);
        bins ch1_en  = binsof(ch1_en.en);
        bins ch1_dis = binsof(ch1_en.dis);
        bins ch2_en  = binsof(ch2_en.en);
        bins ch2_dis = binsof(ch2_en.dis);
        bins ch0_hi  = binsof(ch0_vld.hi);
        bins ch0_lo  = binsof(ch0_vld.lo);
        bins ch1_hi  = binsof(ch1_vld.hi);
        bins ch1_lo  = binsof(ch1_vld.lo);
        bins ch2_hi  = binsof(ch2_vld.hi);
        bins ch2_lo  = binsof(ch2_vld.lo);
        // 关键组合：通道使能+valid高
        bins ch0_en_vld = binsof(ch0_en.en) && binsof(ch0_vld.hi);
        bins ch1_en_vld = binsof(ch1_en.en) && binsof(ch1_vld.hi);
        bins ch2_en_vld = binsof(ch2_en.en) && binsof(ch2_vld.hi);
        // 关键组合：通道禁用+valid高（测试禁用场景）
        bins ch0_dis_vld = binsof(ch0_en.dis) && binsof(ch0_vld.hi);
        bins ch1_dis_vld = binsof(ch1_en.dis) && binsof(ch1_vld.hi);
        bins ch2_dis_vld = binsof(ch2_en.dis) && binsof(ch2_vld.hi);
      }
    endgroup

    // 覆盖率组4：仲裁器优先级覆盖（每个通道的所有优先级）
    covergroup cg_arbiter_priority;
      ch0_prio: coverpoint arb_vif.mon_ck.slv_prios[0] {  // 通道0优先级
        bins ch_prio0 = {0};  // 最高优先级
        bins ch_prio1 = {1};
        bins ch_prio2 = {2};
        bins ch_prio3 = {3};  // 最低优先级
      }
      ch1_prio: coverpoint arb_vif.mon_ck.slv_prios[1] {  // 通道1优先级
        bins ch_prio0 = {0};
        bins ch_prio1 = {1};
        bins ch_prio2 = {2};
        bins ch_prio3 = {3};
      }
      ch2_prio: coverpoint arb_vif.mon_ck.slv_prios[2] {  // 通道2优先级
        bins ch_prio0 = {0};
        bins ch_prio1 = {1};
        bins ch_prio2 = {2};
        bins ch_prio3 = {3};
      }
    endgroup

    // 覆盖率组5：格式化器包长度覆盖（合法包长度+通道ID）
    covergroup cg_formatter_length;
      id: coverpoint fmt_vif.mon_ck.fmt_chid {  // 通道ID
        bins ch0 = {0};
        bins ch1 = {1};
        bins ch2 = {2};
        illegal_bins illegal = default;  // 非法ID（默认不允许）
      }
      length: coverpoint fmt_vif.mon_ck.fmt_length {  // 包长度
        bins len4  = {4};   // 4B
        bins len8  = {8};   // 8B
        bins len16 = {16};  // 16B
        bins len32 = {32};  // 32B
        illegal_bins illegal = default;  // 非法长度（默认不允许）
      }
    endgroup

    // 覆盖率组6：格式化器请求到授权的延迟覆盖
    covergroup cg_formatter_grant();
      delay_req_to_grant: coverpoint this.delay_req_to_grant {
        bins delay1 = {1};          // 1个时钟周期延迟
        bins delay2 = {2};          // 2个时钟周期延迟
        bins delay3_or_more = {[3:10]};  // 3~10个时钟周期延迟
        illegal_bins illegal = {0}; // 0延迟（非法，请求后至少1个周期授权）
      }
    endgroup

    // 构造函数：实例化所有覆盖率组
    function new(string name="mcdf_coverage");
      this.name = name;
      this.cg_mcdf_reg_write_read = new();
      this.cg_mcdf_reg_illegal_access = new();
      this.cg_channel_disable = new();
      this.cg_arbiter_priority = new();
      this.cg_formatter_length = new();
      this.cg_formatter_grant = new();
    endfunction

    // 主运行任务：并行执行所有覆盖率采样任务
    task run();
      fork 
        this.do_reg_sample();      // 寄存器场景采样
        this.do_channel_sample();  // 通道禁用场景采样
        this.do_arbiter_sample();  // 仲裁器优先级采样
        this.do_formater_sample(); // 格式化器场景采样
      join
    endtask

    // 寄存器场景采样任务：复位释放后，每个时钟周期采样寄存器覆盖率
    task do_reg_sample();
      forever begin
        @(posedge reg_vif.clk iff reg_vif.rstn);
        this.cg_mcdf_reg_write_read.sample();
        this.cg_mcdf_reg_illegal_access.sample();
      end
    endtask

    // 通道禁用场景采样任务：有通道valid为高时，采样覆盖率
    task do_channel_sample();
      forever begin
        @(posedge mcdf_vif.clk iff mcdf_vif.rstn);
        if(chnl_vifs[0].mon_ck.ch_valid===1
          || chnl_vifs[1].mon_ck.ch_valid===1
          || chnl_vifs[2].mon_ck.ch_valid===1)
          this.cg_channel_disable.sample();
      end
    endtask

    // 仲裁器优先级采样任务：有通道请求时，采样覆盖率
    task do_arbiter_sample();
      forever begin
        @(posedge arb_vif.clk iff arb_vif.rstn);
        if(arb_vif.slv_reqs[0]!==0 || arb_vif.slv_reqs[1]!==0 || arb_vif.slv_reqs[2]!==0)
          this.cg_arbiter_priority.sample();
      end
    endtask

    // 格式化器场景采样任务：并行采样包长度和请求-授权延迟
    task do_formater_sample();
      fork
        // 采样包长度覆盖率：有格式化器请求时采样
        forever begin
          @(posedge fmt_vif.clk iff fmt_vif.rstn);
          if(fmt_vif.mon_ck.fmt_req === 1)
            this.cg_formatter_length.sample();
        end
        // 采样请求-授权延迟覆盖率：计算延迟并采样
        forever begin
          @(posedge fmt_vif.mon_ck.fmt_req);  // 检测到格式化器请求
          this.delay_req_to_grant = 0;        // 延迟计数器清零
          forever begin
            if(fmt_vif.fmt_grant === 1) begin  // 检测到授权
              this.cg_formatter_grant.sample();// 采样延迟覆盖率
              break;
            end
            else begin  // 未授权，延迟计数器加1
              @(posedge fmt_vif.clk);
              this.delay_req_to_grant++;
            end
          end
        end
      join
    endtask

    // 报告函数：输出各覆盖率组的覆盖率结果
    function void do_report();
      string s;
      s = "\n---------------------------------------------------------------\n";
      s = {s, "COVERAGE SUMMARY \n"}; 
      s = {s, $sformatf("total coverage: %.1f \n", $get_coverage())};  // 总覆盖率
      s = {s, $sformatf("  cg_mcdf_reg_write_read coverage: %.1f \n", this.cg_mcdf_reg_write_read.get_coverage())};
      s = {s, $sformatf("  cg_mcdf_reg_illegal_access coverage: %.1f \n", this.cg_mcdf_reg_illegal_access.get_coverage())};
      s = {s, $sformatf("  cg_channel_disable_test coverage: %.1f \n", this.cg_channel_disable.get_coverage())};
      s = {s, $sformatf("  cg_arbiter_priority_test coverage: %.1f \n", this.cg_arbiter_priority.get_coverage())};
      s = {s, $sformatf("  cg_formatter_length_test coverage: %.1f \n", this.cg_formatter_length.get_coverage())};
      s = {s, $sformatf("  cg_formatter_grant_test coverage: %.1f \n", this.cg_formatter_grant.get_coverage())};
      s = {s, "---------------------------------------------------------------\n"};
      rpt_pkg::rpt_msg($sformatf("[%s]",this.name), s, rpt_pkg::INFO, rpt_pkg::TOP);
    endfunction

    // 接口绑定函数：绑定所有需要的DUT接口
    virtual function void set_interface(virtual chnl_intf ch_vifs[3] 
                                        ,virtual reg_intf reg_vif
                                        ,virtual arb_intf arb_vif
                                        ,virtual fmt_intf fmt_vif
                                        ,virtual mcdf_intf mcdf_vif
                                      );
      this.chnl_vifs = ch_vifs;
      this.arb_vif = arb_vif;
      this.reg_vif = reg_vif;
      this.fmt_vif = fmt_vif;
      this.mcdf_vif = mcdf_vif;
      // 检查接口是否为空
      if(chnl_vifs[0] == null || chnl_vifs[1] == null || chnl_vifs[2] == null)
        $error("chnl interface handle is NULL, please check if target interface has been intantiated");
      if(arb_vif == null)
        $error("arb interface handle is NULL, please check if target interface has been intantiated");
      if(reg_vif == null)
        $error("reg interface handle is NULL, please check if target interface has been intantiated");
      if(fmt_vif == null)
        $error("fmt interface handle is NULL, please check if target interface has been intantiated");
      if(mcdf_vif == null)
        $error("mcdf interface handle is NULL, please check if target interface has been intantiated");
    endfunction
  endclass

  // -----------------------------------------------------------------------------
  // 5. 验证环境（mcdf_env）：集成所有验证组件，管理组件间的数据通路
  // 核心功能：实例化Agent、Checker、Coverage，绑定组件间的mailbox
  // -----------------------------------------------------------------------------
  class mcdf_env;
    chnl_agent chnl_agts[3];  // 3个通道的Agent（包含Driver/Monitor）
    reg_agent reg_agt;        // 寄存器Agent
    fmt_agent fmt_agt;        // 格式化器Agent
    mcdf_checker chker;       // Checker实例
    mcdf_coverage cvrg;       // 覆盖率实例
    protected string name;    // 环境名称

    // 构造函数：实例化所有组件，绑定数据通路
    function new(string name = "mcdf_env");
      this.name = name;
      this.chker = new();  // 实例化Checker

      // 实例化3个通道Agent，绑定Monitor的mailbox到Checker的chnl_mbs（传递输入数据）
      foreach(chnl_agts[i]) begin
        this.chnl_agts[i] = new($sformatf("chnl_agts[%0d]",i));
        this.chnl_agts[i].monitor.mon_mb = this.chker.chnl_mbs[i];
      end

      // 实例化寄存器Agent，绑定Monitor的mailbox到Checker的reg_mb（传递寄存器交易）
      this.reg_agt = new("reg_agt");
      this.reg_agt.monitor.mon_mb = this.chker.reg_mb;

      // 实例化格式化器Agent，绑定Monitor的mailbox到Checker的fmt_mb（传递DUT输出数据）
      this.fmt_agt = new("fmt_agt");
      this.fmt_agt.monitor.mon_mb = this.chker.fmt_mb;

      this.cvrg = new();  // 实例化覆盖率收集器
      $display("%s instantiated and connected objects", this.name);
    endfunction

    // 主运行任务：启动所有组件
    virtual task run();
      $display($sformatf("*****************%s started********************", this.name));
      this.do_config();  // 组件配置（虚函数，可被子类重写）
      fork
        this.chnl_agts[0].run();
        this.chnl_agts[1].run();
        this.chnl_agts[2].run();
        this.reg_agt.run();
        this.fmt_agt.run();
        this.chker.run();
        this.cvrg.run();
      join
    endtask

    // 组件配置函数：虚函数，默认空实现，子类可重写
    virtual function void do_config();
    endfunction

    // 报告函数：调用Checker和Coverage的报告函数
    virtual function void do_report();
      this.chker.do_report();
      this.cvrg.do_report();
    endfunction

  endclass

  // -----------------------------------------------------------------------------
  // 6. 基础测试类（mcdf_base_test）：所有测试用例的基类
  // 核心功能：提供通用测试流程、寄存器操作接口、组件实例化和绑定
  // -----------------------------------------------------------------------------
  class mcdf_base_test;
    chnl_generator chnl_gens[3];  // 3个通道的生成器（生成输入数据）
    reg_generator reg_gen;        // 寄存器生成器（生成寄存器交易）
    fmt_generator fmt_gen;        // 格式化器生成器（配置格式化器）
    mcdf_env env;                 // 验证环境实例
    protected string name;        // 测试用例名称
    local int timeout = 10;       // 超时时间（10ms，避免仿真挂起）

    // 构造函数：实例化Env和Generator，绑定Generator到Agent的Driver
    function new(string name = "mcdf_base_test");
      this.name = name;
      this.env = new("env");  // 实例化验证环境

      // 实例化3个通道Generator，绑定请求/响应mailbox到Agent的Driver
      foreach(this.chnl_gens[i]) begin
        this.chnl_gens[i] = new();
        this.env.chnl_agts[i].driver.req_mb = this.chnl_gens[i].req_mb;
        this.env.chnl_agts[i].driver.rsp_mb = this.chnl_gens[i].rsp_mb;
      end

      // 实例化寄存器Generator，绑定mailbox到Agent的Driver
      this.reg_gen = new();
      this.env.reg_agt.driver.req_mb = this.reg_gen.req_mb;
      this.env.reg_agt.driver.rsp_mb = this.reg_gen.rsp_mb;

      // 实例化格式化器Generator，绑定mailbox到Agent的Driver
      this.fmt_gen = new();
      this.env.fmt_agt.driver.req_mb = this.fmt_gen.req_mb;
      this.env.fmt_agt.driver.rsp_mb = this.fmt_gen.rsp_mb;

      // 配置日志文件名称，清理历史日志
      rpt_pkg::logname = {this.name, "_check.log"};
      rpt_pkg::clean_log();
      $display("%s instantiated and connected objects", this.name);
    endfunction

    // 主运行任务：执行测试流程
    virtual task run();
      fork
        env.run();  // 启动验证环境（后台运行）
      join_none

      // 输出测试启动日志
      rpt_pkg::rpt_msg("[TEST]",
        $sformatf("=====================%s AT TIME %0t STARTED=====================", this.name, $time),
        rpt_pkg::INFO,
        rpt_pkg::HIGH);

      // 测试流程：寄存器配置 → 格式化器配置 → 数据传输 → 看门狗超时
      this.do_reg();         // 寄存器配置（虚函数，子类重写）
      this.do_formatter();   // 格式化器配置（虚函数，子类重写）
      fork
        this.do_data();      // 数据传输（虚函数，子类重写）
        this.do_watchdog();  // 超时保护
      join_any  // 任一任务完成即退出

      // 输出测试结束日志
      rpt_pkg::rpt_msg("[TEST]",
        $sformatf("=====================%s AT TIME %0t FINISHED=====================", this.name, $time),
        rpt_pkg::INFO,
        rpt_pkg::HIGH);

      this.do_report();  // 输出测试报告
      $finish();         // 结束仿真
    endtask

    // 虚函数：寄存器配置（默认空实现，子类重写）
    virtual task do_reg();
    endtask

    // 虚函数：格式化器配置（默认空实现，子类重写）
    virtual task do_formatter();
    endtask

    // 虚函数：数据传输（默认空实现，子类重写）
    virtual task do_data();
    endtask

    // 看门狗任务：超时保护，避免仿真无限挂起
    virtual task do_watchdog();
      rpt_pkg::rpt_msg("[TEST]",
        $sformatf("=====================%s AT TIME %0t WATCHDOG GUARDING=====================", this.name, $time),
        rpt_pkg::INFO,
        rpt_pkg::HIGH);
      #(this.timeout * 1ms);  // 等待10ms
      rpt_pkg::rpt_msg("[TEST]",
        $sformatf("=====================%s AT TIME %0t WATCHDOG BARKING=====================", this.name, $time),
        rpt_pkg::INFO,
        rpt_pkg::HIGH);
    endtask

    // 报告函数：调用Env的报告函数和日志模块的报告函数
    virtual function void do_report();
      this.env.do_report();
      rpt_pkg::do_report();
    endfunction

    // 接口绑定函数：将所有DUT接口绑定到Env
    virtual function void set_interface(virtual chnl_intf ch0_vif 
                                        ,virtual chnl_intf ch1_vif 
                                        ,virtual chnl_intf ch2_vif 
                                        ,virtual reg_intf reg_vif
                                        ,virtual arb_intf arb_vif
                                        ,virtual fmt_intf fmt_vif
                                        ,virtual mcdf_intf mcdf_vif
                                      );
      this.env.chnl_agts[0].set_interface(ch0_vif);
      this.env.chnl_agts[1].set_interface(ch1_vif);
      this.env.chnl_agts[2].set_interface(ch2_vif);
      this.env.reg_agt.set_interface(reg_vif);
      this.env.fmt_agt.set_interface(fmt_vif);
      this.env.chker.set_interface(mcdf_vif, '{ch0_vif, ch1_vif, ch2_vif}, arb_vif);
      this.env.cvrg.set_interface('{ch0_vif, ch1_vif, ch2_vif}, reg_vif, arb_vif, fmt_vif, mcdf_vif);
    endfunction

    // 辅助函数：比较两个值，输出对比结果日志
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

    // 辅助任务：发送寄存器IDLE命令
    virtual task idle_reg();
      void'(reg_gen.randomize() with {cmd == `IDLE; addr == 0; data == 0;});
      reg_gen.start();
    endtask

    // 辅助任务：写寄存器
    // addr：寄存器地址；data：写入数据
    virtual task write_reg(bit[7:0] addr, bit[31:0] data);
      void'(reg_gen.randomize() with {cmd == `WRITE; addr == local::addr; data == local::data;});
      reg_gen.start();
    endtask

    // 辅助任务：读寄存器
    // addr：寄存器地址；data：读出数据（输出）
    virtual task read_reg(bit[7:0] addr, output bit[31:0] data);
      void'(reg_gen.randomize() with {cmd == `READ; addr == local::addr;});
      reg_gen.start();
      data = reg_gen.data;
    endtask
  endclass

  // -----------------------------------------------------------------------------
  // 7. 测试用例1：基础数据一致性测试（mcdf_data_consistence_basic_test）
  // 测试目的：验证基本配置下的数据传输一致性，覆盖固定长度、优先级和使能配置
  // -----------------------------------------------------------------------------
  class mcdf_data_consistence_basic_test extends mcdf_base_test;
    function new(string name = "mcdf_data_consistence_basic_test");
      super.new(name);
    endfunction

    // 重写寄存器配置：配置3个通道的固定参数（len/prio/en），并读写校验
    task do_reg();
      bit[31:0] wr_val, rd_val;
      // 通道0：len=8B（1<<3）、prio=0（最高）、en=1（使能）
      wr_val = (1<<3)+(0<<1)+1;
      this.write_reg(`SLV0_RW_ADDR, wr_val);
      this.read_reg(`SLV0_RW_ADDR, rd_val);
      void'(this.diff_value(wr_val, rd_val, "SLV0_WR_REG"));

      // 通道1：len=16B（2<<3）、prio=1、en=1
      wr_val = (2<<3)+(1<<1)+1;
      this.write_reg(`SLV1_RW_ADDR, wr_val);
      this.read_reg(`SLV1_RW_ADDR, rd_val);
      void'(this.diff_value(wr_val, rd_val, "SLV1_WR_REG"));

      // 通道2：len=32B（3<<3）、prio=2、en=1
      wr_val = (3<<3)+(2<<1)+1;
      this.write_reg(`SLV2_RW_ADDR, wr_val);
      this.read_reg(`SLV2_RW_ADDR, rd_val);
      void'(this.diff_value(wr_val, rd_val, "SLV2_WR_REG"));

      // 发送IDLE命令，结束寄存器配置
      this.idle_reg();
    endtask

    // 重写格式化器配置：长FIFO+高带宽（低延迟场景）
    task do_formatter();
      void'(fmt_gen.randomize() with {fifo == LONG_FIFO; bandwidth == HIGH_WIDTH;});
      fmt_gen.start();
    endtask

    // 重写数据传输：3个通道各传输100个数据包，固定参数
    task do_data();
      // 通道0：100个包，data_nidle=0，pkt_nidle=1，数据长度8B
      void'(chnl_gens[0].randomize() with {ntrans==100; ch_id==0; data_nidles==0; pkt_nidles==1; data_size==8; });
      // 通道1：100个包，data_nidle=1，pkt_nidle=4，数据长度16B
      void'(chnl_gens[1].randomize() with {ntrans==100; ch_id==1; data_nidles==1; pkt_nidles==4; data_size==16;});
      // 通道2：100个包，data_nidle=2，pkt_nidle=8，数据长度32B
      void'(chnl_gens[2].randomize() with {ntrans==100; ch_id==2; data_nidles==2; pkt_nidles==8; data_size==32;});
      // 并行启动3个通道的数据传输
      fork
        chnl_gens[0].start();
        chnl_gens[1].start();
        chnl_gens[2].start();
      join
      #10us;  // 等待所有数据传输完成（留出足够时间）
    endtask
  endclass

  // -----------------------------------------------------------------------------
  // 8. 测试用例2：寄存器读写测试（mcdf_reg_read_write_test）
  // 测试目的：验证寄存器的读写功能，包括RW寄存器保留字段、RO寄存器写保护
  // -----------------------------------------------------------------------------
  class mcdf_reg_read_write_test extends mcdf_base_test;
    function new(string name = "mcdf_reg_read_write_test");
      super.new(name);
    endfunction

    // 重写寄存器配置：遍历所有RW/RO寄存器，写入测试图案并校验
    task do_reg();
      bit[7:0] chnl_rw_addrs[] = '{`SLV0_RW_ADDR, `SLV1_RW_ADDR, `SLV2_RW_ADDR};  // RW寄存器地址列表
      bit[7:0] chnl_ro_addrs[] = '{`SLV0_R_ADDR, `SLV1_R_ADDR, `SLV2_R_ADDR};      // RO寄存器地址列表
      int pwidth = `PAC_LEN_WIDTH + `PRIO_WIDTH + 1;  // 有效位宽度（len+prio+en）
      bit[31:0] check_pattern[] = '{32'h0000_C000, 32'hFFFF_0000};  // 测试图案
      bit[31:0] wr_val, rd_val;

      // 测试RW寄存器：写入测试图案，读取后校验有效位（保留位应忽略）
      foreach(chnl_rw_addrs[i]) begin
        foreach(check_pattern[i]) begin
          wr_val = check_pattern[i];
          this.write_reg(chnl_rw_addrs[i], wr_val);
          this.read_reg(chnl_rw_addrs[i], rd_val);
          // 仅对比有效位（(1<<pwidth)-1 是有效位掩码）
          void'(this.diff_value(wr_val & ((1<<pwidth)-1), rd_val));
        end
      end

      // 测试RO寄存器：写入数据（应被忽略），读取后校验保留位（应全0）
      foreach(chnl_ro_addrs[i]) begin
          wr_val = 32'hFFFF_FF00;  // 写入非法数据（保留位为1）
          this.write_reg(chnl_ro_addrs[i], wr_val);
          this.read_reg(chnl_ro_addrs[i], rd_val);
          // RO寄存器的高24位（保留位）应全0
          void'(this.diff_value(0 , rd_val & 32'hFFFFFF00));
      end

      // 发送IDLE命令
      this.idle_reg();
    endtask
  endclass
  
  // -----------------------------------------------------------------------------
  // 9. 测试用例3：寄存器稳定性测试（mcdf_reg_stability_test）
  // 测试目的：验证寄存器的稳定性，包括RW寄存器位翻转、RO寄存器读访问
  // -----------------------------------------------------------------------------
  class mcdf_reg_stability_test extends mcdf_base_test;
    function new(string name = "mcdf_reg_stability_test");
      super.new(name);
    endfunction

    // 重写寄存器配置：RW寄存器位翻转测试，RO寄存器读访问测试
    task do_reg();
      bit[7:0] chnl_rw_addrs[] = '{`SLV0_RW_ADDR, `SLV1_RW_ADDR, `SLV2_RW_ADDR};
      bit[7:0] chnl_ro_addrs[] = '{`SLV0_R_ADDR, `SLV1_R_ADDR, `SLV2_R_ADDR};
      int pwidth = `PAC_LEN_WIDTH + `PRIO_WIDTH + 1;  // 有效位宽度
      bit[31:0] check_pattern[] = '{((1<<pwidth)-1), 0, ((1<<pwidth)-1)};  // 翻转图案（全1→全0→全1）
      bit[31:0] wr_val, rd_val;

      // 测试RW寄存器：写入翻转图案，读取校验（验证位稳定性）
      foreach(chnl_rw_addrs[i]) begin
        foreach(check_pattern[i]) begin
          wr_val = check_pattern[i];
          this.write_reg(chnl_rw_addrs[i], wr_val);
          this.read_reg(chnl_rw_addrs[i], rd_val);
          void'(this.diff_value(wr_val, rd_val));
        end
      end

      // 测试RO寄存器：多次读访问（验证读稳定性）
      foreach(chnl_ro_addrs[i]) begin
          this.read_reg(chnl_ro_addrs[i], rd_val);
      end

      // 发送IDLE命令
      this.idle_reg();
    endtask
  endclass

  // -----------------------------------------------------------------------------
  // 10. 测试用例4：全随机测试（mcdf_full_random_test）
  // 测试目的：随机配置所有参数，覆盖更多边界场景（包括非法地址访问）
  // -----------------------------------------------------------------------------
  class mcdf_full_random_test extends mcdf_base_test;
    function new(string name = "mcdf_full_random_test");
      super.new(name);
    endfunction

    // 重写寄存器配置：随机配置3个通道参数，加入非法地址访问
    task do_reg();
      bit[7:0] addr;
      bit[31:0] wr_val, rd_val;
      // 通道0：随机len（0-3）、随机prio（0-3）、随机en（0-1）
      wr_val = ($urandom_range(0,3)<<3)+($urandom_range(0,3)<<1)+$urandom_range(0,1);
      this.write_reg(`SLV0_RW_ADDR, wr_val);
      this.read_reg(`SLV0_RW_ADDR, rd_val);
      void'(this.diff_value(wr_val, rd_val, "SLV0_WR_REG"));

      // 通道1：随机配置
      wr_val = ($urandom_range(0,3)<<3)+($urandom_range(0,3)<<1)+$urandom_range(0,1);
      this.write_reg(`SLV1_RW_ADDR, wr_val);
      this.read_reg(`SLV1_RW_ADDR, rd_val);
      void'(this.diff_value(wr_val, rd_val, "SLV1_WR_REG"));

      // 通道2：随机配置
      wr_val = ($urandom_range(0,3)<<3)+($urandom_range(0,3)<<1)+$urandom_range(0,1);
      this.write_reg(`SLV2_RW_ADDR, wr_val);
      this.read_reg(`SLV2_RW_ADDR, rd_val);
      void'(this.diff_value(wr_val, rd_val, "SLV2_WR_REG"));

      // 非法地址访问：随机选择0x20-0xFF的地址，写入并读取
      addr = $urandom_range(8'h20, 8'hFF);
      this.write_reg(addr, 32'hDEAD_BEEF);
      this.read_reg(addr, rd_val);

      // 发送IDLE命令
      this.idle_reg();
    endtask

    // 重写格式化器配置：随机选择短FIFO/超短FIFO，低带宽/超宽带宽
    task do_formatter();
      void'(fmt_gen.randomize() with {fifo inside {SHORT_FIFO, ULTRA_FIFO}; bandwidth inside {LOW_WIDTH, ULTRA_WIDTH};});
      fmt_gen.start();
    endtask

    // 重写数据传输：随机配置传输参数（包数量400-600，其他参数随机）
    task do_data();
      void'(chnl_gens[0].randomize() with {ntrans inside {[400:600]}; ch_id==0; data_nidles inside {[0:3]}; pkt_nidles inside {1,2,4,8}; data_size inside {8,16,32};});
      void'(chnl_gens[1].randomize() with {ntrans inside {[400:600]}; ch_id==1; data_nidles inside {[0:3]}; pkt_nidles inside {1,2,4,8}; data_size inside {8,16,32};});
      void'(chnl_gens[2].randomize() with {ntrans inside {[400:600]}; ch_id==2; data_nidles inside {[0:3]}; pkt_nidles inside {1,2,4,8}; data_size inside {8,16,32};});
      fork
        chnl_gens[0].start();
        chnl_gens[1].start();
        chnl_gens[2].start();
      join
      #10us; // wait until all data haven been transfered through MCDF
    endtask
  endclass
// =========================================================================
// 具体测试用例5：下游低带宽测试（mcdf_down_stream_low_bandwidth_test）
// 核心验证点：Vplan 5.0 通道切换 + 格式化器请求-授权延迟场景
// 测试设计思路：
// 1. 配置下游格式化器为低带宽+短/中FIFO，模拟下游处理能力不足的临界场景；
// 2. 3个通道同时发送突发数据（无间隙），给DUT施加高数据压力；
// 3. 验证高负载下：通道切换的正确性、格式化器请求到授权的延迟稳定性、数据传输一致性；
// 4. 配套覆盖率组：cg_formatter_grant（统计请求-授权延迟分布）
// =========================================================================
class mcdf_down_stream_low_bandwidth_test extends mcdf_base_test;
  // 构造函数：初始化测试用例实例
  // 注意：原代码存在笔误（形参name默认值为"mcdf_data_consistence_basic_test"），
  // 实际应与类名一致，注释中已标注，建议修正为"mcdf_down_stream_low_bandwidth_test"
  function new(string name = "mcdf_data_consistence_basic_test");
    super.new(name);  // 调用基类构造函数，初始化环境、生成器等组件
  endfunction

  // ======================================================================
  // 任务：寄存器配置（固定参数，确保数据传输场景可复现）
  // 配置逻辑：3个通道均使能，按优先级从高到低分配，包长度递增，便于观察通道切换
  // ======================================================================
  task do_reg();
    bit[31:0] wr_val, rd_val;  // wr_val：写入值；rd_val：读出值（用于写后读校验）

    // 通道0配置：包长度=8字节（len=1 → 4<<1=8）、优先级=0（最高）、使能=1
    // 配置值计算：(len<<3) + (prio<<1) + en → (1<<3)=8, (0<<1)=0, +1 → 9（0x09）
    wr_val = (1<<3)+(0<<1)+1;
    this.write_reg(`SLV0_RW_ADDR, wr_val);  // 写通道0读写寄存器
    this.read_reg(`SLV0_RW_ADDR, rd_val);   // 读通道0读写寄存器（写后读校验）
    void'(this.diff_value(wr_val, rd_val, "SLV0_WR_REG"));  // 对比读写值，验证配置一致性

    // 通道1配置：包长度=16字节（len=2 → 4<<2=16）、优先级=1、使能=1
    // 配置值计算：(2<<3)=16, (1<<1)=2, +1 → 19（0x13）
    wr_val = (2<<3)+(1<<1)+1;
    this.write_reg(`SLV1_RW_ADDR, wr_val);  // 写通道1读写寄存器
    this.read_reg(`SLV1_RW_ADDR, rd_val);   // 读通道1读写寄存器（写后读校验）
    void'(this.diff_value(wr_val, rd_val, "SLV1_WR_REG"));  // 对比读写值，验证配置一致性

    // 通道2配置：包长度=32字节（len=3 → 4<<3=32）、优先级=2、使能=1
    // 配置值计算：(3<<3)=24, (2<<1)=4, +1 → 29（0x1D）
    wr_val = (3<<3)+(2<<1)+1;
    this.write_reg(`SLV2_RW_ADDR, wr_val);  // 写通道2读写寄存器
    this.read_reg(`SLV2_RW_ADDR, rd_val);   // 读通道2读写寄存器（写后读校验）
    void'(this.diff_value(wr_val, rd_val, "SLV2_WR_REG"));  // 对比读写值，验证配置一致性

    this.idle_reg();  // 发送IDLE命令，结束寄存器配置阶段（避免多余寄存器操作）
  endtask

  // ======================================================================
  // 任务：格式化器配置（核心：模拟下游低处理能力场景）
  // 配置逻辑：限制FIFO深度和带宽，故意降低下游接收效率，制造请求-授权延迟
  // ======================================================================
  // 配置格式化器为短/中FIFO + 低/中带宽，模拟临界数据路径（下游处理瓶颈）
  task do_formatter();
    // 随机化约束：
    // - fifo：仅选择SHORT_FIFO（短FIFO）/MED_FIFO（中FIFO）→ 缓存能力弱
    // - bandwidth：仅选择LOW_WIDTH（低带宽）/MED_WIDTH（中带宽）→ 数据传输速率低
    // 目的：制造格式化器"忙"状态，使fmt_req到fmt_grant产生明显延迟，覆盖延迟场景
    void'(fmt_gen.randomize() with {fifo inside {SHORT_FIFO, MED_FIFO}; 
                                    bandwidth inside {LOW_WIDTH, MED_WIDTH};});
    fmt_gen.start();  // 启动格式化器生成器，发送配置transaction到DUT
  endtask

  // ======================================================================
  // 任务：通道数据发送（突发数据，最大化DUT负载）
  // 设计逻辑：3个通道并行发送无间隙突发数据，触发高并发和通道切换
  // ======================================================================
  // 突发数据包传输，给DUT施加最大数据压力（触发通道切换和延迟场景）
  task do_data();
    // 通道0：300笔交易，无数据间隙（data_nidles=0），小包间隙（pkt_nidles=1），数据大小=8字节
    // 约束说明：无数据间隙→数据连续发送，小包间隙→包间仅1个时钟空闲，最大化流量
    void'(chnl_gens[0].randomize() with {ntrans==300;    // 交易数：300笔
                                         ch_id==0;       // 通道ID：0
                                         data_nidles==0; // 数据间空闲周期：0（连续数据）
                                         pkt_nidles==1;  // 包间空闲周期：1（小包间隔）
                                         data_size==8;});// 单包数据大小：8字节（匹配通道0配置）

    // 通道1：300笔交易，无数据间隙，小包间隙，数据大小=16字节（匹配通道1配置）
    void'(chnl_gens[1].randomize() with {ntrans==300;    // 交易数：300笔
                                         ch_id==1;       // 通道ID：1
                                         data_nidles==0; // 数据间空闲周期：0（连续数据）
                                         pkt_nidles==1;  // 包间空闲周期：1（小包间隔）
                                         data_size==16;});// 单包数据大小：16字节（匹配通道1配置）

    // 通道2：300笔交易，无数据间隙，小包间隙，数据大小=32字节（匹配通道2配置）
    void'(chnl_gens[2].randomize() with {ntrans==300;    // 交易数：300笔
                                         ch_id==2;       // 通道ID：2
                                         data_nidles==0; // 数据间空闲周期：0（连续数据）
                                         pkt_nidles==1;  // 包间空闲周期：1（小包间隔）
                                         data_size==32;});// 单包数据大小：32字节（匹配通道2配置）

    // 并行启动3个通道的数据发送（模拟最大并发负载，触发仲裁器频繁调度和通道切换）
    fork
      chnl_gens[0].start();
      chnl_gens[1].start();
      chnl_gens[2].start();
    join

    #10us;  // 等待所有数据传输完成：高负载+延迟场景下，预留足够时间让DUT处理所有数据
            // 避免因处理不及时导致邮箱残留数据，影响测试报告准确性
  endtask
endclass

endpackage  // MCDF验证包结束（包含所有验证组件和测试用例）