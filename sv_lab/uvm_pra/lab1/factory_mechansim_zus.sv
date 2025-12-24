// 定义包 factory_pkg，封装所有工厂模式相关的类（避免命名冲突）
package factory_pkg;
  // 导入UVM核心包（包含UVM基础类和宏）
  import uvm_pkg::*;
  // 包含UVM宏定义（如`uvm_object_utils、`uvm_component_utils等）
  `include "uvm_macros.svh"

  // -----------------------------------------------------------------------------
  // 1. UVM Object 基类：trans（继承自uvm_object，无父子层级关系）
  // 作用：定义基础数据传输对象，作为uvm_object的示例
  // -----------------------------------------------------------------------------
  class trans extends uvm_object;
    bit[31:0] data;  // 数据字段：32位数据

    // UVM对象注册宏：将trans类注册到UVM工厂，支持工厂创建和类型覆盖
    // 必须在uvm_object子类中使用，生成type_id等工厂相关接口
    `uvm_object_utils(trans)

    // 构造函数：UVM对象构造函数需遵循 "string name = "默认名"" 的格式
    // name：对象实例名，用于UVM树形结构和日志打印
    function new(string name = "trans");
      super.new(name);  // 调用父类uvm_object的构造函数，初始化名称等基础属性
      // UVM日志打印：UVM_LOW优先级（默认打印），提示对象创建成功
      `uvm_info("CREATE", $sformatf("trans type [%s] created", name), UVM_LOW)
    endfunction
  endclass

  // -----------------------------------------------------------------------------
  // 2. UVM Object 子类：bad_trans（继承自trans，用于类型覆盖测试）
  // 作用：作为trans的"坏数据"子类，演示工厂模式的类型替换功能
  // -----------------------------------------------------------------------------
  class bad_trans extends trans;
    bit is_bad = 1;  // 扩展字段：标记是否为坏数据（区别于父类trans）

    // 注册到UVM工厂，支持工厂创建和覆盖trans类型
    `uvm_object_utils(bad_trans)

    // 构造函数：默认名称继承父类的"trans"（可通过创建时指定自定义名称）
    function new(string name = "trans");
      super.new(name);  // 调用父类trans的构造函数，初始化父类属性
      `uvm_info("CREATE", $sformatf("bad_trans type [%s] created", name), UVM_LOW)
    endfunction
  endclass

  // -----------------------------------------------------------------------------
  // 3. UVM Component 基类：unit（继承自uvm_component，有父子层级关系）
  // 作用：定义基础组件，作为uvm_component的示例（组件需嵌入UVM树形结构）
  // -----------------------------------------------------------------------------
  class unit extends uvm_component;
    // UVM组件注册宏：将unit类注册到UVM工厂，支持工厂创建和类型覆盖
    // 必须在uvm_component子类中使用，生成type_id等工厂接口（含parent参数支持）
    `uvm_component_utils(unit)

    // 组件构造函数：需额外传入父组件指针parent（构建UVM树形结构）
    // name：组件实例名；parent：父组件（null表示顶层组件）
    function new(string name = "unit", uvm_component parent = null);
      super.new(name, parent);  // 调用父类uvm_component的构造函数，初始化名称和父子关系
      `uvm_info("CREATE", $sformatf("unit type [%s] created", name), UVM_LOW)      
    endfunction
  endclass

  // -----------------------------------------------------------------------------
  // 4. UVM Component 子类：big_unit（继承自unit，用于组件类型覆盖测试）
  // 作用：作为unit的"大型组件"子类，演示组件的工厂类型替换
  // -----------------------------------------------------------------------------
  class big_unit extends unit;
    bit is_big = 1;  // 扩展字段：标记是否为大型组件（区别于父类unit）

    // 注册到UVM工厂，支持覆盖unit类型
    `uvm_component_utils(big_unit)

    // 构造函数：默认名称为"bit_unit"（可能是笔误，应为"big_unit"，不影响功能）
    function new(string name = "bit_unit", uvm_component parent = null);
      super.new(name, parent);  // 调用父类unit的构造函数，初始化父类属性和父子关系
      `uvm_info("CREATE", $sformatf("big_unit type [%s] created", name), UVM_LOW)
    endfunction
  endclass

  // -----------------------------------------------------------------------------
  // 5. 基础测试类：top（继承自uvm_test，所有测试类的基类）
  // 作用：定义测试的基础结构，提供phase机制的默认实现
  // uvm_test是UVM测试的入口类，每个测试需继承自它
  // -----------------------------------------------------------------------------
  class top extends uvm_test;
    // 注册测试类到UVM工厂（支持通过run_test指定测试名启动）
    `uvm_component_utils(top)

    // 构造函数：测试类作为顶层组件，parent默认null
    function new(string name = "top", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    // 构建阶段（UVM标准phase）：用于创建测试所需的对象/组件
    // 执行时机：测试启动后，run_phase前，按树形结构自上而下执行
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);  // 必须调用父类build_phase，确保UVM内部初始化
    endfunction

    // 运行阶段（UVM标准phase）：测试的核心逻辑执行阶段
    // 执行时机：build_phase完成后，按树形结构并行执行
    task run_phase(uvm_phase phase);
      phase.raise_objection(this);  // 提起异议：阻止UVM提前结束测试
      #1us;  // 测试延时（模拟实际测试逻辑执行时间）
      phase.drop_objection(this);   // 放下异议：通知UVM测试可结束
    endtask
  endclass

  // -----------------------------------------------------------------------------
  // 6. Object创建测试类：object_create（继承自top）
  // 作用：演示uvm_object的4种创建方式（直接new + 3种工厂创建）
  // -----------------------------------------------------------------------------
  class object_create extends top;
    trans t1, t2, t3, t4;  // 声明4个trans类型的句柄（用于演示不同创建方式）

    // 注册测试类到工厂，支持通过run_test("object_create")启动
    `uvm_component_utils(object_create)

    function new(string name = "object_create", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    // 构建阶段：集中创建uvm_object实例
    function void build_phase(uvm_phase phase);
      uvm_factory f = uvm_factory::get();  // 获取UVM工厂单例（全局唯一的工厂实例）
      super.build_phase(phase);           // 调用父类build_phase

      // 方式1：直接构造（不经过UVM工厂，无法被类型覆盖）
      t1 = new("t1");  // 直接调用new，创建trans实例，名称为"t1"

      // TODO-1.1：按要求用3种工厂方式创建uvm_object
      // 方式2：通过类的type_id::create()创建（推荐工厂创建方式，简洁且支持覆盖）
      // type_id由`uvm_object_utils宏生成，create()是工厂创建的便捷接口
      t2 = trans::type_id::create("t2");  // 创建trans实例，名称为"t2"

      // 方式3：通过工厂的create_object_by_type()创建（按类型创建，支持覆盖）
      // requested_type：指定要创建的类型（trans::get_type()获取类型句柄）
      // parent_inst_path：对象的父路径（uvm_object无父子关系，留空）
      // name：对象实例名
      t3 = trans::type_id::convert_handle(f.create_object_by_type(trans::get_type(), "", "t3"));

      // 方式4：通过工厂的create_object()创建（按类型名字符串创建，支持覆盖）
      // requested_type_name：类型名（字符串形式，需与类名一致）
      // name：对象实例名
      t4 = trans::type_id::convert_handle(f.create_object("trans", "t4"));
    endfunction
  endclass

  // -----------------------------------------------------------------------------
  // 7. Object类型覆盖测试类：object_override（继承自object_create）
  // 作用：演示uvm_object的类型覆盖（用bad_trans替换trans）
  // 核心：工厂模式的核心功能，无需修改代码即可替换对象类型
  // -----------------------------------------------------------------------------
  class object_override extends object_create;
    // 注册测试类到工厂，支持通过run_test("object_override")启动
    `uvm_component_utils(object_override)

    function new(string name = "object_override", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    // 构建阶段：先配置类型覆盖，再执行父类的对象创建（覆盖才会生效）
    function void build_phase(uvm_phase phase);
      uvm_factory f = uvm_factory::get();  // 获取工厂单例

      // 配置类型覆盖：用bad_trans覆盖trans类型
      // set_type_override_by_type：按类型句柄覆盖（类型安全，推荐）
      // original_type：被覆盖的原始类型（trans::get_type()）
      // override_type：用于替换的目标类型（bad_trans::get_type()）
      // replace=1：强制替换（若已有其他覆盖，替换为当前配置）
      f.set_type_override_by_type(trans::get_type(), bad_trans::get_type(), 1);

      // 必须在覆盖配置后调用父类build_phase，确保创建对象时覆盖生效
      super.build_phase(phase);
    endfunction
  endclass

  // -----------------------------------------------------------------------------
  // 8. Component创建测试类：component_create（继承自top）
  // 作用：演示uvm_component的4种创建方式（直接new + 3种工厂创建）
  // 注意：component有父子层级，创建时需指定parent（嵌入UVM树形结构）
  // -----------------------------------------------------------------------------
  class component_create extends top;
    unit u1, u2, u3, u4;  // 声明4个unit类型的句柄（组件句柄）

    // 注册测试类到工厂
    `uvm_component_utils(component_create)

    function new(string name = "component_create", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    // 构建阶段：创建uvm_component实例（需指定父组件）
    function void build_phase(uvm_phase phase);
      uvm_factory f = uvm_factory::get();  // 获取工厂单例
      super.build_phase(phase);           // 调用父类build_phase

      // 方式1：直接构造（不经过工厂，无法覆盖，需指定parent）
      u1 = new("u1", this);  // this表示当前测试类（component_create）是u1的父组件

      // TODO-1.2：按要求用3种工厂方式创建uvm_component
      // 方式2：通过类的type_id::create()创建（推荐，支持覆盖，自动关联父组件）
      // 第一个参数：组件名；第二个参数：父组件（this）
      u2 = unit::type_id::create("u2", this);

      // 方式3：通过工厂的create_component_by_type()创建（按类型创建）
      // requested_type：要创建的类型（unit::get_type()）
      // parent_inst_path：父组件的路径（留空，UVM自动通过parent参数识别）
      // name：组件名；parent：父组件（this）
      u3 = unit::type_id::convert_handle(f.create_component_by_type(unit::get_type(), "", "u3", this));

      // 方式4：通过工厂的create_component()创建（按类型名字符串创建）
      // requested_type_name：组件类型名（字符串）；name：组件名
      // 注意：该方法默认父组件为当前组件（this），无需额外指定
      u4 = unit::type_id::convert_handle(f.create_component("unit", "u4"));
    endfunction
  endclass

  // -----------------------------------------------------------------------------
  // 9. Component类型覆盖测试类：component_override（继承自component_create）
  // 作用：演示uvm_component的类型覆盖（用big_unit替换unit）
  // 核心：组件的覆盖与object原理一致，但需注意父子层级的兼容性
  // -----------------------------------------------------------------------------
  class component_override extends component_create;
    // 注册测试类到工厂
    `uvm_component_utils(component_override)

    function new(string name = "component_override", uvm_component parent = null);
      super.new(name, parent);
    endfunction

    // 构建阶段：先配置类型覆盖，再执行父类的组件创建
    function void build_phase(uvm_phase phase);
      uvm_factory f = uvm_factory::get();  // 获取工厂单例

      // 配置类型覆盖：用big_unit覆盖unit类型（按类型名字符串覆盖）
      // set_type_override：按字符串名称覆盖（灵活，无需导入类型，但无类型检查）
      // original_type_name：原始类型名（"unit"）
      // override_type_name：目标类型名（"big_unit"）
      // replace=1：强制替换
      f.set_type_override("unit", "big_unit", 1);

      // 调用父类build_phase，创建组件时覆盖生效
      super.build_phase(phase);
    endfunction
  endclass
  
endpackage

// -----------------------------------------------------------------------------
// 顶层模块：factory_mechanism（UVM测试的入口模块）
// 作用：初始化UVM环境，启动测试
// -----------------------------------------------------------------------------
module factory_mechanism;

  import uvm_pkg::*;         // 导入UVM核心包
  `include "uvm_macros.svh"  // 包含UVM宏
  import factory_pkg::*;     // 导入自定义的工厂模式包

  initial begin
    // 启动UVM测试：参数为空字符串时，UVM会从命令行（+UVM_TESTNAME）获取测试类名
    // 示例：仿真时指定 +UVM_TESTNAME=object_create 即可运行对应的测试
    run_test(""); 
  end

endmodule