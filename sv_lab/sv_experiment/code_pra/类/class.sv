class cat;
    protected color_t color;
    local bit is_good;
    function set_good(bit s);
        this.is_good = s;
    endfunction
endclass

class black_cat extends cat;
    function new();
        this.color = BLACK;
    endfunction
endclass

class white_cat extends cat;
    function new();
        this.color = WHITE;
    endfunction
endclass

black_cat bk;
white_cat wt;
initial begin
    bk = new();
    wt = new();
    bk.set_good(1);
    wk.set_good(1);
end

//-------------------------//
class Transaction;
    rand bit [31:0] src,dst,data[8];
    bit [31:0] crc;
    virtual function void calc_crc();
        crc = src ^ dst ^ data.xor;
    endfunction
    virtual function void display(input string prefix = "");
        $display("%sTr: src = %h,dst = %h,crc = %h",prefix,src,dst,crc);
    endfunction
endclass

class BadTr extends Transaction;
    rand bit bad_crc;
    virtual function void calc_crc;
        super.calc_crc();
        if(bad_crc) crc = ~crc;
    endfunction
    virtual function void display(input string prefix = "");
        $write("%sBadTr: bad_crc = %b",prefix,bad_crc);
        super.display();
endclass:BadTr

//------------------------//
interface arb_if(input bit clk);
    logic [1:0] grant,request;
    logic rst;
endinterface

module arb(arb_if arbif);
    always @(posedge arbif.clk or posedge arbif.rst) begin
        if(arbif.rst)
            arbif.grant <= 2'b00;
        else
            arbif.grant <= next_grant;
    end
endmodule:arb

module test(arb_if arbif);
    initial begin
        @(posedge arbif.clk) arbif.request <= 2'b01;
        $display("@%0t:Drove req = 01",$time);
        repeat(2) @(posedge arbif.clk);
        if(arbif.grant != 2'b01) $display("@%0t: a1: grant != 2'b01",$time);
        $finish;
    end
endmodule:test

module top;
    bit clk;
    always #5 clk = ~clk;
    arb_if arbif(clk);
    arb a1(arbif);
    test t1(arbif);
endmodule:top























