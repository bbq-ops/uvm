//--------------------------------------------------------------------------------------
// 1. 定义自定义接口：用于UVM验证环境与硬件侧的信号交互
//    这里是一个简单的示例接口，包含地址、数据、操作码信号
//--------------------------------------------------------------------------------------
interface uvm_config_if;
  logic [31:0] addr;  // 32位地址信号
  logic [31:0] data;  // 32位数据信号
  logic [ 1:0] op;    // 2位操作码（如读/写/空闲）
endinterface

//--------------------------------------------------------------------------------------
// 2. 定义UVM包：包含所有自定义的配置对象、组件、测试用例
//    包是SystemVerilog中封装代码的单元，避免命名冲突
//--------------------------------------------------------------------------------------
package uvm_config_pkg;
  // 导入UVM核心包和宏定义（UVM的基础依赖）
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  //--------------------------------------------------------------------------------------
  // 2.1 自定义配置对象：继承自uvm_object，用于批量传递配置参数
  //     优势：可以将多个相关配置参数封装成一个对象，通过uvm_config_db一次性传递
  //--------------------------------------------------------------------------------------
  class config_obj extends uvm_object;
    // 配置参数：分别给comp1和comp2使用的整型变量
    int comp1_var;
    int comp2_var;

    // UVM工厂注册宏：将该类注册到UVM工厂，支持工厂创建（type_id::create）
    `uvm_object_utils(config_obj)

    // 构造函数：初始化配置对象
    function new(string name = "config_obj");
      super.new(name);  // 调用父类uvm_object的构造函数
      // 打印创建信息，用于调试组件/对象的创建顺序
      `uvm_info("CREATE", $sformatf("config_obj type [%s] created", name), UVM_LOW)
    endfunction
  endclass

  //--------------------------------------------------------------------------------------
  // 2.2 自定义组件comp2：继承自uvm_component，是UVM的基础组件
  //     功能：在build_phase中从uvm_config_db获取配置（虚拟接口、整型变量、配置对象）
  //--------------------------------------------------------------------------------------
  class comp2 extends uvm_component;
    int var2;  // 组件内部的整型变量
    virtual uvm_config_if vif;  // 虚拟接口句柄（必须是virtual，才能绑定物理接口）
    config_obj cfg;  // 自定义配置对象的句柄

    // UVM工厂注册宏：组件类使用uvm_component_utils
    `uvm_component_utils(comp2)

    // 构造函数：初始化组件，设置父组件指针
    function new(string name = "comp2", uvm_component parent = null);
      super.new(name, parent);  // 调用父类uvm_component的构造函数
      var2 = 200;  // 初始化var2为默认值200
      `uvm_info("CREATE", $sformatf("unit type [%s] created", name), UVM_LOW)
    endfunction

    // BUILD阶段：UVM的静态阶段，用于创建子组件、获取配置（核心阶段）
    // 执行顺序：自顶向下（父组件→子组件）
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);  // 必须调用父类的build_phase，保证UVM核心机制运行
      `uvm_info("BUILD", "comp2 build phase entered", UVM_LOW)

      // ① 从uvm_config_db中获取虚拟接口（virtual interface）
      //    参数说明：
      //    this: 当前组件的句柄（表示从当前组件的路径开始查找）
      //    "": 空字符串表示当前组件的实例名（不限制子路径）
      //    "vif": 配置项的名称（与set时的名称一致）
      //    vif: 接收配置值的变量（输出参数）
      //    返回值：成功返回1，失败返回0（失败时打印错误）
      if(!uvm_config_db#(virtual uvm_config_if)::get(this, "", "vif", vif))
        `uvm_error("GETVIF", "no virtual interface is assigned")

      // ② 打印获取配置前的var2值（默认值200）
      `uvm_info("GETINT", $sformatf("before config get, var2 = %0d", var2), UVM_LOW)
      // 从uvm_config_db中获取整型变量var2（会覆盖默认值）
      uvm_config_db#(int)::get(this, "", "var2", var2);
      // 打印获取配置后的var2值（应该是test层设置的20）
      `uvm_info("GETINT", $sformatf("after config get, var2 = %0d", var2), UVM_LOW)

      // ③ 从uvm_config_db中获取自定义配置对象cfg
      uvm_config_db#(config_obj)::get(this, "", "cfg", cfg);
      // 打印配置对象中的comp2_var值（应该是test层设置的200）
      `uvm_info("GETOBJ", $sformatf("after config get, cfg.comp2_var = %0d", cfg.comp2_var), UVM_LOW)

      `uvm_info("BUILD", "comp2 build phase exited", UVM_LOW)
    endfunction
  endclass

  //--------------------------------------------------------------------------------------
  // 2.3 自定义组件comp1：继承自uvm_component，包含子组件comp2
  //     功能：获取配置，同时创建子组件comp2
  //--------------------------------------------------------------------------------------
  class comp1 extends uvm_component;
    int var1;  // 组件内部的整型变量
    comp2 c2;  // 子组件comp2的句柄
    config_obj cfg;  // 自定义配置对象的句柄
    virtual uvm_config_if vif;  // 虚拟接口句柄

    // UVM工厂注册宏
    `uvm_component_utils(comp1)

    // 构造函数
    function new(string name = "comp1", uvm_component parent = null);
      super.new(name, parent);
      var1 = 100;  // 初始化var1为默认值100
      `uvm_info("CREATE", $sformatf("unit type [%s] created", name), UVM_LOW)
    endfunction

    // BUILD阶段：获取配置，创建子组件comp2
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      `uvm_info("BUILD", "comp1 build phase entered", UVM_LOW)

      // ① 获取虚拟接口（与comp2的逻辑一致）
      if(!uvm_config_db#(virtual uvm_config_if)::get(this, "", "vif", vif))
        `uvm_error("GETVIF", "no virtual interface is assigned")

      // ② 获取整型变量var1，覆盖默认值
      `uvm_info("GETINT", $sformatf("before config get, var1 = %0d", var1), UVM_LOW)
      uvm_config_db#(int)::get(this, "", "var1", var1);
      `uvm_info("GETINT", $sformatf("after config get, var1 = %0d", var1), UVM_LOW)

      // ③ 获取自定义配置对象cfg
      uvm_config_db#(config_obj)::get(this, "", "cfg", cfg);
      `uvm_info("GETOBJ", $sformatf("after config get, cfg.comp1_var = %0d", cfg.comp1_var), UVM_LOW)

      // ④ 创建子组件comp2（UVM工厂创建方式，推荐使用）
      //    参数说明："c2"是子组件的实例名，this是父组件句柄（comp1是c2的父组件）
      c2 = comp2::type_id::create("c2", this);

      `uvm_info("BUILD", "comp1 build phase exited", UVM_LOW)
    endfunction
  endclass

  //--------------------------------------------------------------------------------------
  // 2.4 测试用例类：继承自uvm_test，是UVM验证环境的顶层组件
  //     功能：创建配置对象、设置uvm_config_db、创建顶层组件comp1
  //--------------------------------------------------------------------------------------
  class uvm_config_test extends uvm_test;
    comp1 c1;  // 顶层组件comp1的句柄
    config_obj cfg;  // 自定义配置对象的句柄

    // UVM工厂注册宏
    `uvm_component_utils(uvm_config_test)

    // 构造函数
    function new(string name = "uvm_config_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    // BUILD阶段：设置配置，创建组件（测试用例的核心配置阶段）
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      `uvm_info("BUILD", "uvm_config_test build phase entered", UVM_LOW)

      // ① 创建自定义配置对象实例（UVM工厂创建）
      cfg = config_obj::type_id::create("cfg");
      // 给配置对象的成员赋值
      cfg.comp1_var = 100;
      cfg.comp2_var = 200;
      // 将配置对象设置到uvm_config_db中
      //    参数说明：
      //    this: 当前组件（uvm_test_top）的句柄
      //    "*": 通配符，表示所有子组件都可以获取该配置（路径匹配）
      //    "cfg": 配置项的名称（与get时的名称一致）
      //    cfg: 要传递的配置值（输入参数）
      uvm_config_db#(config_obj)::set(this, "*", "cfg", cfg);

      // ② 设置整型变量到uvm_config_db中（指定具体路径）
      //    "c1": 仅comp1组件可以获取该var1（路径：uvm_test_top.c1）
      uvm_config_db#(int)::set(this, "c1", "var1", 10);
      //    "c1.c2": 仅comp2组件可以获取该var2（路径：uvm_test_top.c1.c2）
      uvm_config_db#(int)::set(this, "c1.c2", "var2", 20);

      // ③ 创建顶层组件comp1（父组件是uvm_test_top）
      c1 = comp1::type_id::create("c1", this);

      `uvm_info("BUILD", "uvm_config_test build phase exited", UVM_LOW)
    endfunction

    // RUN阶段：控制仿真的执行时间（UVM的动态阶段）
    task run_phase(uvm_phase phase);
      super.run_phase(phase);
      `uvm_info("RUN", "uvm_config_test run phase entered", UVM_LOW)
      // 提出异议：阻止UVM的run_phase提前结束（必须配对使用drop_objection）
      phase.raise_objection(this);
      // 仿真延时1微秒（控制测试用例的执行时间）
      #1us;
      // 撤销异议：允许UVM的run_phase结束，进入后续的report阶段
      phase.drop_objection(this);
      `uvm_info("RUN", "uvm_config_test run phase exited", UVM_LOW)
    endtask
  endclass
endpackage

//--------------------------------------------------------------------------------------
// 3. 顶层模块：实例化物理接口，设置虚拟接口到uvm_config_db，启动UVM测试
//--------------------------------------------------------------------------------------
module uvm_config;
  // 导入UVM核心包和自定义包
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import uvm_config_pkg::*;

  // 实例化物理接口（硬件侧的实际接口）
  uvm_config_if if0();

  initial begin
    // 将虚拟接口设置到uvm_config_db中（全局路径）
    //    uvm_root::get(): 获取UVM的根组件（全局最高层）
    //    "uvm_test_top.*": 表示uvm_test_top及其所有子组件都可以获取该接口
    uvm_config_db#(virtual uvm_config_if)::set(uvm_root::get(), "uvm_test_top.*", "vif", if0);
    // 启动UVM测试：空字符串表示使用UVM_DEFAULT_TEST_NAME，或通过+UVM_TESTNAME参数指定
    run_test(""); // empty test name
  end

endmodule