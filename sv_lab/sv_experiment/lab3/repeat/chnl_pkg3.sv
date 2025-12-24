package chnl_pkg2;
    //全局变量，用于同步，只有生成器都发送完数据后才结束
    semaphore run_stop_flags = new();
    
    class chnl_trans;
        rand bit [31:0] data[];
        rand int ch_id;
        rand int pkg_id;
        rand int data_nidles;
        rand int pkg_nidles;
        bit rsp;
        local static int obj_id = 0;
        
        constraint c_trans{
            soft data.size inside {[4:8]};
            foreach(data[i]) data[i] == 'hC000_0000 + (ch_id << 24) + (pkg_id << 8) + i;
            soft ch_id == 0;
            soft pkg_id == 0;
            data_nidles inside {[0:2]};
            pkg_nidles inside {[1:10]};   
        };
        
        function new();
            this.obj_id++;
        endfunction
        
        function chnl_trans clone();
            chnl_trans c = new();
            c.data = this.data;  //动态数组的直接复制，共享内存
            c.ch_id = this.id;  //对于非动态数组的标量，赋值会分配独立内存
            c.pkg_id = this.pkg_id;
            c.data_nidles = this.data_nidles;
            c.pkg_nidles = this.pkg_nidles;
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
    endclass:chnl_trans
    
    class chnl_initiator;
        local virtual chnl_intf intf;
        mailbox #(chnl_trans) req_mb;
        mailbox #(chnl_trans) rsp_mb;
        local string name;
        
        function new(name = "chnl_initiator");
            this.name = name;
        endfunction
        
        function void set_name(string s);
            this.name = s;
        endfunction
        
        function set_interface(virtual chnl_intf intf);
            if(intf == null)
                $error("not this intf");
            else
                this.intf = intf;
        endtask
        
        task run();
            this.drive();
        endtask
        
        task drive();
          @(posedge intf.rstn);
          chnl_trans req,rsp;
          forever begin
            this.req_mb.get(req);
            this.chnl_write(req);
            rsp = req.clone();
            rsp.rsp = 1;
            this.rsp_mb.put(rsp);
          end
        endtask
        
        task chnl_write(input chnl_trans t);
           foreach(t.data[i]) begin  //ch_data一次只能传输1个32位数据
            @(posedge intf.clk);
            intf.drv_ck.ch_valid = 1;
            intf.drv_ck.ch_data = t.data[i];
            wait(intf.ch_ready === 1);
            repeat(t.data_nidles) chnl_idle();
           end
           repeat(t.pkt_nidles) chnl_idle();
        endtask
        
        task chnl_idle();
            @(posedge intf.clk);
            intf.drv_ck.ch_valid = 0;
            intf.drv_ck.ch_data = 0;
        endtask
    endclass: chnl_initiator
    
    class chnl_generator;
        rand int ch_id = -1;
        rand int pkg_id = -1;
        rand int data_nidles = -1;
        rand int pkg_nidles = -1;
        rand int data.size = -1;
        rand int ntrans = 10;
        
        mailbox #(chnl_trans) req_mb;
        mailbox #(chnl_trans) rsp_mb;
        
        constraint c_g{
            soft ch_id == -1;
            soft pkg_id == -1;
            soft data_nidles == -1;
            soft pkg_nidles == -1;
            soft data.size == -1;
            soft ntrans == 10;            
        };
        
        function new();
            req_mb = new();
            rsp_mb = new();
        endfunction
        
        task run();
            repeat(ntrans) send_trans();
            run_stop_flags.put();
        endtask
        
        task send_trans();
            chnl_trans req,rsp;
            req = new();
            //对req随机化，需要遵循chnl_trans类的约束条件+with后的约束条件，注意防止约束冲突
            assert(req.randomize() with {
                local::ch_id >= 0 -> ch_id = local::ch_id;
                local::pkg_id >= 0 -> pkg_id = local::pkg_id;
                local::data_nidles >= 0 -> data_nidles = local::data_nidles;
                local::pkg_nidles >= 0 -> pkg_nidles = local::pkg_nidles;
                local::data.size >= 0 -> data.size = local::data.size;
            })
            else $error("chnnel packet randomize failure");
            this.pkg_id++;
            $display(req.sprint());
            this.req_mb.put(req);
            this.rsp_mb.get(rsp);
            $display(rsp.sprint());
            assert(rsp.rsp)
                else $error("%0t error respone receive ",$time);
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
            s = {"AFTER RANDOMIZION \n",this.sprint()};
            $display(s);
        endfunction
    endclass: chnl_generator
    
    //new
    typedef struct packed{
        bit [31:0] data;
        bit [1:0] id;
    } mon_data_t;
    
    class chnl_monitor;
        local string name;
        local virtual chnl_intf intf;
        mailbox #(mon_data_t) mon_mb;
        
        function new(string name = "chnl_monitor");
            this.name = name;
        endfunction
        
        function void set_interface(virtual chnl_intf intf);
            if(intf == null)
                $error("interface handle is NULL,please check if target interface has been intantiated");
            else
                this.intf = intf;
        endfunction
        
        rask run();
            this.mon_trans();
        endtask
        
        task mon_trans();
            mon_data_t m;
            forever begin
                @(posedge intf.clk iff(intf.mon_ck.ch_valid === 1 && intf.mon_ck.ch_ready === 1 ));
                m.data = intf.mon_ck.ch_data;
                mon_mb.put(m);
                $display("%t %s monitored chnl data %8x",$time,this.name,m.data);
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
                @(posedge intf.clk iff(intf.mon_ck.mcdt_valid === 1));
                m.data = intf.mon_ck.mcdt_data;
                m.id = intf.mon_ck.mcdt_id;
                mon_mb.put(m);
                $display("%t %s monitored mcdt data %8x and id %d",$time,this.name,m.data,m.id);
            end
        endtask
    endclass
    
    class chnl_agent;
        local string name;
        chnl_initiator init;
        chnl_monitor mon;
        local virtual chnl_intf vif;
        
        function new(string name = "chnl_agent");
            this.name = name;
            init = new({name,".init"});
            mon = new({name,".mon"});
        endfunction
        
        function void set_interface(virtual chnl_intf vif);
            this.vif = vif;
            init.set_interface(vif);
            mon.set_interface(vif);
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
        local int error_count;
        local int cmp_count;
        mailbox #(mon_data_t) in_mbs[3];
        mailbox #(mon_data_t) out_mb;
        
        function new(string name = "chnl_checker");
            this.name = name;
            foreach(in_mbs[i]) this.in_mbs[i] = new();
            this.out_mb = new();
            error_count = 0;
            cmp_count = 0;
        endfunction
        
        task do_compare();
            mon_data_t im,om;
            forever begin
                out_mb.get(om);
                case(om.id)
                    0: in_mbs[0].get(im);
                    1: in_mbs[1].get(im);
                    2: in_mbs[2].get(im);
                    default : $fatal("id %d is not availed",om.id);
                endcase
                
                if(im.data != om.data) begin
                    this.error_count++;
                    $error("compared failed,mcdt out data %8x ch_id %d is not equal in data %8x",om.data,om.id,im.data);
                end
                else begin
                    $display("[CMPSUCD] Compared succeeded! mcdt out data %8x ch_id %0d is equal with channel in data %8x", om.data, om.id, im.data);                
                end
                this.cmp_count++;
            end
        endtask
    endclass
    
    class chnl_root_test;
        chnl_agent agent[3];
        chnl_generator gen[3];
        mcdt_monitor mcdt_mon;
        chnl_checker chker;
        event gen_stop_e;
        protected string name;
        
        function new(string name = "chnl_root_test");
            this.chker = new();
            foreach(agent[i]) begin
                agent[i] = new($formatf("chnl_agent[%d]",i));
                gen[i] = new();  //gen[0],gen[1],gen[2]的空间是分离的，所以其初始化空间的邮箱也是分离的
                this.agent[i].init.req_mb = this.gen[i].req_mb;
                this.agent[i].init.rsp_mb = this.gen[i].rsp_mb;
                this.agent[i].mon.mon_mb = this.chker.in_mbs[i];
            end
            this.mcdt_mon = new();
            this.mcdt_mon.mon_mb = this.chker.out_mb; 
            this.name = name;
            $display("%s intantiated object",this.name);
        endfunction
        
        virtual task gen_stop_callback();
        
        endtask
        
        virtual task run_stop_callback();
            $display("run_stop_callback enterred");
            $display("%s:wait for all generator have generated and tranferred transcation",this.name);
            run_stop_flags.get(3);
            $display($sformatf("*****%s finished*****",this.name));
            $finish();
        endtask
        
        virtual task run();
            $display($sformatf("***%s start***",this.name));
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
                @(this.gen_stop_e) disable gen_threads;
            join_none
            
            fork: gen_threads  //生成器传完数据相当于整个器件完成数据传输，因为gen每发一次数据，都需要init回应，不回应就不会再发
                gen[0].run();
                gen[1].run();
                gen[2].run();
            join
            
            run_stop_callback();
            
            $display($sformatf("%s is finished",this.name));
        endtask
        
        virtual function void set_interface(virtual chnl_intf ch0_vif,virtual chnl_intf ch1_vif,virtual chnl_intf ch2_vif,virtual mcdt_intf mcdt_vif);
            agent[0].set_interface(ch0_vif);
            agent[1].set_interface(ch1_vif);
            agent[2].set_interface(ch2_vif);
            mcdt_mon.set_interface(mcdt_vif);
        endfunction
        
        virtual function void do_config();

        endfunction
        
        class chnl_basic_test extends chnl_root_test;
            function new(string name = "chnl_basic_test");
                super.new(name);
            endfunction
            virtual function void do_config();
                super.do_config();
                assert(gen[0].randomize() with {ntrans==100; data_nidles==0; pkt_nidles==1; data_size==8;})
                    else $fatal("[RNDFAIL] gen[0] randomization failure!");
            
                // USER TODO 2.2
                // To randomize gen[1] with
                // ntrans==50, data_nidles inside [1:2], pkt_nidles inside [3:5],
                // data_size == 6
                assert(gen[1].randomize() with {ntrans==50; data_nidles inside {[1:2]}; pkt_nidles inside {[3:5]}; data_size==16;})
                    else $fatal("[RNDFAIL] gen[1] randomization failure!");
            
                // USER TODO 2.3
                // ntrans==80, data_nidles inside [0:1], pkt_nidles inside [1:2],
                // data_size == 32
                assert(gen[2].randomize() with {ntrans==80; data_nidles inside {[0:1]}; pkt_nidles inside {[1:2]}; data_size==32;})
                    else $fatal("[RNDFAIL] gen[2] randomization failure!");
            endfunction

        endclass
        
        class chnl_burst_test extends chnl_root_test;
            function new(string name = "chnl_burst_test");
                super.new(name);
            endfunction
            
            virtual function void do_config();
                assert(gen[0].randomize() with {ntrans inside {[80:100]};data_nidles == 0;pkg_nidles == 1;data_size inside{8,16,32}})
                    else $fatal("gen[0] generate fail");
                assert(gen[1].randomize() with {ntrans inside {[80:100]};data_nidles == 0;pkg_nidles == 1;data_size inside{8,16,32}})
                    else $fatal("gen[1] generate fail");
                assert(gen[2].randomize() with {ntrans inside {[80:100]};data_nidles == 0;pkg_nidles == 1;data_size inside{8,16,32}})
                    else $fatal("gen[2] generate fail");                    
            endfunction
        endclass
        
        class chnl_fifo_full_test extends chnl_root_test;
            function new(string name = "chnl_burst_test");
                super.new(name);
            endfunction
            
            virtual function void do_config();
                assert(gen[0].randomize() with {ntrans inside {[1000:2000]};data_nidles == 0;pkg_nidles == 1;data_size inside{8,16,32}})
                    else $fatal("gen[0] generate fail");
                assert(gen[1].randomize() with {ntrans inside {[1000:2000]};data_nidles == 0;pkg_nidles == 1;data_size inside{8,16,32}})
                    else $fatal("gen[1] generate fail");
                assert(gen[2].randomize() with {ntrans inside {[1000:2000]};data_nidles == 0;pkg_nidles == 1;data_size inside{8,16,32}})
                    else $fatal("gen[2] generate fail");                    
            endfunction
            
            local function bit[2:0] get_chnl_ready_flags();
                return {
                    agent[0].vif.mon_ck.ch_ready,
                    agent[1].vif.mon_ck.ch_ready,
                    agent[2].vif.mon_ck.ch_ready
                };
            endfunction
            
            virtual task gen_stop_callback();
                bit[2:0] chnl_ready_flags;
                $display("gen_stop_collback enterred");
                @(posedge agent[0].vif.rstn);
                forever begin
                    chnl_ready_flags = this.get_chnl_ready_flags();\
                    if($countones(chnl_ready_flags <= 1)) break;
                end
                
                $display("%s: stop 3 generators running",this.name);
                
                ->this.gen_stop_e;
            endtask
            
            virtual task run_stop_callback();
                fork
                    wait(agent[0].vif.ch_margin == 'h20);
                    wait(agent[1].vif.ch_margin == 'h20);
                    wait(agent[2].vif.ch_margin == 'h20);
                join
                
                $finish();
            endtask
        
        endclass
       

endpackage