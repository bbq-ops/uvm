/**
 * 模块说明：
 * 本代码演示UVM中uvm_object核心方法（compare/copy/print）的使用，
 * 定义了一个自定义事务类trans，重写do_compare方法实现自定义比较逻辑，
 * 并通过测试类验证事务对象的比较、复制功能。
 */

// 定义自定义UVM包，封装事务类、测试类等核心组件
package object_methods_pkg;
  // 导入UVM核心包和宏定义（UVM必备）
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  
  /**
   * 枚举类型：定义总线操作类型
   * WRITE: 写操作
   * READ: 读操作
   * IDLE: 空闲状态
   */
  typedef enum {WRITE, READ, IDLE} op_t;  

  /**
   * 事务类trans：继承自uvm_object，是UVM中最基础的事务对象
   * 作用：封装总线事务的核心属性（地址、数据、操作类型、名称），
   *       并重写do_compare方法实现自定义比较逻辑
   */
  class trans extends uvm_object;
    // 事务属性：32位地址
    bit[31:0] addr;
    // 事务属性：32位数据
    bit[31:0] data;
    // 事务属性：操作类型（枚举）
    op_t op;
    // 事务对象名称（用于UVM组件/对象的标识）
    string name;

    /**
     * UVM工厂注册宏：将trans类注册到UVM工厂，支持工厂创建（type_id::create）
     * `uvm_object_utils_begin/end包裹字段注册宏，实现字段的自动化（打印/比较/复制等）
     * UVM_ALL_ON：启用该字段的所有自动化功能（打印、比较、复制、记录等）
     */
    `uvm_object_utils_begin(trans)
      `uvm_field_int(addr, UVM_ALL_ON)    // 注册32位整型字段addr
      `uvm_field_int(data, UVM_ALL_ON)    // 注册32位整型字段data
      `uvm_field_enum(op_t, op, UVM_ALL_ON) // 注册枚举类型字段op
      `uvm_field_string(name, UVM_ALL_ON) // 注册字符串类型字段name
    `uvm_object_utils_end

    /**
     * 构造函数：初始化事务对象
     * @param name：对象名称（默认值"trans"）
     * 功能：调用父类uvm_object的构造函数，打印创建信息
     */
    function new(string name = "trans");
      super.new(name); // 调用父类构造函数，设置对象名称
      // 打印对象创建信息（UVM_LOW级别：最低日志级别，始终打印）
      `uvm_info("CREATE", $sformatf("trans type [%s] created", name), UVM_LOW)
    endfunction

    /**
     * 重写uvm_object的do_compare方法：自定义事务对象的比较逻辑
     * UVM的compare()方法底层会调用do_compare，实现对象成员的逐字段比较
     * @param rhs：待比较的右侧对象（uvm_object类型，需向下转换为trans）
     * @param comparer：UVM比较器（控制比较规则，如容差、显示最大差异数等）
     * @return bit：比较结果（1=相等，0=不相等）
     */
    function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      trans t; // 声明trans类型变量，存储转换后的rhs
      do_compare = 1; // 初始化比较结果为"相等"
      
      // 将uvm_object类型的rhs向下转换为trans类型（$cast返回值无意义，用void'忽略）
      void'($cast(t, rhs));

      // 比较addr字段：不相等则置位错误标志，打印警告
      if(addr != t.addr) begin
        do_compare = 0;
        `uvm_warning("CMPERR", $sformatf("addr %8x != %8x", addr, t.addr))
      end
      // 比较data字段：不相等则置位错误标志，打印警告
      if(data != t.data) begin
        do_compare = 0;
        `uvm_warning("CMPERR", $sformatf("data %8x != %8x", data, t.data))
      end
      // 比较op字段：不相等则置位错误标志，打印警告（注：%8x是格式错误，应为%s，此处保留原代码）
      if(op != t.op) begin
        do_compare = 0;
        `uvm_warning("CMPERR", $sformatf("op %s != %8x", op, t.op))
      end
      // 比较name字段：此处重复判断addr（原代码笔误），且%8x格式错误（字符串应用%s），保留原代码
      if(addr != t.addr) begin
        do_compare = 0;
        `uvm_warning("CMPERR", $sformatf("name %8x != %8x", name, t.name))
      end
    endfunction
  endclass


  /**
   * 测试类object_methods_test：继承自uvm_test，是UVM测试的顶层组件
   * 作用：创建trans事务对象，验证compare/copy/print等UVM核心方法的功能
   */
  class object_methods_test extends uvm_test;
    // UVM工厂注册宏：将测试类注册到UVM工厂，支持run_test调用
    `uvm_component_utils(object_methods_test)

    /**
     * 构造函数：初始化测试类对象
     * @param name：测试类名称（默认"object_methods_test"）
     * @param parent：父组件（UVM组件树的父节点，测试类通常为顶层，parent=null）
     */
    function new(string name = "object_methods_test", uvm_component parent = null);
      super.new(name, parent); // 调用父类uvm_component的构造函数
    endfunction

    /**
     * build_phase：UVM构建阶段（创建/配置组件）
     * 功能：调用父类build_phase，本示例无额外组件需要构建
     * @param phase：当前UVM阶段（build_phase）
     */
    function void build_phase(uvm_phase phase);
      super.build_phase(phase); // 必须调用父类build_phase，保证UVM树构建完整
    endfunction

    /**
     * run_phase：UVM运行阶段（核心测试逻辑）
     * 功能：
     * 1. 创建两个trans对象t1/t2，初始化不同值
     * 2. 调用compare方法比较t1/t2，验证不相等
     * 3. 调整比较器参数，再次比较
     * 4. 调用copy方法将t2复制到t1
     * 5. 再次比较t1/t2，验证相等
     * @param phase：当前UVM阶段（run_phase）
     */
    task run_phase(uvm_phase phase);
      trans t1, t2;       // 声明两个trans事务对象
      bit is_equal;       // 存储比较结果（1=相等，0=不相等）
      
      // 提升异议：告诉UVM测试还未完成，防止提前结束（UVM必备）
      phase.raise_objection(this);

      // 1. 创建并初始化t1对象（通过UVM工厂创建，推荐方式）
      t1 = trans::type_id::create("t1");
      t1.data = 'h1FF;    // 设置t1数据为0x1FF
      t1.addr = 'hF100;   // 设置t1地址为0xF100
      t1.op = WRITE;      // 设置t1操作为WRITE
      t1.name = "t1";     // 设置t1名称为"t1"

      // 2. 创建并初始化t2对象（与t1值不同）
      t2 = trans::type_id::create("t2");
      t2.data = 'h2FF;    // 设置t2数据为0x2FF
      t2.addr = 'hF200;   // 设置t2地址为0xF200
      t2.op = WRITE;      // 设置t2操作为WRITE（与t1相同）
      t2.name = "t2";     // 设置t2名称为"t2"

      // 3. 第一次比较t1和t2（预期不相等）
      is_equal = t1.compare(t2);
      
      // 设置UVM默认比较器的最大显示差异数为10（默认值较小，扩展显示能力）
      uvm_default_comparer.show_max = 10;
      // 第二次比较t1和t2（验证比较器参数调整不影响结果，仍不相等）
      is_equal = t1.compare(t2);
      
      // 根据比较结果打印日志：不相等则警告，相等则信息
      if(!is_equal)
        `uvm_warning("CMPERR", "t1 is not equal to t2")
      else
        `uvm_info("CMPERR", "t1 is equal to t2", UVM_LOW)
      
      // 4. 打印复制前的t1/t2（验证初始值）
      `uvm_info("COPY", "Before uvm_object copy() taken", UVM_LOW)
      t1.print(); // 调用UVM自动化打印方法，打印t1所有字段
      t2.print(); // 调用UVM自动化打印方法，打印t2所有字段

      // 5. 复制操作：将t2的所有字段复制到t1（覆盖t1原有值）
      `uvm_info("COPY", "After uvm_object t2 is copied to t1", UVM_LOW)
      t1.copy(t2);

      // 打印复制后的t1/t2（验证t1已被覆盖为t2的值）
      t1.print();
      t2.print();

      // 6. 第三次比较t1和t2（预期相等）
      `uvm_info("CMP", "Compare t1 and t2", UVM_LOW)
      is_equal = t1.compare(t2);
      // 根据比较结果打印日志
      if(!is_equal)
        `uvm_warning("CMPERR", "t1 is not equal to t2")
      else
        `uvm_info("CMPERR", "t1 is equal to t2", UVM_LOW)       
      
      // 延时1微秒：模拟实际测试中的时序（非必需，仅演示）
      #1us;
      
      // 撤销异议：告诉UVM测试完成，允许结束
      phase.drop_objection(this);
    endtask
  endclass
  
endpackage

/**
 * 顶层模块object_methods：UVM测试的入口模块
 * 作用：导入UVM和自定义包，启动UVM测试流程
 */
module object_methods;
  // 导入UVM核心包和宏（UVM必备）
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  // 导入自定义包（包含trans和测试类）
  import object_methods_pkg::*;

  initial begin
    /**
     * run_test：UVM启动测试的核心函数
     * 参数为空字符串时，UVM会根据工厂中注册的测试类自动选择（本示例中为object_methods_test）
     * 也可指定测试类名：run_test("object_methods_test")
     */
    run_test(""); // empty test name
  end

endmodule