
package uvm_message_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    
    class config_obj extends uvm_object;
        `uvm_object_utils(config_obj)
        function new(string name = "config_obj");
            super.new(name);
            `uvm_info("CREATE",$sformatf("config_obj type [%s] created",name),UVM_LOW)
        endfunction
    endclass
    
    class comp2 extends uvm_component;
        `uvm_component_utils(comp2)
        function new(string name = "comp2", uvm_component parent = null);
            super.new(name, parent);
            `uvm_info("CREATE", $sformatf("unit type [%s] created", name), UVM_LOW)
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            `uvm_info("BUILD", "comp2 build phase entered", UVM_LOW)
            `uvm_info("BUILD", "comp2 build phase exited", UVM_LOW)
        endfunction
        task run_phase(uvm_phase phase);
            super.run_phase(phase);
            `uvm_info("RUN", "comp2 run phase entered", UVM_LOW)
            `uvm_info("RUN", "comp2 run phase exited", UVM_LOW)
        endtask
    endclass    

    class comp1 extends uvm_component;
        `uvm_component_utils(comp1)
        function new(string name = "comp1", uvm_component parent = null);
            super.new(name, parent);
            `uvm_info("CREATE", $sformatf("unit type [%s] created", name), UVM_LOW)
        endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            `uvm_info("BUILD", "comp1 build phase entered", UVM_LOW)
            `uvm_info("BUILD", "comp1 build phase exited", UVM_LOW)
        endfunction
        task run_phase(uvm_phase phase);
            super.run_phase(phase);
            `uvm_info("RUN", "comp1 run phase entered", UVM_LOW)
            `uvm_info("RUN", "comp1 run phase exited", UVM_LOW)
        endtask
    endclass

    
endpackage