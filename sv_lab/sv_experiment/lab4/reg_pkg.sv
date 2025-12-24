`include "param_def.v"
package reg_pkg;
    class reg_trans;
        rand bit [7:0] addr;
        rand bit [1:0] cmd;
        rand bit [31:0] data;
        bit rsp;
        
        constraint cstr{
            soft cmd inside {`READ,`WRITE,`IDLE};
            soft addr inside {`SLV0_RW_ADDR,`SLV1_RW_ADDR,`SLV2_RW_ADDR,`SLV0_R_ADDR,`SLV1_R_ADDR,`SLV2_R_ADDR};
            addr[7:4] == 0 && cmd == `WRITE -> soft data[31:6] == 0; 
            addr[4] == 1 -> soft cmd == `READ;
        };
        
        function reg_trans clone();
            reg_trans c = new();
            c.data = this.data;
            c.addr = this.addr;
            c.cmd = this.cmd;
            c.rsp = this.rsp;
            return c;
        endfunction
        
        function string sprint();
            string s;
            s = {s, $sformatf("=======================================\n")};
            s = {s, $sformatf("reg_trans object content is as below: \n")};            
            s = {s,$sformatf("data is %8x \n",this.data)};
            s = {s,$sformatf("cmd is %2d \n",this.cmd)};
            s = {s,$sformatf("addr is %2x \n",this.addr)};
            s = {s,$sformatf("rsp is %d \n",this.rsp)};
            s = {s, $sformatf("=======================================\n")};
            return s;
        endfunction

    endclass
    //将数据驱动给待测DUT，通过接口传递
    class reg_driver;
        local string name;
        local virtual reg_intf intf;
        mailbox #(reg_trans) req_mb;
        mailbox #(reg_trans) rsp_mb;
        
        function new(string name = "req_driver");
            this.name = name;
        endfunction
        
        function void set_name(string s);
            this.name = s;
        endfunction
        
        function void set_interface(virtual reg_intf intf);
            if(intf == null)
                $error("handle is not have been intantiated");
            else 
                this.intf = intf;
        endfunction
        
        task run();
            fork
                this.do_drive();
                this.do_reset();
            join
        endtask
        
        task do_reset();
            @(negedge intf.rstn);
            intf.drv_ck.cmd <= `IDLE;
            intf.drv_ck.cmd_addr <= 0;
            intf.drv_ck.cmd_data_m2s <= 0;            
        endtask
        
        task do_drive();
            reg_trans req,rsp;
            @(posedge intf.rstn);
            forever begin
                this.req_mb.get(req);
                this.reg_write(req);
                rsp = req.clone();
                rsp.rsp = 1;
                this.rsp_mb.put(rsp);
            end
        endtask
        
        task reg_write(input reg_trans t);
            @(posedge intf.clk iff intf.rstn);
            case(t.cmd)
                `READ: begin
                    intf.drv_ck.cmd_addr <= t.addr;
                    intf.drv_ck.cmd <= t.cmd;
                    repeat(2) @(negedge intf.clk);
                    t.data <= cmd_data_s2m;
                end
                `WRITE: begin
                    intf.drv_ck.cmd <= t.cmd;
                    intf.drv_ck.cmd_addr <= t.addr;    
                    intf.drv_ck.cmd_data_m2s <= t.data;
                end
                `IDLE: begin
                    this.reg_idle();
                end
                default: $error("command %d si illegal",t.cmd);
            endcase
        endtask
        
        task reg_idle();
            @(posedge intf.clk);
            intf.drv_ck.cmd <= `IDLE;
            intf.drv_ck.cmd_addr <= 0;
            intf.drv_ck.cmd_data_m2s <= 0;
        endtask 
    endclass
    
    //生成器
    class reg_generator;
        rand bit [31:0] data = -1;
        rand bit [7:0]  addr = -1;
        rand bit [1:0]  cmd = -1;
        
        mailbox #(reg_trans) req_mb;
        mailbox #(req_trans) rsp_mb;

        
        constraint cstr{
            soft data == -1;
            soft addr == -1;
            soft cmd == -1;
        };
        
        function new();
            req_mb = new();
            rsp_mb = new();
        endfunction
        
        task start();
            this.send_trans();
        endtask
        
        task send_trans();
            reg_trans req,rsp;
            assert(req.randomize() with {local::data >= 0 -> data == local::data;
                                         local::cmd >= 0 -> cmd == local::cmd;
                                         local::addr >= 0 -> addr == local::addr;})
                else $fatal("[RNDFAIL] register packet randomization failure!");
            $display(req.sprint());
            req_mb.put(req);
            rsp_mb.get(rsp);
            $display(rsp.sprint());
            if(req.cmd == `READ)
                this.data = rsp.data;
            assert(rsp.rsp)
                else $fatal("%t error recieve response",$time);
        endtask
        
        function string sprint();
            string s;
            s = {s,$sformatf(" cmd = %2d \n",this.cmd)};
            s = {s,$sformatf(" data = %8x \n",this.data)};
            s = {s,$sformatf(" addr = %2x \n",this.addr)};
            return s;
        endfunction
        
        function void post_randomize();
            string s;
            s = {"AFTER RANDOMIZE \n",this.sprint()};
            $display(s);
        endfunction
  
    endclass
    
    //监测器（从接口采集信号）
    class reg_monitor;
        local virtual reg_intf intf;
        local string name;
        mailbox #(req_trans) mon_mb;
        
        function new(string name = "reg_monitor");
            this.name = name;
        endfunction
        
        function void set_interface(virtual reg_intf intf);
            if(intf == null)
                $error("handle is not have been intantiated");
            else    
                this.intf = intf;
        endfunction
        
        
        
        task mon_trans();
            reg_trans m;
            forever begin
                @(posedge intf.clk iff(intf.rstn && intf.drv_ck.cmd != `IDLE));
                m = new();
                m.addr <= intf.mon_ck.cmd_addr;
                m.cmd <= intf.mon_ck.cmd;
                if(intf.mon_ck.cmd == `WRITE)
                    m.data <= intf.mon_ck.cmd_data_m2s;
                else if(intf.mon_ck.cmd == `READ) begin
                    @(posedge intf.clk);
                    m.data <= intf.mon_ck.cmd_data_s2m;
                end
                mon_mb.put(m);
                $display("%0t %s monitored addr %2x,cmd %2d,data = %8x",$time,this.name,m.addr,m.cmd,m.data);
            end
        
        endtask
        
    endclass
    
    class reg_agent;
        reg_driver driver;
        reg_monitor monitor;
        local string name;
        local virtual reg_intf vif;
        
        function new(string name = "reg_agent");
            this.name = name;
            this.driver = new({name,".driver"});
            this.monitor = new({name,".monitor"});
        endfunction
        
        function void set_interface(virtual reg_intf vif);
            this.vif = vif;
            driver.set_interface(vif);
            monitor.set_interface(vif);
        endfunction
        
        task run();
            fork
                driver.run();
                monitor.run();
            join
        endtask
    endclass

endpackage