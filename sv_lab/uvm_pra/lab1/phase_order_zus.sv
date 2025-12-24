// 定义UVM包，用于封装演示phase执行顺序的所有组件和测试类
package phase_order_pkg;
  // 导入UVM核心包，必须先导入才能使用UVM相关类和宏
  import uvm_pkg::*;
  // 包含UVM宏定义（如`uvm_component_utils、`uvm_info等）
  `include "uvm_macros.svh"

  // ------------------------------
  // 基础组件类comp2：继承自uvm_component，无自组件
  // 演示单个组件的各phase执行逻辑
  // ------------------------------
  class comp2 extends uvm_component;
    // UVM工厂注册宏：将comp2类注册到UVM工厂，支持动态创建实例
    `uvm_component_utils(comp2)

    // 组件构造函数：UVM组件必须实现new函数，参数为组件名和父组件
    // name：组件实例名，parent：父组件句柄（null表示无父组件）
    function new(string name = "comp2", uvm_component parent = null);
      super.new(name, parent); // 调用父类（uvm_component）的构造函数
      // 打印组件创建信息，UVM_LOW表示最低日志级别（始终打印）
      `uvm_info("CREATE", $sformatf("unit type [%s] created", name), UVM_LOW)
    endfunction

    // BUILD阶段：UVM生命周期第一个核心阶段，用于创建子组件、配置参数
    // phase：当前执行的phase句柄，所有phase方法都接收该参数
    function void build_phase(uvm_phase phase);
      super.build_phase(phase); // 必须调用父类的build_phase，保证UVM核心逻辑执行
      `uvm_info("BUILD", "comp2 build phase entered", UVM_LOW) // 打印进入BUILD阶段
      `uvm_info("BUILD", "comp2 build phase exited", UVM_LOW)  // 打印退出BUILD阶段
    endfunction

    // CONNECT阶段：BUILD之后，用于组件间的连接（如TLM端口绑定）
    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase); // 调用父类connect_phase
      `uvm_info("CONNECT", "comp2 connect phase entered", UVM_LOW)
      `uvm_info("CONNECT", "comp2 connect phase exited", UVM_LOW)
    endfunction

    // RUN阶段：UVM唯一的任务（task）型phase，可执行时序逻辑（含延迟）
    task run_phase(uvm_phase phase);
      super.run_phase(phase); // 调用父类run_phase
      `uvm_info("RUN", "comp2 run phase entered", UVM_LOW)
      `uvm_info("RUN", "comp2 run phase entered", UVM_LOW) // 注：原代码重复打印，保留原样
    endtask

    // REPORT阶段：RUN之后，用于生成测试报告、打印统计信息
    function void report_phase(uvm_phase phase);
      super.report_phase(phase); // 调用父类report_phase
      `uvm_info("REPORT", "comp2 report phase entered", UVM_LOW)
      `uvm_info("REPORT", "comp2 report phase exited", UVM_LOW)   
    endfunction
  endclass
  
  // ------------------------------
  // 基础组件类comp3：结构与comp2完全一致，用于被comp1实例化
  // 演示多个子组件的phase执行顺序
  // ------------------------------
  class comp3 extends uvm_component;
    `uvm_component_utils(comp3) // 注册到UVM工厂

    function new(string name = "comp3", uvm_component parent = null);
      super.new(name, parent);
      `uvm_info("CREATE", $sformatf("unit type [%s] created", name), UVM_LOW)
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      `uvm_info("BUILD", "comp3 build phase entered", UVM_LOW)
      `uvm_info("BUILD", "comp3 build phase exited", UVM_LOW)
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      `uvm_info("CONNECT", "comp3 connect phase entered", UVM_LOW)
      `uvm_info("CONNECT", "comp3 connect phase exited", UVM_LOW)
    endfunction

    task run_phase(uvm_phase phase);
      super.run_phase(phase);
      `uvm_info("RUN", "comp3 run phase entered", UVM_LOW)
      `uvm_info("RUN", "comp3 run phase entered", UVM_LOW)
    endtask

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("REPORT", "comp3 report phase entered", UVM_LOW)
      `uvm_info("REPORT", "comp3 report phase exited", UVM_LOW)   
    endfunction
  endclass
  
  // ------------------------------
  // 复合组件类comp1：包含comp2和comp3子组件，演示父子组件的phase执行顺序
  // ------------------------------
  class comp1 extends uvm_component;
    comp2 c2; // 声明comp2类型的子组件句柄
    comp3 c3; // 声明comp3类型的子组件句柄
    `uvm_component_utils(comp1) // 注册到UVM工厂

    function new(string name = "comp1", uvm_component parent = null);
      super.new(name, parent);
      `uvm_info("CREATE", $sformatf("unit type [%s] created", name), UVM_LOW)
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      `uvm_info("BUILD", "comp1 build phase entered", UVM_LOW)
      // 通过UVM工厂创建子组件：type_id::create(实例名, 父组件句柄)
      // this表示comp1是c2/c3的父组件，UVM会维护组件层次结构
      c2 = comp2::type_id::create("c2", this);
      c3 = comp3::type_id::create("c3", this);
      `uvm_info("BUILD", "comp1 build phase exited", UVM_LOW)
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      `uvm_info("CONNECT", "comp1 connect phase entered", UVM_LOW)
      `uvm_info("CONNECT", "comp1 connect phase exited", UVM_LOW)
    endfunction

    task run_phase(uvm_phase phase);
      super.run_phase(phase);
      `uvm_info("RUN", "comp1 run phase entered", UVM_LOW)
      `uvm_info("RUN", "comp1 run phase entered", UVM_LOW)
    endtask

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("REPORT", "comp1 report phase entered", UVM_LOW)
      `uvm_info("REPORT", "comp1 report phase exited", UVM_LOW)   
    endfunction
  endclass

  // ------------------------------
  // 测试类phase_order_test：UVM测试的顶层组件（继承uvm_test）
  // 所有测试必须继承uvm_test，是UVM树的根节点（除uvm_top）
  // ------------------------------
  class phase_order_test extends uvm_test;
    comp1 c1; // 声明顶层复合组件句柄
    `uvm_component_utils(phase_order_test) // 注册到UVM工厂

    function new(string name = "phase_order_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      `uvm_info("BUILD", "phase_order_test build phase entered", UVM_LOW)
      // 创建comp1实例，父组件为当前test（UVM树的顶层）
      c1 = comp1::type_id::create("c1", this);
      `uvm_info("BUILD", "phase_order_test build phase exited", UVM_LOW)
    endfunction

    function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      `uvm_info("CONNECT", "phase_order_test connect phase entered", UVM_LOW)
      `uvm_info("CONNECT", "phase_order_test connect phase exited", UVM_LOW)
    endfunction

    // RUN阶段：核心测试逻辑，通过objection控制测试结束
    task run_phase(uvm_phase phase);
      super.run_phase(phase);
      `uvm_info("RUN", "phase_order_test run phase entered", UVM_LOW)
      // 提起objection：告诉UVM测试正在运行，不要提前结束
      phase.raise_objection(this);
      #1us; // 模拟1微秒的测试时序逻辑
      // 放下objection：告诉UVM测试逻辑完成，可以结束
      phase.drop_objection(this);
      `uvm_info("RUN", "phase_order_test run phase exited", UVM_LOW)
    endtask

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("REPORT", "phase_order_test report phase entered", UVM_LOW)
      `uvm_info("REPORT", "phase_order_test report phase exited", UVM_LOW)    
    endfunction
    
    // RESET阶段：UVM的预定义phase，在run_phase之前执行（属于pre-run phases）
    task reset_phase(uvm_phase phase);
      `uvm_info("RESET", "phase_order_test reset phase entered", UVM_LOW)
      phase.raise_objection(this); // objection同样适用于reset/main等子phase
      #1us; // 模拟复位时序（如系统复位）
      phase.drop_objection(this);
      `uvm_info("RESET", "phase_order_test reset phase exited", UVM_LOW)
    endtask
    
    // MAIN阶段：UVM的预定义phase，在reset之后、run之前执行（属于pre-run phases）
    task main_phase(uvm_phase phase);
      `uvm_info("MAIN", "phase_order_test main phase entered", UVM_LOW)
      phase.raise_objection(this);
      #1us; // 模拟主测试逻辑前的初始化
      phase.drop_objection(this);
      `uvm_info("MAIN", "phase_order_test main phase exited", UVM_LOW)
    endtask 
  endclass
endpackage

// ------------------------------
// 顶层模块phase_order：UVM测试的入口
// 所有SystemVerilog代码必须包含在module中，UVM也不例外
// ------------------------------
module phase_order;
  // 导入UVM核心包和自定义包
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import phase_order_pkg::*;

  // 初始块：SystemVerilog的入口，启动UVM测试
  initial begin
    // 启动UVM测试：参数为空字符串时，UVM会通过+UVM_TESTNAME命令行指定测试类
    // 也可直接写run_test("phase_order_test")指定测试类
    run_test(""); 
  end

endmodule