class ctrl_reg extends uvm_reg;
    `uvm_object_utils(ctrl_reg)
    uvm_reg_field reserved;
    rand uvm_reg_field pkt_len;
    rand uvm_reg_field prio_level;
    rand uvm_reg_field chnl_en;
    
    function new(string name = "ctrl_reg");
        super.new(name,32,UVM_NO_COVERAGE);
    endfunction
    
    virtual function build();
        reserved = uvm_reg_field::type_id::create("reserved");
        pkt_len = uvm_reg_field::type_id::create("pkt_len");
        prio_level = uvm_reg_field::type_id::create("prio_level");
        chnl_en = uvm_reg_field::type_id::create("chnl_en");
        reserved.configure(this,26,6,"RO",0,26'h0,1,0,0);
        pkt_len.configure(this,3,3,"RW",0,3'h0,1,1,0);
        prio_level.configure(this,2,1,"RW",0,2'h3,1,1,0);
        chnl_en.configure(this,1,0,"RW",0,1'h0,1,1,0);
    endfunction
endclass

class stat_reg extends uvm_reg;
    `uvm_object_utils(stat_reg)
    uvm_reg_field reserved;
    rand uvm_reg_field fifo_avail;
    function new(string name = "stat_reg");
        super.new(name,32,UVM_NO_COVERAGE);
    endfunction
    
    virtual function build();
        reserved = uvm_reg_field::type_id::create("reserved");
        fifo_avail = uvm_reg_field::type_id::create("fifo_avail");
        reserved.configure(this,24,8,"RO",0,24'h0,1,0,0);
        fifo_avail.configure(this,8,0,"RW",0,8'h0,1,1,0);
    endfunction
endclass

class mcdf_rgm extends uvm_reg_block;
    `uvm_object_utils(mcdf_rgm)
    rand ctrl_reg chnl0_ctrl_reg;
    rand ctrl_reg chnl1_ctrl_reg;
    rand ctrl_reg chnl2_ctrl_reg;
    rand stat_reg chnl0_stat_reg;
    rand stat_reg chnl1_stat_reg;
    rand stat_reg chnl2_stat_reg;
    uvm_reg_map map;
    function new(string name = "mcdf_rgm");
        super.new(name,UVM_NO_COVERAGE);
    endfunction
    
    virtual function build();
        chnl0_ctrl_reg = ctrl_reg::type_id::create("chnl0_ctrl_reg");
        chnl0_ctrl_reg.configure(this);
        chnl0_ctrl_reg.build();
        chnl1_ctrl_reg = ctrl_reg::type_id::create("chnl1_ctrl_reg");
        chnl1_ctrl_reg.configure(this);
        chnl1_ctrl_reg.build();
        chnl2_ctrl_reg = ctrl_reg::type_id::create("chnl2_ctrl_reg");
        chnl2_ctrl_reg.configure(this);
        chnl2_ctrl_reg.build();
        chnl0_stat_reg = stat_reg::type_id::create("chnl0_stat_reg");
        chnl0_stat_reg.configure(this);
        chnl0_stat_reg.build();
        chnl1_stat_reg = stat_reg::type_id::create("chnl1_stat_reg");
        chnl1_stat_reg.configure(this);
        chnl1_stat_reg.build();
        chnl2_stat_reg = stat_reg::type_id::create("chnl2_stat_reg");
        chnl2_stat_reg.configure(this);
        chnl2_stat_reg.build();

        map = create_map("map",'h0,4,UVM_LITTLE_ENDIAN);
        map.add_reg(chnl0_ctrl_reg,32'h0000_0000,"RW");
        map.add_reg(chnl1_ctrl_reg,32'h0000_0004,"RW");
        map.add_reg(chnl2_ctrl_reg,32'h0000_0008,"RW");
        map.add_reg(chnl0_stat_reg,32'h0000_0010,"RO");
        map.add_reg(chnl1_stat_reg,32'h0000_0014,"RO");
        map.add_reg(chnl2_stat_reg,32'h0000_0018,"RO");
        
        lock_model();
    endfunction
endclass
//-----------------------------adapter---------------------------//
class reg2mcdf_adapter extends uvm_reg_adapter;
	`uvm_object_utils(reg2mcdf_adapter)
	function new(string name = "reg2mcdf_adapter");
		super.new(name);
		provides_responses = 1;
	endfunction
	
	function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
		mcdf_bus_trans t = mcdf_bus_trans::type_id::create("t");
		t.cmd = (rw.kind == UVM_WRITE) ? `WRITE : `READ;
		t.addr = rw.addr;
		t.wdata = rw.data;
		return t;
	endfunction
	
	function void bus2reg(uvm_sequence_item bus_item,ref uvm_reg_bus_op rw);
		mcdf_bus_trans t;
		if(!$cast(t,bus_item)) begin
			`uvm_fatal("NOT_MCDF_BUS_TYPE","provide bus_item is not of the correct type")
		end
		rw.kind = (t.cmd == `WRITE)? UVM_WRITE : UVM_READ;
		rw.addr = t.addr;
		rw.data = (t.cmd == `WRITE)? t.wdata:t.rdata;
		rw.status = UVM_IS_OK;
	endfunction
endclass

//------------adapter jic---------------------------//
class mcdf_bus_env extends uvm_env;
	mcdf_bus_agent agent;
	mcdf_rgm rgm;
	reg2mcdf_adapter reg2mcdf;
	`uvm_component_utils(mcdf_bus_env)
	
	function new(string name = "mcdf_bus_env",uvm_component parent);
		super.new(name,parent);
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		agent = mcdf_bus_agent::type_id::create("agent",this);
		if(!uvm_config_db#(mcdf_rgm)::get(this,"","rgm",rgm)) begin
			`uvm_info("GETRGM","no top down RGM handle is assigned",UVM_LOW)
			rgm = mcdf_rgm::type_id::create("rgm",this);
			`uvm_info("NEWRGM","CREATE rgm instance locally",UVM_LOW)
		end
		rgm.build();
		rgm.map.set_auto_predict();
		reg2mcdf = reg2mcdf_adapter::type_id::create("reg2mcdf",this);
	endfunction
	
	function void connect_phase(uvm_phase phase);
		rgm.map.set_sequencer(agent.sequencer,reg2mcdf); 
	endfunction
endclass

class test1 extends uvm_test;
	mcdf_bus_env env;
	mcdf_rgm rgm;
	`uvm_component_utils(test1)
	
	function void build_phase(uvm_phase);
		super.build_phase(phase);
		env = mcdf_bus_env::type_id::create("env",this);
		rgm = mcdf_rgm::type_id::create("rgm",this);
		uvm_config_db#(mcdf_rgm)::set(this,"env*","rgm",rgm);
	endfunction
endclass

//-----------------frontdoor-------------------//
class mcdf_example_seq extends uvm_reg_sequence;
	mcdf_rgm rgm;
	`uvm_object_utils(mcdf_example_seq)
	`uvm_declare_p_sequencer(mcdf_bus_sequencer)
	
	task body();
		uvm_status_e status;
		uvm_reg_data_t data;
		if(!uvm_config_db#(mcdf_rgm)::get(null,get_full_name(),"rgm",rgm)) begin 
			$uvm_error("GETRGM","no top down RGM handle is assigned")
		end
		
		rgm.chnl0_ctrl_reg.read(status,data,UVM_FRONTDOOR,.parent(this));
		rgm.chnl0_ctrl_reg.write(status,'h11,UVM_FRONTDOOR,.parent(this));
		rgm.chnl0_ctrl_reg.read(status,data,UVM_FRONTDOOR,.parent(this));
		
		read_reg(chnl0_ctrl_reg,status,data,UVM_FRONTDOOR);
		write_reg(chnl0_ctrl_reg,status,'h22,UVM_FRONTDOOR);
		read_reg(chnl0_ctrl_reg,status,data,UVM_FRONTDOOR);
	endtask
endclass

//---------------------backdoor--------------------//
class mcdf_rgm extends uvm_reg_block;
	virtual function build();
		add_hdl_path("reg_backdoor_access.dut");
		chnl0_ctrl_reg.add_hdl_path_slice($sformatf("regs[%d]",`SLV0_RW_REG),0,32);
		chnl1_ctrl_reg.add_hdl_path_slice($sformatf("regs[%d]",`SLV1_RW_REG),0,32);
		chnl2_ctrl_reg.add_hdl_path_slice($sformatf("regs[%d]",`SLV2_RW_REG),0,32);
	endfunction
endclass

//---------------predictor--------------------//
class mcdf_bus_env extends uvm_env;
    mcdf_bus_agent agent;
    mcdf_rgm rgm;
    reg2mcdf_adapter reg2mcdf;
    uvm_reg_predictor #(mcdf_bus_trans) mcdf2reg_predictor;
    `uvm_component_utils(mcdf_bus_env)
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = mcdf_bus_agent::type_id::create("agent",this);
        if(!uvm_config_db#(mcdf_rgm)::create(this,"","rgm",rgm)) begin
            `uvm_info("GETRGM","no top-down RGM handle is assigned",UVM_LOW)
            rgm = mcdf_rgm::type_id::create("rgm",this);
            `uvm_info("NEWRGM","created rgm instance locally",UVM_LOW)
        end
        rgm.build();
        reg2mcdf = reg2mcdf_adapter::type_id::create("reg2mcdf",this);
        mcdf2reg_predictor = uvm_reg_predictor #(mcdf_bus_trans)::type_id::create("mcdf2reg_predictor",this);
        mcdf2reg_predictor.map = reg2mcdf.map;
        mcdf2reg_predictor.adapter = reg2mcdf;
    endfunction
    
    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        rgm.map.set_sequencer(agent.sequencer,reg2mcdf);
        agent.monitor.ap.connect(mcdf2reg_predictor.bus_in);
    endfunction
endclass