`timescale 1ns/1ps

// 导入报告包
import rpt_pkg::*;

module rpt_example_test;
  
  // 测试信号
  logic clk;
  logic rstn;
  logic [31:0] data_in;
  logic [31:0] data_out;
  logic valid;
  
  // 时钟生成
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end
  
  // 测试主程序
  initial begin
    // 1. 清理之前的日志文件
    clean_log();
    
    // 2. 设置报告严重程度阈值为MEDIUM（只显示MEDIUM以上级别的消息）
    rpt_pkg::svrt = MEDIUM;
    
    rpt_msg("TESTBENCH", "=== 开始测试 ===", INFO, TOP);
    
    // 3. 复位序列
    rstn = 0;
    data_in = 0;
    valid = 0;
    
    rpt_msg("RESET", "开始复位序列", INFO, HIGH);
    repeat(5) @(posedge clk);
    rstn = 1;
    rpt_msg("RESET", "复位完成", INFO, HIGH);
    
    // 4. 测试数据传输
    repeat(10) begin
      @(posedge clk);
      data_in = $random;
      valid = 1;
      
      // 检查数据有效性（示例检查）
      if(data_in == 0) begin
        rpt_msg("DATA_CHECK", $sformatf("数据为0: 0x%08x", data_in), WARNING, MEDIUM);
      end
      else if(data_in > 32'hFFFF_FF00) begin
        rpt_msg("DATA_CHECK", $sformatf("数据值过大: 0x%08x", data_in), ERROR, HIGH, STOP);
      end
      else begin
        rpt_msg("DATA_CHECK", $sformatf("数据正常: 0x%08x", data_in), INFO, LOW);
      end
      
      @(posedge clk);
      valid = 0;
    end
    
    // 5. 模拟一些错误情况
    rpt_msg("PROTOCOL", "检测到协议违规", ERROR, HIGH);
    rpt_msg("TIMEOUT", "操作超时", WARNING, MEDIUM);
    rpt_msg("DEBUG", "调试信息", INFO, LOW);  // 这个不会显示，因为严重程度低于阈值
    
    // 6. 致命错误示例（但不退出，只是计数）
    rpt_msg("SYSTEM", "内存分配失败", FATAL, TOP);
    
    // 7. 生成测试报告
    repeat(5) @(posedge clk);
    rpt_msg("TESTBENCH", "=== 测试完成 ===", INFO, TOP);
    do_report();
    
    $finish;
  end
  
  // 监控器示例 - 展示在always块中使用报告功能
  always @(posedge clk) begin
    if(rstn && valid) begin
      // 模拟数据输出延迟检查
      if($time > 1000 && !data_out) begin
        rpt_msg("MONITOR", $sformatf("@%0t 输出延迟异常", $time), WARNING, MEDIUM);
      end
    end
  end
  
  // 简单的数据处理逻辑（演示用）
  always_ff @(posedge clk or negedge rstn) begin
    if(!rstn) begin
      data_out <= 0;
    end
    else if(valid) begin
      data_out <= data_in + 1; // 简单的+1操作
    end
  end

endmodule