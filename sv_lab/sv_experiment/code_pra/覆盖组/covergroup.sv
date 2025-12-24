//在类里面定义覆盖组
class Transactor;
    Transaction tr;
    mailbox mbx_in;
    covergroup CovPort;
        coverpoint tr.port;
    endgroup
    
    function new(mailbox mbx_in);
        CovPort = new();
        this.mbx_in = mbx_in;
    endfunction
    
    task main;
        forever begin
            tr = mbx_in.get();
            ifc.cb.port <= tr.port;
            ifc.cb.data <= tr.data;
            CovPort.sample();
        end
    endtask
endclass

//===================================//
event trans_ready;
covergroup CovPort @(trans_ready);
    coverpoint ifc_cb.port;
endgroup

//===================================//
covergroup CovPort;
    options.auto.bin.max = 8;
    coverpoint tr.port {
        options.auto.bin.max = 2;
    }
endgroup

//===================================//
covergroup CovKind;
    coverpoint tr.kind {
        bins zero = {0};
        bins lo = {[1:3],5};
        bins hi[] = {[8:$]};
        bins misc = default;
    }
endgroup

//===================================//
covergroup CoverPort;
    coverpoint port iff(!bus_if_reset);
endgroup

initial begin
    CoverPort ck = new();
    #1ns;
    ck.stop();
    bus_if.reset = 1;
    #100ns bus_if.reset = 0;
    ck.start();
    ...
end

//===================================//

covergroup CoverPort;
    coverpoint port{
        bins t1 = (0 => 1),(0 => 2),(0 => 3);
    }
endgroup

//===================================//
bit [2:0] port;
covergroup CoverPort;
    coverpoint port{
        wildcard bins even = {3'b??0};
        wildcard bins odd = {3'??1};
    }
endgroup

//===================================//
bit [2:0] low_ports_0_5;
covergroup CoverPort;
    coverpoint low_ports_0_5{
        illegal_bins hi = {[6:7]};
    }
endgroup

//===================================//
class Trasaction;
    rand bit [3:0] kind;
    rand bit [2:0] port;
endclass

Transaction tr;

covergroup CovPort;
    kind: coverpoint tr.kind;
    port: coverpoint tr.port;
    cross kind,port;
endgroup

//===================================//
covergroup Covport;
    port: coverpoint tr.port{
        bins port[] = {[0:$]};
    }
    kind: coverpoint tr.kind{
        bins zero = {0};
        bins lo = {[1:3]};
        bins hi[] = {[8:$]};
        bins misc = default;
    }

cross kind,port{
    ignore_bins hi = binsof(port) intersect{7};
    ignore_bins md = binsof(port) intersect{0} && binsof(kind) intersect{[9:11]};
    ignore_bins lo = binsof(kin.lo);
}

endgroup

//===================================//
class Transaction;
    rand bit a,b;
endclass

covergroup CrossBinNaems;
    a:coverpoint tr.a{
        bins a0 = {0};
        bins a1 = {1};
        option.weight = 0;
    }
    b: coverpoint tr.b{
        bins b0 = {0};
        bins b1 = {1};
        option.weight = 0;
    }
    ab: cross a,b{
        bins a0b0 = binsof(a.a0) && binsof(b.b0);
        bins a1b0 = binsof(a.a1) && binsof(b.b0);
        bins b1 = binsof(b.b1);
    }
endgroup


    