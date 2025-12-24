class Packet;
    rand bit [31:0] src,dst,data[8];
    rand bit [7:0] kind;
    
    constraint c {src > 10;src < 15;};

endclass

Packet p;
initial begin
    p = new();
    assert(p.randomize()) else
    $fatal(0,"Packet::randomize failed");
    transmit(p);
end

//----------------------------------------//
class date;
    rand bit [2:0] month;
    rand bit [4:0] day;
    rand int year;
    constraint c_date{
        month inside {[1:12]};
        day inside {[1:31]};
        year inside {[2010:2030]};
    };
endclass

//----------------------------------------//
class Stim;
    const bit [31:0] CONGEST_ADDR = 42;
    
    typedef enum{READ,WRITE,CONTROL} stim_e;
    
    randc stim_e kind;  //定义一个枚举的变量
    
    rand bit [31:0] len,src,dst;
    bit congestion_test;

    constraint c_stim{
        len < 1000;
        len > 0;
        //约束块中使用if..else，若多约束条件必须使用{}包围
        if(congestion_test) {
            dst inside {[CONGEST_ADDR - 100 : CONGEST_ADDR + 100]};
            src == CONGEST_ADDR;
            }
        else
        src inside {0,[2:0],[100:107]};
    }; 
endclass

//----------------------------------------//
rand int src,dst;
constraint c_dist{
    src dist {0:=40,[1:3]:=60}
    dst dist {0:/40,[1:3]:/60}
};

//----------------------------------------//
rand int c;
int lo,hi;

constraint c_range{
    c inside {[lo,hi]}
};

rand bit [6:0] b;
rand bit [5:0] e;

constraint c_range{
    b inside {[$:4],[20:$]};
    c inside {[$:4],[20:$]}
};

//----------------------------------------//
class packet;
    rand int length;
    constraint c_short {length inside{[1:32]};}
    constraint c_long {length inside{[1000:1023]};}
    
endclass

Packet p;
initial begin
    p = new();
    p.c_short.constraint_mode(0);
    assert (p.randomize());
    transmit(p);
    p.constraint_mode(0);
    p.c_short.constraint_mode(1);
    assert(p.randomize());
    transmit(p);
end

//----------------------------------------//
class Transaction;
    rand bit [31:0] addr,data;
    constraint c1{
        soft addr inside {[0:100],[1000:2000]};
    }
endclass

Transaction t;
initial begin
    t = new();
    
    assert(t.randomize() with {addr >= 50;addr <= 1500;data < 10;});
    
    driveBus(t);
    
    assert(t.randomize() with {addr == 2000;data > 10;});
    
    driveBus(t);
end

//----------------------------------------//
class Rising;
    byte low;
    rand byte med, hi;
    constraint up{
        low < med; med < hi;
    }
endclass

initial begin
    Rising r;
    r = new();
    r.randomize();
    r.randomize(med);
    r.randomize(low);
end

//----------------------------------------//
class good_sum5;
    rand unit len[];
    constraint c_len{
        foreach(len[i]) len[i] inside {[1:255]};
        len.sum() < 1024;
        len.size() inside {[1:8]};
    }
endclass

//----------------------------------------//
class UniqueSlow;
    rand bit [7:0] ua[64];
    constrait c{
        foreach(ua[i])
            foreach(ua[j])
                if(i != j)
                    ua[i] != ua[j];
    }

//----------------------------------------//
class randc8;
    randc bit [7:0] val;
endclass

class LittleUniqueArray;
    bit [7:0] ua[64];
    function void pre_randomize();
        randc8 rc8;
        rc8 = new();
        foreach(ua[i]) begin
            assert(rc8.randomize());
            ua[i] = rc8.val;
        end     
    endfunction
endclass

//----------------------------------------//
parameter MAX_SIZE = 10;
class RandStuff;
    bit [1:0] value = 1;
endclass

class RandArray;
    rand RandStuff array[];
    constraint c {
        array.size() inside {[1:MAX_SIZE]};
    }
    function new();
        array = new[MAX_SIZE];
        foreach(array[i])
            array[i] = new();
    endfunction
endclass

RandArray ra;
initial begin
    ra = new();
    assert(ra.randomize());
    foreach(ra.array[i])
        $display(ra.array[i].value);
end

//----------------------------------------//
initial begin
    for(int i=0; i<15; i++) begin
        randsequence (stream)
            stream : cfg_read := 1 |
                    io_read := 2 |
                    mem_read := 5;
            cfg_read : {cfg_read_task;} |
                       {cfg_read_task;} cfg_read;
            mem_read : {mem_read_task;} |
                       {mem_read_task;} mem_read;
            io_read : {io_read_task;} | 
                      {io_read_task;} io_read;
        endsequence
    end
end





































