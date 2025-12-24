package chnl_pkg2;
  semaphore run_stop_flags = new();
  class chnl_trans;
    rand bit[31:0] data[];
    rand int ch_id;
    rand int pkt_id;
    rand int data_nidles;
    rand int pkt_nidles;
    bit rsp;
    local static int obj_id = 0;
    constraint cstr{
      soft data.size inside {[4:8]};
      foreach(data[i]) data[i] == 'hC000_0000 + (this.ch_id<<24) + (this.pkt_id<<8) + i;
      soft ch_id == 0;
      soft pkt_id == 0;
      data_nidles inside {[0:2]};
      pkt_nidles inside {[1:10]};
    };

    function new();
      this.obj_id++;
    endfunction

    function chnl_trans clone();
      chnl_trans c = new();
      c.data = this.data;
      c.ch_id = this.ch_id;
      c.pkt_id = this.pkt_id;
      c.data_nidles = this.data_nidles;
      c.pkt_nidles = this.pkt_nidles;
      c.rsp = this.rsp;
      return c;
    endfunction

    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("chnl_trans object content is as below: \n")};
      s = {s, $sformatf("obj_id = %0d: \n", this.obj_id)};
      foreach(data[i]) s = {s, $sformatf("data[%0d] = %8x \n", i, this.data[i])};
      s = {s, $sformatf("ch_id = %0d: \n", this.ch_id)};
      s = {s, $sformatf("pkt_id = %0d: \n", this.pkt_id)};
      s = {s, $sformatf("data_nidles = %0d: \n", this.data_nidles)};
      s = {s, $sformatf("pkt_nidles = %0d: \n", this.pkt_nidles)};
      s = {s, $sformatf("rsp = %0d: \n", this.rsp)};
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction
  endclass: chnl_trans
  
  class chnl_initiator;
    local string name;
    local virtual chnl_intf intf;
    mailbox #(chnl_trans) req_mb;
    mailbox #(chnl_trans) rsp_mb;
  
    function new(string name = "chnl_initiator");
      this.name = name;
    endfunction
  
    function void set_name(string s);
      this.name = s;
    endfunction
  
    function void set_interface(virtual chnl_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction

    task run();
      this.drive();
    endtask

    task drive();
      chnl_trans req, rsp;
      @(posedge intf.rstn);
      forever begin
        this.req_mb.get(req);
        this.chnl_write(req);
        rsp = req.clone();
        rsp.rsp = 1;
        this.rsp_mb.put(rsp);
      end
    endtask
  
    task chnl_write(input chnl_trans t);
      foreach(t.data[i]) begin
        @(posedge intf.clk);
        intf.drv_ck.ch_valid <= 1;
        intf.drv_ck.ch_data <= t.data[i];
        wait(intf.ch_ready === 'b1);
        $display("%0t channel initiator [%s] sent data %x", $time, name, t.data[i]);
        repeat(t.data_nidles) chnl_idle();
      end
      repeat(t.pkt_nidles) chnl_idle();
    endtask
    
    task chnl_idle();
      @(posedge intf.clk);
      intf.drv_ck.ch_valid <= 0;
      intf.drv_ck.ch_data <= 0;
    endtask
  endclass: chnl_initiator
  
  class chnl_generator;
    rand int pkt_id = -1;
    rand int ch_id = -1;
    rand int data_nidles = -1;
    rand int pkt_nidles = -1;
    rand int data_size = -1;
    rand int ntrans = 10;

    mailbox #(chnl_trans) req_mb;
    mailbox #(chnl_trans) rsp_mb;

    constraint cstr{
      soft ch_id == -1;
      soft pkt_id == -1;
      soft data_size == -1;
      soft data_nidles == -1;
      soft pkt_nidles == -1;
      soft ntrans == 10;
    }

    function new();
      this.req_mb = new();
      this.rsp_mb = new();
    endfunction

    task run();
      repeat(ntrans) send_trans();
	  run_stop_flags.put();
    endtask

    // generate transaction and put into local mailbox
    task send_trans();
      chnl_trans req, rsp;
      req = new();
      assert(req.randomize with {local::ch_id >= 0 -> ch_id == local::ch_id; 
                                 local::pkt_id >= 0 -> pkt_id == local::pkt_id;
                                 local::data_nidles >= 0 -> data_nidles == local::data_nidles;
                                 local::pkt_nidles >= 0 -> pkt_nidles == local::pkt_nidles;
                                 local::data_size >0 -> data.size() == local::data_size; 
                               })
        else $fatal("[RNDFAIL] channel packet randomization failure!");
      this.pkt_id++;
      $display(req.sprint());
      this.req_mb.put(req);
      this.rsp_mb.get(rsp);
      $display(rsp.sprint());
      assert(rsp.rsp)
        else $error("[RSPERR] %0t error response received!", $time);
    endtask

    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("chnl_generator object content is as below: \n")};
      s = {s, $sformatf("ntrans = %0d: \n", this.ntrans)};
      s = {s, $sformatf("ch_id = %0d: \n", this.ch_id)};
      s = {s, $sformatf("pkt_id = %0d: \n", this.pkt_id)};
      s = {s, $sformatf("data_nidles = %0d: \n", this.data_nidles)};
      s = {s, $sformatf("pkt_nidles = %0d: \n", this.pkt_nidles)};
      s = {s, $sformatf("data_size = %0d: \n", this.data_size)};
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction

    function void post_randomize();
      string s;
      s = {"AFTER RANDOMIZATION \n", this.sprint()};
      $display(s);
    endfunction
  endclass: chnl_generator
  
  typedef struct packed{
	bit [1:0] id;
	bit [31:0] data;
  }mon_data_t;
  
  class chnl_monitor;
	local string name;
	local virtual chnl_intf intf;
	mailbox #(mon_data_t) mon_mb;
	
	function new(string name = "chnl_monitor");
		this.name = name;
	endfunction
	
	function void set_interface(virtual chnl_intf intf);
		if(intf == null)
			$error("interface handle is NULL,please check if target interface have been intantiated");
		else
			this.intf = intf;
	endfunction
	
	task run();
		this.mon_trans();
	endfunction
	
	task mon_trans();
		mon_data_t m;
		forever begin
			@(posedge intf.clk iff ((intf.mon_ck.ch_ready === 1) && (intf.mon_ck.ch_valid === 1)));
			m.data = intf.mon_ck.ch_data;
			mon_mb.put(m);
			$display("%t %s monitored channel data %x",%time,this.nane,m.data);
		end
	endtask
  endclass
  
  class mcdt_monitor;
	local string name;
	local virtual mcdt_intf intf;
	mailbox #(mon_data_t) mon_mb;
	
	function new(string name = "mcdt_monitor");
		this.name = name;
	endfunction
	
	function void set_interface(virtual mcdt_intf intf);
		if(intf == null)
			$error("interface handle is NULL,please check if target has been intantiated");
		else
			this.intf = intf;
	endfunction
	
	task run();
		this.mon_trans();
	endtask
	
	task mon_trans();
		mon_data_t m;
		forever begin 
			@(posedge intf.clk iff(intf.mon_ck.mcdt_val === 1));
			m.data = intf.mon_ck.mcdt_data;
			m.id = intf.mon_ck.mcdt_id;
			mon_mb.put(m);
			$display("%t %s monitored data is %x and id is %d",$time,this.name,m.data,m.id);
		end
	endtask
  endclass

  class chnl_agent;
	local string name;
    chnl_initiator init;
	chnl_monitor mon;
    virtual chnl_intf vif;
	
    function new(string name = "chnl_agent");
	  this.name = name;
      this.init = new({name,".init"});
	  this.mon = new({name,".mon"});
    endfunction
	
    function void set_interface(virtual chnl_intf vif);
      this.vif = vif;
      this.init.set_interface(vif);
	  this.mon.set_interface(vif);
    endfunction
	
    task run();
      fork
        init.run();
		mon.run();
      join
    endtask
  endclass: chnl_agent
  
  class chnl_checker;
	local string name;
	mailbox #(mon_data_t) in_mbs[3];
	mailbox #(mon_data_t) out_mb;
	local int error_count;
	local int cmp_count;
	
	function new(string name = "chnl_checker");
		this.name = name;
		foreach(in_mbs[i]) in_mbs[i] = new();
		out_mb = new();
		
	endfunction
	
	task run();
		this.do_compare();
	endtask
	
	task do_compare();
		mon_data_t im,om;
		forever begin
			out_mb.get(om);
			case(om.id)
			  0:in_mbs[0].get(im);
			  1:in_mbs[1].get(im);	
			  2:in_mbs[2].get(im);	
			  default:$fatal("id %d is not available",om.id);
			endcase
			if(om.data != im.data)begin
				this.error_count++;
				$display("[FAIL] om.data is %x != im.data is %x",om.data,im.data);
				end
			else
				$display("[SUCC] om.data is %x = im.data is %x",om.data,im.data);
			this.cmp_count++;
		end
	endtask
  endclass

  class chnl_root_test;
    chnl_generator gen[3];
    chnl_agent agent[3];
	chnl_checker chker;
	mcdt_monitor mcdt_mon;
    protected string name;
	event gen_stop_e;

    function new(string name = "chnl_root_test");
	  chker = new();
	  this.name = name;
      foreach(agent[i]) begin
        this.agent[i] = new($sformatf("chnl_agent%0d",i));
        this.gen[i] = new();
        // USER TODO 2.1
        // Connect the mailboxes handles of gen[i] and agent[i].init
		this.agent[i].intf.req_mb = this.gen[i].req_mb;
		this.agent[i].intf.rsp_mb = this.gen[i].rsp_mb;
		this.agent[i].mon.mon_mb = this.chker.in_mbs[i];
      end
	  this.mcdt_mon = new();
	  this.mcdt_mon.mon_mb = this.chker.out_mb;
      this.name = name;
      $display("%s instantiate objects", this.name);
    endfunction

    virtual task run();
      $display($sformatf("*****************%s started********************", this.name));
      this.do_config();
      fork
        agent[0].run();
        agent[1].run();
        agent[2].run();
		mcdt_mon.run();
		chker.run();
      join_none
	  
	  fork 
		this.gen_stop_callback();
		@(gen_stop_e) disable fork_all_run;
	  join_none
	  
      fork : fork_all_run
        gen[0].run();
        gen[1].run();
        gen[2].run();
      join
	  
	  run_stop_callback();
      
      // USER TODO 1.3
      // Please move the $finish statement from the test run task to generator
      // You woudl put it anywhere you like inside generator to stop test when
      // all transactions have been transfered

    endtask
	//一个是判断仿真结束任务
	virtual task run_stop_callback();
		$display("run_stop_callback enterred");
		$display("%s : wait all generator have generated and transferred transaction",this.name);
		run_stop_flags.get(3);
		$display($sformatf("*****************%s finished********************", this.name));
		$finish();
	endtask
	//一个是终止发送任务（当满足要求时，用于fifo_full_test）
	virtual task gen_stop_callback();
	
	endtask

    virtual function void set_interface(virtual chnl_intf ch0_vif, virtual chnl_intf ch1_vif, virtual chnl_intf ch2_vif);
      agent[0].set_interface(ch0_vif);
      agent[1].set_interface(ch1_vif);
      agent[2].set_interface(ch2_vif);
    endfunction


    virtual function void do_config();
      assert(gen[0].randomize() with {ntrans==100; data_nidles==0; pkt_nidles==1; data_size==8;})
        else $fatal("[RNDFAIL] gen[0] randomization failure!");

      // USER TODO 2.2
      // To randomize gen[1] with
      // ntrans==50, data_nidles inside [1:2], pkt_nidles inside [3:5],
      // data_size == 6
	  assert(gen[1].randomize() with {ntrans==50;data_nidles inside{[1:2]};pkt_nidles inside {[3:5]};data_size==6;})
		else $fatal("[RNDFALL] gen[1] randomization failure!");

      // USER TODO 2.3
      // ntrans==80, data_nidles inside [0:1], pkt_nidles inside [1:2],
      // data_size == 32
	  assert(gen[2].randomize() with {ntrans==80;data_nidles inside {[0:1]};pkt_nidles inside {[1:2]};data_size==32;})
		else $fatal("[RNDFALL] gen[1] randomization failure!");
    endfunction
  endclass

  class chnl_basic_test extends chnl_root_test;
    function new(string name = "chnl_basic_test");
      super.new(name);
    endfunction
  endclass: chnl_basic_test

  // USER TODO 2.4
  // each channel send data packet number inside [80:100]
  // data_nidles == 0, pkt_nidles == 1, data_size inside {8, 16, 32}
  class chnl_burst_test extends chnl_root_test;
    function new(string name = "chnl_burst_test");
      super.new(name);
    endfunction
	
	function void do_config();
      assert(gen[0].randomize() with {ntrans inside {[80:100]}; data_nidles==0; pkt_nidles==1; data_size inside {8,16,32};})
        else $fatal("[RNDFAIL] gen[0] randomization failure!");		
      assert(gen[1].randomize() with {ntrans inside {[80:100]}; data_nidles==0; pkt_nidles==1; data_size inside {8,16,32};})
        else $fatal("[RNDFAIL] gen[1] randomization failure!");	
      assert(gen[2].randomize() with {ntrans inside {[80:100]}; data_nidles==0; pkt_nidles==1; data_size inside {8,16,32};})
        else $fatal("[RNDFAIL] gen[2] randomization failure!");	
	endfunction
	
    //USER TODO
  endclass: chnl_burst_test

  // USER TODO 2.5
  // keep channel sending out data packet with number, and please
  // let all of slave channels raising fifo_full (ready=0) at the same time
  // and then to stop the test
  class chnl_fifo_full_test extends chnl_root_test;
    function new(string name = "chnl_fifo_full_test");
      super.new(name);
    endfunction
	
	function void do_config();
      assert(gen[0].randomize() with {ntrans inside {[1000:2000]}; data_nidles==0; pkt_nidles==1; data_size inside {8,16,32};})
        else $fatal("[RNDFAIL] gen[0] randomization failure!");		
      assert(gen[1].randomize() with {ntrans inside {[1000:2000]}; data_nidles==0; pkt_nidles==1; data_size inside {8,16,32};})
        else $fatal("[RNDFAIL] gen[1] randomization failure!");	
      assert(gen[2].randomize() with {ntrans inside {[1000:2000]}; data_nidles==0; pkt_nidles==1; data_size inside {8,16,32};})
        else $fatal("[RNDFAIL] gen[2] randomization failure!");	
	endfunction
	
	function bit[2:0] get_chnl_ready_flags();
		return {agent[0].vif.ch_ready,agent[1].vif.ch_ready,agent[2].vif.ch_ready};
	endfunction
	
	task gen_stop_callback();
		bit [3:0] chnl_ready_flags;
		@(posedge agent[0].vif.rstn);
		forever begin
			@(posedge agent[0].vif.clk);  //获取上升沿来临的数据
			chnl_ready_flags = this.get_chnl_ready_flags();
			if($countones(chnl_ready_flags) <= 1) break;
		end
		-> gen_stop_e;
	endtask
	
	task run_stop_callback();
      $display("run_stop_callback enterred");
		fork
			wait(agent[0].vif.ch_margin == 'h20);
			wait(agent[1].vif.ch_margin == 'h20);
			wait(agent[2].vif.ch_margin == 'h20);
		join
		$display("%s: 3 channel fifos have transferred all data", this.name);
		$display($sformatf("*****************%s finished********************", this.name));
		$finish();
	endtask
	
    // USER TODO
  endclass: chnl_fifo_full_test

endpackage


