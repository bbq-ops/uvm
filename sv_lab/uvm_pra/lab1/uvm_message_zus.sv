// 定义自定义UVM包，包含配置对象、组件和测试用例
package uvm_message_pkg;
  // 导入UVM核心包，包含UVM的基础类（如uvm_object、uvm_component）和方法
  import uvm_pkg::*;
  // 包含UVM的宏定义（如`uvm_object_utils、`uvm_info、`uvm_component_utils）
  `include "uvm_macros.svh"
  
  // 定义配置对象：继承自uvm_object（UVM数据对象基类，无父组件，不属于组件层级）
  // 作用：存储测试用例的配置参数
  class config_obj extends uvm_object;
    // 将类注册到UVM工厂，允许通过工厂创建实例（UVM工厂机制的核心宏）
    `uvm_object_utils(config_obj)

    // 构造函数：uvm_object的构造函数仅需名称参数
    function new(string name = "config_obj");
      super.new(name); // 必须调用父类的构造函数
      // 打印对象创建信息：消息ID为"CREATE"，冗余度级别UVM_LOW（最低级别，默认会打印）
      `uvm_info("CREATE", $sformatf("config_obj type [%s] created", name), UVM_LOW)
    endfunction
  endclass
  
  // 定义UVM组件comp2：继承自uvm_component（UVM组件基类，属于组件层级，有父组件）
  // 作用：演示子组件的消息打印和控制
  class comp2 extends uvm_component;
    // 将组件注册到UVM工厂
    `uvm_component_utils(comp2)

    // 构造函数：uvm_component的构造函数需要名称和父组件参数
    function new(string name = "comp2", uvm_component parent = null);
      super.new(name, parent); // 必须调用父类的构造函数
      `uvm_info("CREATE", $sformatf("unit type [%s] created", name), UVM_LOW)
    endfunction

    // BUILD阶段：UVM的第一个主要phase，用于创建子组件和配置对象
    // 执行顺序：**自上而下**（父组件的build_phase先于子组件执行）
    function void build_phase(uvm_phase phase);
      super.build_phase(phase); // 必须调用父类的build_phase（UVM规范要求）
      `uvm_info("BUILD", "comp2 build phase entered", UVM_LOW)
      `uvm_info("BUILD", "comp2 build phase exited", UVM_LOW)
    endfunction

    // RUN阶段：UVM的主要运行阶段，用于执行测试逻辑（支持时序逻辑，因此用task定义）
    // 执行顺序：**所有组件的run_phase并行执行**
    task run_phase(uvm_phase phase);
      super.run_phase(phase); // 调用父类的run_phase
      `uvm_info("RUN", "comp2 run phase entered", UVM_LOW)
      `uvm_info("RUN", "comp2 run phase exited", UVM_LOW)
    endtask
  endclass

  // 定义UVM组件comp1：结构与comp2一致，用于演示多个子组件的消息控制
  class comp1 extends uvm_component;
    `uvm_component_utils(comp1)

    function new(string name = "comp1", uvm_component parent = null);
      super.new(name, parent);
      `uvm_info("CREATE", $sformatf("unit type [%s] created", name), UVM_LOW)
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      `uvm_info("BUILD", "comp1 build phase entered", UVM_LOW)
      `uvm_info("BUILD", "comp1 build phase exited", UVM_LOW)
    endfunction

    task run_phase(uvm_phase phase);
      super.run_phase(phase);
      `uvm_info("RUN", "comp1 run phase entered", UVM_LOW)
      `uvm_info("RUN", "comp1 run phase exited", UVM_LOW)
    endtask
  endclass

  // 定义UVM测试用例：继承自uvm_test（UVM组件层级的顶层组件，是测试的入口）
  class uvm_message_test extends uvm_test;
    // 声明成员变量：配置对象、子组件comp1和comp2
    config_obj cfg;
    comp1 c1;
    comp2 c2;

    // 将测试用例注册到UVM工厂
    `uvm_component_utils(uvm_message_test)

    // 构造函数：测试用例的父组件默认为null（顶层组件）
    function new(string name = "uvm_message_test", uvm_component parent = null);
      super.new(name, parent);
      // 注意：这里没有添加`uvm_info，因为构造函数执行时消息控制还未设置
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      `uvm_info("BUILD", "uvm_message_test build phase entered", UVM_LOW)

      // 1. 通过UVM工厂创建配置对象（uvm_object，无父组件）
      cfg = config_obj::type_id::create("cfg");
      // 2. 通过UVM工厂创建子组件comp1和comp2，父组件为当前测试用例（this）
      c1 = comp1::type_id::create("c1", this);
      c2 = comp2::type_id::create("c2", this);

      //TODO-5.1: 使用set_report_verbosity_level_hier()禁用uvm_message_test下的所有UVM消息
      // 原理：set_report_verbosity_level_hier(level)会设置**当前组件及其所有子组件**的默认冗余度级别
      // UVM_NONE（0）是最低冗余度级别，表示所有消息都不会打印
      // 注意：子组件的"CREATE"消息已经打印（因为组件创建时就执行了`uvm_info`），因此该设置对已打印的消息无效
      // set_report_verbosity_level_hier(UVM_NONE);
      
      //TODO-5.2: 使用set_report_id_verbosity_level_hier()禁用"CREATE"、"BUILD"、"RUN" ID的消息
      // 原理：set_report_id_verbosity_hier(id, level)针对**特定消息ID**设置冗余度级别
      // 问题："CREATE"消息无法禁用（组件创建时已打印）；测试用例的"BUILD"进入消息已打印，子组件的"BUILD"消息还未打印
      // set_report_id_verbosity_hier("BUILD", UVM_NONE);
      // set_report_id_verbosity_hier("CREATE", UVM_NONE);
      // set_report_id_verbosity_hier("RUN", UVM_NONE);
      
      //TODO-5.3: 为什么config_obj和uvm_message_ref模块的消息无法被禁用？
      // 原因：
      // 1. config_obj是uvm_object，不属于UVM组件层级，因此组件的hier方法无法控制它的消息
      // 2. 模块中的`uvm_info属于uvm_root（UVM根组件）的消息，不在测试用例的层级下
      // 解决方案：使用uvm_root（全局根组件）或uvm_report_server（全局消息服务器）设置消息过滤
      // uvm_root::get().set_report_id_verbosity_hier("CREATE", UVM_NONE);
      // uvm_root::get().set_report_id_verbosity_hier("BUILD", UVM_NONE);
      // uvm_root::get().set_report_id_verbosity_hier("RUN", UVM_NONE);

      `uvm_info("BUILD", "uvm_message_test build phase exited", UVM_LOW)
    endfunction
    
    // end_of_elaboration_phase：UVM的phase，在所有组件创建和配置完成后执行（build_phase之后）
    // 这是设置消息控制的**最佳时机**：所有组件已创建，且后续phase（如connect_phase、run_phase）尚未执行
    // 注意：即使在这里设置，"CREATE"消息已打印（组件创建时执行），但子组件的"BUILD"、"RUN"消息可以被禁用
    function void end_of_elaboration_phase(uvm_phase phase);
      //TODO-5.2: 在这里调用set_report_id_verbosity_hier()，效果更好
      // 原因：此时所有子组件都已创建，hier方法可以覆盖所有子组件的后续消息
      // set_report_id_verbosity_hier("BUILD", UVM_NONE);
      // set_report_id_verbosity_hier("CREATE", UVM_NONE); // 无效，CREATE消息已打印
      // set_report_id_verbosity_hier("RUN", UVM_NONE); // 有效，RUN消息还未执行
    endfunction

    task run_phase(uvm_phase phase);
      super.run_phase(phase);
      `uvm_info("RUN", "uvm_message_test run phase entered", UVM_LOW)
      // 提出异议：UVM的run_phase默认会在没有异议时立即结束，因此需要raise_objection保持phase运行
      phase.raise_objection(this);
      // 撤销异议：表示测试逻辑完成，run_phase可以结束
      phase.drop_objection(this);
      `uvm_info("RUN", "uvm_message_test run phase exited", UVM_LOW)
    endtask
  endclass
endpackage

// 顶层模块：UVM测试的入口，负责启动UVM环境
module uvm_message_ref;

  // 导入UVM核心包和自定义包
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import uvm_message_pkg::*;
  
  initial begin
    //TODO-5.3: 禁用config_obj和模块中的消息的最终解决方案
    // 方案1：使用uvm_report_server（全局消息服务器）过滤特定ID的消息（推荐）
    // uvm_report_server::get_server().set_id_action("CREATE", UVM_NO_ACTION);
    // uvm_report_server::get_server().set_id_action("BUILD", UVM_NO_ACTION);
    // uvm_report_server::get_server().set_id_action("RUN", UVM_NO_ACTION);
    // uvm_report_server::get_server().set_id_action("TOPTB", UVM_NO_ACTION);
    // 方案2：使用uvm_root（全局根组件）设置层级消息控制
    // uvm_root::get().set_report_id_verbosity_hier("TOPTB", UVM_NONE);

    // 打印模块级别的消息，ID为"TOPTB"（属于uvm_root的消息）
    `uvm_info("TOPTB", "RUN TEST entered", UVM_LOW)
    // 启动UVM测试：run_test("")会从UVM命令行参数获取测试用例名称，或使用默认的测试用例
    // 此处代码中仅有uvm_message_test，因此会运行该测试用例
    run_test(""); // empty test name
    `uvm_info("TOPTB", "RUN TEST exited", UVM_LOW)
  end

endmodule