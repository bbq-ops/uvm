`timescales 1ns/1ps

interface chnl_intf(input clk, input rstn);
	logic [31:0] ch_data;
	logic  	     ch_valid;
	logic  		 ch_ready;
	logic [5:0]  ch_margin;
	
	clocking drv_clk @(posedge clk);
		default input #1ns output #1ns;
		output ch_data, ch_valid;
		input  ch_ready, ch_margin;
	endclocking
endinterface

//通道事务类，封装一次是数据传输的相关信息，作为数据传输的基本单元
class chnl_trans;
	int data;
	int num;
	int id;
endclass

//通道发起器，负责通过接口驱动数据的传输，是测试平台的驱动组件
class chnl_initiator;
	local string name;
	local int idle_cycles;
	virtual chnl_intf intf;  //绑定实际接口，用于信号驱动，类中无法直接驱动interfac中的信号（需要使用virtual）
	
	//构造函数：初始化发起器的名称，默认空闲周期为1
	function new(string name = "chnl_initiator");
		this.name = name;
		this.idle_cycles = 1;
	endfunction
	
	//设置发起器的空闲周期
	function void set_idle_cycles(int n);
		this.idle_cycles = n;
	endfunction
	
	//设置发起器名称
	function void set_name(string s);
		this.name = s;
	endfunction
	
	//绑定接口：将虚拟接口与实际接口连接，若接口为空则报错
	function void set_interface(virtual chnl_intf intf);
	if(intf == null)
		$error("interface handle is NULL,check if target interface has been intantiated");
	else
		this.intf = intf;
	endfunction
	
	//数据发送任务：通过接口发送一个事务数据
	task chnl_wirte(input chnl_trans t);
		@(posedge intf.clk);
		intf.drv_clk.ch_valid <= 1'b1;
		intf.drv_clk.ch_data <= t.data;
		@(negedge intf.clk);
		wait(intf.ch_ready === 1'b1);
		$display("%t channel initiator [%s] sent data %x",$time,name,t.data);
		
		repeat(this.idle_cycles) chnl_idle();
	endtask
	
	task chnl_idle();
		@(posedge intf.clk);
		intf.drv_clk.ch_valid <= 1'b0;
		intf.drv_clk.ch_data <= 'b0;
	endtask
	
endclass

class chnl_generator;
	chnl_trans trans[$];  //事务队列：存储已生成的事务
	int num;
	int id;
	chnl_trans t;
	
	function new(int n);
		this.id = n;
		this.num = 0;
	endfunction
	
	//生成一个对象，并返回其句柄
	function chnl_trans get_trans();
		t = new();
		t.data = 'h00C0_0000 + (this.id << 16) + this.num;
		t.id = this.id;
		t.num = this.num;
		this.num++;
		this.trans.push_back(t);  //将每个句柄存入事务队列
		return t;
	endfunction
endclass

module tb3_ref;
	logic clk;
	logic rstn;
	logic [31:0] mcdt_data;
	logic mcdt_val;
	logic mcdt_id;
	
  mcdt dut(
     .clk_i       (clk                )  // 时钟输入
    ,.rstn_i      (rstn               )  // 复位输入
    ,.ch0_data_i  (chnl0_if.ch_data   )  // 通道0数据输入
    ,.ch0_valid_i (chnl0_if.ch_valid  )  // 通道0有效输入
    ,.ch0_ready_o (chnl0_if.ch_ready  )  // 通道0就绪输出
    ,.ch0_margin_o(chnl0_if.ch_margin )  // 通道0FIFO余量输出
    ,.ch1_data_i  (chnl1_if.ch_data   )  // 通道1数据输入
    ,.ch1_valid_i (chnl1_if.ch_valid  )  // 通道1有效输入
    ,.ch1_ready_o (chnl1_if.ch_ready  )  // 通道1就绪输出
    ,.ch1_margin_o(chnl1_if.ch_margin )  // 通道1FIFO余量输出
    ,.ch2_data_i  (chnl2_if.ch_data   )  // 通道2数据输入
    ,.ch2_valid_i (chnl2_if.ch_valid  )  // 通道2有效输入
    ,.ch2_ready_o (chnl2_if.ch_ready  )  // 通道2就绪输出
    ,.ch2_margin_o(chnl2_if.ch_margin )  // 通道2FIFO余量输出
    ,.mcdt_data_o (mcdt_data          )  // 合并数据输出
    ,.mcdt_val_o  (mcdt_val           )  // 合并数据有效输出
    ,.mcdt_id_o   (mcdt_id            )  // 合并数据通道ID输出
  );
  
  initial begin
	clk <= 0;
	forever begin
	 #5	clk = !clk;
	end
  end
  
  initial begin
	#10 rstn <= 0;
	repeat(10) @(posedge clk);
	rstn <= 1;
  end
  
  chnl_intf chnl0_if(.*);
  chnl_intf chnl1_if(.*);
  chnl_intf chnl2_if(.*);
  
  chnl_initiator chnl0_init;
  chnl_initiator chnl1_init;
  chnl_initiator chnl2_init;
  
  chnl_generator chnl0_gen;
  chnl_generator chnl1_gen;
  chnl_generator chnl2_gen;
  
  initial begin
	//初始化发起器和生成器
	chnl0_init = new("chnl0_init");
	chnl1_init = new("chnl1_init");
	chnl2_init = new("chnl2_init");
	
	chnl0_gen = new(0);
	chnl1_gen = new(1);
	chnl2_gen = new(2);
	
	//为每个发起器绑定一个接口
	chnl0_init.set_interface(chnl0_if);
	chnl1_init.set_interface(chnl1_if);
	chnl2_init.set_interface(chnl2_if);
	
    $display("***all of tests have been finished***");
    basic_test();
    burst_test();
    fifo_full_test();
    $finish();
  end
  
  task automatic basic_test();
    chnl0_init.set_idle_cycles($urandom_range(1,3));
    chnl1_init.set_idle_cycles($urandom_range(1,3));
    chnl2_init.set_idle_cycles($urandom_range(1,3));
    $display("basic_test initialized componnents");
    wait(rstn === 1'b1);
    repeat(5) @(posedge clk);
    $display("basic_test started testing DUT");
    
    fork
        repeat(100) chnl0_init.chnl_wirte(chnl0_gen.get_trans());
        repeat(100) chnl1_init.chnl_wirte(chnl1_gen.get_trans());
        repeat(100) chnl2_init.chnl_wirte(chnl2_gen.get_trans());
    join
    
    fork
        wait(chnl0_init.intf.ch_margin == 'h20);
        wait(chnl1_init.intf.ch_margin == 'h20);
        wait(chnl2_init.intf.ch_margin == 'h20);
    join
    $display("basic_test finished testing DUT");
  endtask
 
  task automatic burst_test();
    chnl0_init.set_idle_cycles(0);
    chnl1_init.set_idle_cycles(0);
    chnl2_init.set_idle_cycles(0);   
    
    wait(rstn === 1'b1);
    repeat(5) @(posedge clk);
    
    fork
        begin
            repeat(500) chnl0_init.chnl_wirte(chnl0_gen.get_trans());
            chnl0_init.chnl_idle();
        end
        begin
            repeat(500) chnl1_init.chnl_wirte(chnl1_gen.get_trans());
            chnl0_init.chnl_idle();
        end
        begin
            repeat(500) chnl2_init.chnl_wirte(chnl2_gen.get_trans());
            chnl0_init.chnl_idle();
        end
    join
    
    fork
        wait(chnl0_init.intf.ch_margin == 'h20);
        wait(chnl1_init.intf.ch_margin == 'h20);
        wait(chnl2_init.intf.ch_margin == 'h20);        
    join
  endtask
  
  task automatic fifo_full_test();
    chnl0_init.set_idle_cycles(0);
    chnl1_init.set_idle_cycles(0);
    chnl2_init.set_idle_cycles(0);
    
    fork: fork_all_run
        forever chnl0_init.chnl_wirte(chnl0_gen.get_trans());
        forever chnl1_init.chnl_wirte(chnl1_gen.get_trans());
        forever chnl2_init.chnl_wirte(chnl2_gen.get_trans());
    join_none
    
    fork
        wait(chnl0_init.intf.ch_margin == 0);
        wait(chnl1_init.intf.ch_margin == 0);
        wait(chnl2_init.intf.ch_margin == 0);
    join
    
    disable fork_all_run;
    
    fork
        chnl0_init.chnl_idle();
        chnl1_init.chnl_idle();
        chnl2_init.chnl_idle();
    join
    
    fork
        wait(chnl0_init.intf.ch_margin == 'h20);
        wait(chnl1_init.intf.ch_margin == 'h20);
        wait(chnl2_init.intf.ch_margin == 'h20);        
    join   
    
    endtask
endmodule
  
  
  
	
	
	
	
	
	
	
	
