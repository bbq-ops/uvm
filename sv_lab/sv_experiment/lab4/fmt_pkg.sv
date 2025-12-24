
package fmt_pkg;
    import rpt_pkg::*;
    
    typedef enum {
        SHORT_FIFO,
        MED_FIFO,
        LONG_FIFO,
        ULTRA_FIFO
    } fmt_fifo_t;
    
    typedef enum{
        LOW_WIDTH,
        MED_WIDTH,
        HIGH_WIDTH,
        ULTRA_WIDTH
    } fmt_bandwidth_t;
    
    class fmt_trans;
        rand fmt_fifo_t fifo;
        rand fmt_bandwidth_t bandwidth;
        bit [9:0] length;
        bit [31:0] data[];
        bit [1:0] ch_id;
        bit rsp;
        
        constraint cstr{
            soft fifo == MED_FIFO;
            soft bandwidth == MED_WIDTH;
        };
        
        function fmt_trans clone();
            fmt_trans c = new();
            c.fifo = this.fifo;
            c.bandwidth = this.bandwidth;
            c.data = this.data;
            c.length = this.length;
            c.ch_id = this.ch_id;
            c.rsp = this.rsp;
            return c;
        endfunction
        
        function string sprint();
            string s;
            s = {s,$sformatf("================= \n")};
            s = {s,$sformatf("fmt_trans object content is as below : \n")};
            s = {s,$sformatf("fifo = %s \n",this.fifo)};
            s = {s,$sformatf("bandwidth = %s \n",this.bandwidth)};
            foreach(data[i]) s = {s,$sformatf("data[%d] = %8x \n",i,this.data[i])};
            s = {s,$sformatf("length = %0d \n",this.length)};
            s = {s,$sformatf("ch_id = %0d \n",this.ch_id)};
            s = {s,$sformatf("rsp = %0d \n",this.rsp)};
            return s;
        endfunction
        
        //比较函数
        function bit compare(fmt_trans t);
            string s;
            compare = 1;
            
            s = "================\n"
            s = {s,$sformatf("COMPARING fmt_trans object at time %0t \n", $time)};
            
            if(this.length != t.length)begin
                compare = 0;
                s = {s,$sformatf("this.length  %d != t.length %d \n",this.length,t.length)};
            end
            
            if(this.ch_id != t.ch_id) begin
                compare = 0;
                s = {s,$sformatf("this.ch_id %d != t.ch_id %d \n",this.ch_id,t.ch_id)};
            end
            
            foreach(data[i]) begin
                if(this.data[i] != t.data[i]) begin
                    compare = 0;
                    s = {s,"this.data[%d] %8x != t.data[%d] %8x",i,this.data[i],i,t.data[i]};
                end
            end
            
            if(compare == 1) 
                s = {s,$sformatf("COMPARE SUCCESS \n")};
            else
                s = {"COMPARED FAILURE! \n"};
            
            s = {s,$sformatf("=================\n")};
            
            rpt_pkg::rpt_msg("[CMPOBJ]", s, rpt_pkg::INFO, rpt_pkg::MEDIUM);  
        endfunction
    endclass
    
    class fmt_driver;
        local string name;
        local virtual fmt_intf intf;
        mailbox #(fmt_trans) req_mb;
        mailbox #(fmt_trans) rsp_mb;
        
        local mailbox #(bit[31:0]) fifo;
        local int fifo_bound;
        local int data_consum_peroid;
        
        function new(string name = "fmt_driver");
            this.name = name;
            fifo = new();
            fifo_bound = 4096;
            data_consum_peroid = 1;
        endfunction
        
        function void set_interface(virtual fmt_intf intf);
            if(intf == null)
                $error("interface handle in NULL,please check if target interface has been intantiated");
            else
                this.intf = intf;
                
        task run();
            fork
                this.do_config();
                this.do_recieve();
                this.do_consume();
                this.reset();
            join
        endtask
        
        //从请求邮箱获取配置，更新驱动参数并返回响应
        task do_config();
            fmt_trans req,rsp;
            
            forever begin
                this.req_mb.get(req); //阻塞获取配置请求
                
                case(req.fifo)
                    SHORT_FIFO: this.fifo_bound = 64;    // 短FIFO容量64
                    MED_FIFO:   this.fifo_bound = 256;     // 中等FIFO容量256
                    LONG_FIFO:  this.fifo_bound = 512;    // 长FIFO容量512
                    ULTRA_FIFO: this.fifo_bound = 2048;  // 超大FIFO容量2048
                endcase                
                this.fifo = new(this.fifo_bound);
                
                case(req.bandwidth)
                    LOW_WIDTH: this.data_consum_peroid = 8;  
                    MED_WIDTH: this.data_consum_peroid = 4;  
                    HIGH_WIDTH: this.data_consum_peroid = 2; 
                    ULTRA_WIDTH: this.data_consum_peroid = 1;
                endcase
                
                rsp = req.clone();
                rsp.rsp = 1;
                this.rsp_mb.put(rsp);
            end
        endtask
        
        task do_reset();
            forever begin
                @(negedge intf.rstn);
                intf.drv_ck.grant <= 0;
            end
        endtask
        
        task do_recieve();
            forever begin
                @(posedge intf.fmt_req);
                forever begin
                    if(this.fifo_bound - this.fifo.num() >= intf.fmt_length)
                        break;
                end
                
                intf.drv_ck.fmt_grant <= 1;
                @(posedge intf.fmt_start);
                
                fork 
                    begin
                    @(posedge intf.clk);
                    intf.drv_ck.fmt_grant <= 0;
                    end
                join_none
                
                repeat(intf.fmt_length) begin
                    @(negedge intf.clk);
                    this.fifo.put(intf.fmt_data);
                end
            end
        endtask
        
        //控制读取输出速率
        task do_consume();
            bit [31:0] data;
            forever begin
                void'(this.fifo.try_get(data));
                repeat($urandom_range(1,this.data_consum_peroid)) @(posedge intf.clk);
            end
        endtask
    
    endclass
    
    class fmt_generator;
        rand fmt_fifo_t fifo = MED_FIFO;
        rand fmt_bandwidth_t bandwidth = MED_WIDTH;
        
        mailbox #(fmt_trans) req_mb;
        mailbox #(fmt_trans) rsp_mb;
        
        constraint cstr{
            soft fifo == MED_FIFO;
            soft bandwidth == MED_WIDTH;
        };
        
        function new();
            req_mb = new();
            rsp_mb = new();
        endfunction
        
        task start();
            send_trans();
        endtask    
                
        task send_trans();
            fmt_trans req,rsp;
            req = new();
            assert(req.randomize() with{
                local::fifo != MED_FIFO -> fifo == local::fifo;
                local::bandwidth != MED_WIDTH -> bandwidth == local::bandwidth; 
            })
                else $fatal("formater packet randomization failure!");
            $display(req.sprint());
            this.req_mb.put(req);
            this.rsp_mb.get(rsp);
            $display(rsp.sprint());
            
            assert(rsp.rsp)
                else $error("%0t error response received",$time);
        endtask
        
        function string sprint();
            string s;
            s = {s, $sformatf("=======================================\n")};
            s = {s, $sformatf("fmt_generator object content is as below: \n")};
            s = {s, $sformatf("fifo = %s \n", this.fifo)};          // 打印FIFO配置
            s = {s, $sformatf("bandwidth = %s \n", this.bandwidth)};// 打印带宽配置
            s = {s, $sformatf("=======================================\n")};
            return s;            
        endfunction
        
        function void post_randomize();
            string s;
            s = {"AFTER RANDOMIZE \n",this.sprint()};
            $display(s);
        endfunction
        
    endclass
    
    class fmt_monitor;
        local virtual fmt_intf intf;
        string name;
        mailbox #(fmt_trans) mon_mb;
        
        function new(string name = "fmt_monitor");
            this.name = name;
        endfunction

        function void set_interface(virtual fmt_trans intf);
            if(intf == null)
             $error("handle is not have been intantiated");
            else
                this.intf = intf;
        endfunction
        
        task mon_trans();
            fmt_trans m;
            forever begin
                @(posedge intf.mon_ck.fmt_start);
                m = new();
                m.length = intf.mon_ck.fmt_length;
                m.ch_id = intf.mon_ck.fmt_chid;
                m.data = new[m.length];
                
                foreach(m.data[i]) begin
                    @(posedge intf.clk);
                    m.data[i] = intf.mon_ck.fmt_data;
                end
                
                mon_mb.put(m);
                s = $sformatf("=======================================\n");
                s = {s, $sformatf("%0t %s monitored a packet: \n", $time, this.name)};
                s = {s, $sformatf("length = %0d \n", m.length)};
                s = {s, $sformatf("chid = %0d \n", m.ch_id)};
                foreach(m.data[i]) s = {s, $sformatf("data[%0d] = %8x \n", i, m.data[i])};
                s = {s, $sformatf("=======================================\n")};
                $display(s);            
            end
        endtask
    
    endclass
    
    class fmt_agent;
        fmt_driver driver;
        fmt_monitor monitor;
        local virtual fmt_intf vif;
        local string name;
        
        function new(string name = "fmt_agent");
            this.driver = new({name,".driver"});
            this.monitor = new({name,".monitor"});
            this.name = name;
        endfunction
        
            // 接口绑定函数：统一为驱动和监视器绑定虚拟接口
        function void set_interface(virtual fmt_intf vif);
            this.vif = vif;
            driver.set_interface(vif);  // 驱动绑定接口
            monitor.set_interface(vif); // 监视器绑定接口
        endfunction
    
        // 主运行任务：并行启动驱动和监视器
        task run();
            fork
                driver.run();  // 启动驱动
                monitor.run(); // 启动监视器
            join
        endtask
    
    endclass


endpackage