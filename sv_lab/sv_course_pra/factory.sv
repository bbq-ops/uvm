class comp1 extends uvm_component;
    `uvm_component_utils(comp1)
    function new(string name = "comp1",uvm_component parent = null);
        super.new(name,parent);
        $display($sformatf("%s is created",name));
    endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
    endfunction
endclass

class obj1 extends uvm_object;
    `uvm_object_utils(obj1)
    function new(string name = "obj1");
        super.new(name);
        $display($sformatf("%s is created",name));
    endfunction
endclass

comp1 c1,c2;
obj1 o1,o2;

initial begin 
    c1 = new("c1");
    o1 = new("o1");
    c2 = comp1::type_id::create("c2",null);
    o2 = obj1::type_id::create("o2");

end

//-----------------------------//
module factory_override;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    class comp1 extends uvm_component;
        `uvm_component_utils(comp1)
        function new(string name = "comp1",uvm_component parent = null);
            super.new(name,parent);
            $display($sformatf("comp1:: %s is created",name));
        endfunction
        
        virtual function void hello(string name);
            $display($sformatf("comp1:: %s said hello!",name));
        endfunction
        
    class comp2 extends comp1;
        `uvm_component_utils(comp2)
        function new(string name = "comp2",uvm_component parent = null);
            super.new(name,parent);
            $display($sformatf("comp2:: %s is created",name));
        endfunction
        
        function void hello(string name);
            $display($sformatf("comp2:: %s said hello",name));
        endfunction
    endclass
    
    comp1 c1,c2;
    initial begin
        comp1::type_id::set_type_override(comp2::get_type());
        c1 = new("c1");
        c2 = comp1::type_id::create("c2",null);
        c1.hello(c1);
        c2.hello(c2);
    end
endmodule

//核心基类 uvm_object
class box extends uvm_object;
    int volume = 120;
    color_t color = WHITE;
    string name = "box";
    `uvm_object_utils_begin(box)
        `uvm_field_int(volume,UVM_ALL_ON)
        `uvm_field_enum(color_t,color,UVM_ALL_ON)
        `uvm_field_string(name,UVM_ALL_ON)
    `uvm_object_utils_end
    
