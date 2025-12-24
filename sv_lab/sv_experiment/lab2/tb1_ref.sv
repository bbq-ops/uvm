//时间单位定义
`timescale 1ns/1ps

//通道接口定义：用于连接数据发起端initiator和DUT，封装了数据传输相关信号及时钟块
interface chnl_intf(input clk, input rstn);
	logic [31:0] ch_data;
	logic  	     ch_valid;
	logic 		 ch_ready;
	logic [5:0]  ch_margin;
	
	//驱动时钟块：定义在clk上升沿同步驱动信号，用于确保信号同步性
	clocking drv_ck @(posedge clk);
		default input #1ns output #1ns;  //输入信号上升沿前1ns采样，输出信号上升沿后1ns驱动（避免竞争冒险）
		output ch_data, ch_valid;
		input ch_ready, ch_margin;
	endclocking
endinterface

//通道发起器模块：负责通过接口向DUT发送数据
module chnl_initiator(chnl_intf intf);  //使用接口作为输入
	string name;		//发起器名称（用于打印信息区分不同通道）
	int idle_cycles = 1;//数据间的空闲周期数（默认1个周期）
	
	//配置空闲周期的函数：设置两个连续数据之间的空闲周期数
	function automatic void set_idle_cycles(int n);
		idle_cycles = n;
	endfunction
	//配置名称的函数：设置发起器的名称
	function automatic void set_name(string s)
        name = s;
    endfunction
    //数据发送任务：通过接口向DUT发送一个32位数据
    task automatic chnl_write(input logic [31:0] data);
    @(posedge intf.clk);
    //通过运用drv_ck产生的时钟信号驱动数据，可以避免竞争冒险
    intf.drv_ck.ch_valid <= 1'b1;
    intf.drv_ck.ch_data  <= data;
    
    //增加等待下降沿，防止驱动器数据还未稳定就采样
    @(negedge intf.clk);  //相当于等待半个时钟周期
    
    //等待DUT就绪，表示DUT可以接收数据
    wait(intf.ch_ready === 1'b1);
    
    $display("%t channel initiator [%s] sent data %x",$time,name,data);
    
    //根据idle_cycles确定其需要空闲数量
    //循环调用chnl_idle()可实现多周期空闲
    repeat(idle_cycles) chnl_idle();
    endtask
    
    //空闲任务：在数据发送间隙插入空闲周期
    task automatic chnl_idle();
    @(posedge intf.clk);
    
    intf.drv_ck.ch_valid <= 1'b0;
    intf.drv_ck.ch_data <= 'b0; 
    
    endtask

module chnl_generator;
    int chnl_arr[$];   //定义了一个队列
    int num;           //数据计数器
    int id;            //区别不同的数据生成器
    
    //初始化函数：设置通道id并重置计数器
    function automatic void initialize(int n);
        id = n;        //赋值通道id
        num = 0;       //重置计数数据
    endfunction
    
    //生成数据的函数：按照固定格式生成数据并存储
    function automatic int get_data();
        int data;
        //数据格式：固定前缀'h00C0_0000 + 通道标识 + 数据个数
        data = 32'h00C0_0000 + (id << 16) + num;
        num++;
        chnl_arr.push_back(data);  //将生成的数据传入到队列中去
        return data;
    endfunction

//测试平台模块：实例化DUT,接口，发起器，生成器，构建完整的测试环境    
module tb1;
    logic clk;
    logic rstn;
    logic [31:0] mcdt_data;
    logic mcdt_val;
    logic mcdt_id;
    
    //实例化DUT（多通道数据合并器）：连接各通道的接口信号和输出信号
    mcdt dut(
        .clk_i(clk),
        .rstn_i(rstn),
        //通道0信号连接
        .ch0_data_i  (chnl0_if.ch_data),
        .ch0_valid_i (chnl0_if.ch_valid),
        .ch0_ready_o (chn10_if.ch_ready),
        .ch0_margin_o(chnl0_if.ch_margin),
        //通道1信号连接
        .ch1_data_i  (chnl1_if.ch_data),
        .ch1_valid_i (chnl1_if.ch_valid),
        .ch1_ready_o (chn11_if.ch_ready),
        .ch1_margin_o(chnl1_if.ch_margin),
        //通道2信号连接
        .ch0_data_i  (chnl2_if.ch_data),
        .ch0_valid_i (chnl2_if.ch_valid),
        .ch0_ready_o (chn12_if.ch_ready),
        .ch0_margin_o(chnl2_if.ch_margin),
        //DUT输出信号
        .mcdt_data_o (mcdt_data),
        .mcdt_val_o  (mcdt_val),
        .mcdt_id_o   (mcdt_id)
    );
    
    //实例化三个通道的接口
    chnl_intf chnl0_if(.*);
    chnl_intf chnl1_if(.*);
    chnl_intf chnl2_if(.*);
    
    //实例化三个数据生成器
    chnl_generator chnl0_gen();
    chnl_generator chnl1_gen();
    chnl_generator chnl2_gen();
    
    //实例化三个通道的数据发起器
    chnl_initiator chnl0_init(chnl0_if);
    chnl_initiator chnl1_init(chnl1_if);
    chnl_initiator chnl2_init(chnl2_if);
    
    //时钟生成：产生周期为10ns的时钟
    initial begin
        clk <= 0;
        forever begin
            #5 clk <= !clk;
        end
    end
    
    //复位触发：产生复位信号
    initial begin
        #10 rstn <= 0;  //#10是为了防止仿真初期不定态对电路的影响
        repeat(10) @(posedge clk);
        rstn <= 1;
    end
    
    //验证组件的初始化：配置生成器和发起器的参数
    initial begin
    //初始化三个通道的数据生成器（分别设置ID0，1，2）
    chnl0_gen.initialize(0);
    chnl1_gen.initialize(1);
    chnl2_gen.initialize(2);
    
    //设置三个发起器的名称
    chnl0_init.set_name("chnl0_init");
    chnl1_init.set_name("chnl1_init");
    chnl2_init.set_name("chnl2_init");
    
    //设置三个发起器的数据空闲周期
    chnl0_init.set_idle_cycles(0);
    chnl1_init.set_idle_cycles(0);
    chnl2_init.set_idle_cycles(0);
    end
    
    //通道0发生任务：复位释放后发送100个数据
    initial begin
    @(posedge rstn);
    repeat(5) @(posedge clk);
    repeat(100) begin
       //从生成器获取数据并通过发起器发送
       chnl0_init.chnl_write(chnl0_gen.get_data());
    end
    chnl0_init.chnl_idle();  //确保发送完成后进入空闲状态
    end
    
    //通道1发生任务：复位释放后发送100个数据
    initial begin
    @(posedge rstn);
    repeat(5) @(posedge clk);
    repeat(100) begin
       //从生成器获取数据并通过发起器发送
       chnl1_init.chnl_write(chnl1_gen.get_data());
    end
    chnl1_init.chnl_idle();  //确保发送完成后进入空闲状态
    end

    //通道2发生任务：复位释放后发送100个数据
    initial begin
    @(posedge rstn);
    repeat(5) @(posedge clk);
    repeat(100) begin
       //从生成器获取数据并通过发起器发送
       chnl2_init.chnl_write(chnl2_gen.get_data());
    end
    chnl2_init.chnl_idle();  //确保发送完成后进入空闲状态
    end
    
endmodule