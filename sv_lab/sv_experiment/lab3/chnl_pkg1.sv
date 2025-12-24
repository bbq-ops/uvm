//定义一个通道相关的包，包含事务、发起器、生成器、代理及测试类等验证组件
package chnl_pkg1;
	
	//通道事务类：描述一次数据传输的属性和数据内容，是验证环境中数据传输的基本单元
	class chnl_trans;
		rand bit [31:0] data[];  //随机动态数组，存储传输数据流
		rand int ch_id;  //随机通道id，标识数据所属通道
		rand int pkt_id;  //随机包id，标识当前包在通道的序号
		rand int data_nidles;  //数据空闲周期，data[0]和data[1]的空闲周期
		rand int pkt_nidles;  //包间空闲周期，包1和包2间的空闲周期
		bit rsp;  //响应标志，用于标识事务是否已被响应
		local static int obj_id = 0;  //静态变量，用于记录事务对象的总个数（本地变量，仅类中可见）
		
		//约束块：限制随机变量的取值范围，确保生成符合需求的事务
		constraint cstr{
			data.size inside {[4:8]}; //数据长度4到8个32位数据
			//每个数据按固定格式生成：基值C000_0000 + 通道ID左移24位 + 包id左移8位 + 索引
			foreach(data[i]) data[i] = 'hC000_0000 + (ch_id << 24) + (pkt_id << 8) + i;
			soft ch_id == 0;  //软约束：通道id默认为0（可被外部约束覆盖）
			soft pkt_id == 0;  
			data_nidles inside {[0:2]};  //数据空闲周期为0-2
			pkt_nidles inside {[1:10]};  //包空闲周期1-10
			};
			
		//构造函数：创建事务对象是，自动递增obj_id（记录总对象数）
		function new();
			this.obj_id++;
		endfunction
		
		//克隆函数：复制当前事务对象的属性，生成一个新的事务对象
		function chnl_trans clone();
			chnl_trans c = new();  //创建新对象（obj_id+1）
			c.data = this.data;
			c.ch_id = this.ch_id;
			c.pkt_id = this.pkt_id;
			c.data_nidles = this.data_nidles;
			c.pkt_nidles = this.pkt_nidles;
			c.rsp = this.rsp;
			
			return c;
		endfunction
			
		//打印函数：格式化输出事务的所有属性，用于调试和日志
		function string sprint();
			string s;
			s = {s,$sformatf("=======================================\n")};
			s = {s,$sformatf("chnl_trans object content is as below: \n")};
			s = {s,$sformatf("obj_id = %0d:\n",this.obj_id)};
			foreach(data[i]) s = {s,$sformatf("data[%0d] = %8x \n",i,this.data[i])};
			s = {s, $sformatf("ch_id = %0d: \n", this.ch_id)};
			s = {s, $sformatf("pkt_id = %0d: \n", this.pkt_id)};
			s = {s, $sformatf("data_nidles = %0d: \n", this.data_nidles)};
			s = {s, $sformatf("pkt_nidles = %0d: \n", this.pkt_nidles)};
			s = {s, $sformatf("rsp = %0d: \n", this.rsp)};
			s = {s, $sformatf("=======================================\n")};	
			return s;
		endfunction		
	endclass :chnl_trans
	
	//通道发起器类：负责生成事务通过接口驱动到DUT
	class chnl_initiator;
		local string name;  //发起器名称（本地变量，仅类中可见）
		local virtual chnl_intf intf;  //虚拟接口句柄，连接到物理接口
		mailbox #(chnl_trans) req_mb;  //请求邮箱：接收来自生成器的事务
		mailbox #(chnl_trans) rsp_mb;  //响应邮箱： 向生成器返回处理结果
		
		//构造函数：初始化发起器名称
		function new(string name = "chnl_initiator");
			this.name = name;
		endfunction
		
		//设置发起器名称
		function void set_name(string s);
			this.name = s;
		endfunction

		//设置接口句柄：绑定到物理接口，如果接口为空则报错
		function void set_interface(virtual chnl_intf intf);
			if(intf == null)
				$error("interface handle is NULL, please check if target interface has been intantiated");
			else
				this.intf = intf;
		endfunction
		
		task run();
			this.drive();
		endtask
		
		//驱动任务：从请求邮箱中取事务，然后调用chnl_write发送数据，处理后通过响应邮箱返回
		task drive();
			chnl_trans req,rsp;
			@(posedge intf.rstn)
			forever begin
				this.req_mb.get(req);  //从邮箱中获取数据赋值给req
				this.chnl_write(req);
				rsp = req.clone();
				rsp.rsp = 1;  //标记响应完成
				this.rsp_mb.put(rsp);  //将数据写入响应邮箱
			end
		endtask
		
		//写任务通道：将事务中的数据逐渐位驱动到接口
		task chnl_write(input chnl_trans t);
			foreach(t.data[i]) begin
				@(posedge intf.clk);
				intf.drv_ck.ch_valid <= 1'b1;
				intf.drv_ck.ch_data <= t.data[i];
				wait(intf.ch_ready === 1'b1);
				$display("%0t channel initiator [%s] sent data %x", $time, name, t.data[i]);
				repeat(t.data_nidles) chnl_idle();
			end
			repeat(t.pkt_nidles) chnl_idle();
		endtask
		
		//空闲任务
		task chnl_idle();
			intf.drv_ck.ch_valid <= 1'b0;
			intf.drv_ck.ch_data <= 0;			
		endtask
		
	endclass:chnl_initiator
		
endpackage