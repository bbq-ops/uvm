`timescale 1ns/1ps

module chnl_initiator(
    input                 clk_i,
    input                 rstn,
    input [5:0]           chnl_margin,
    input                 chnl_ready,
    output logic [31:0]   chnl_data,
    output logic          chnl_valid
);

string name;

function void set_name(string s);
    name = s;
endmodule

function void chnl_write(input logic [31:0] data);
    @(posedge clk);
    chnl_valid = 1'b1;
    chnl_data = data;
    @(negedge clk);
    wait(chnl_ready == 1);
    $display("%t chnl_initial [%s] send data %x ",$time,name,data);
    chnl_idle();
endfunction

function void chnl_idle();
    @(posedge clk);
    chnl_valid <= 1'b0;
    chnl_data <= 0;
endfunction  

endmodule

module tb1;
reg          clk;
reg          rstn;
reg  [31:0]  ch0_data;
reg          ch0_valid;
wire         ch0_ready;
wire [ 5:0]  ch0_margin;
reg  [31:0]  ch1_data;
reg          ch1_valid;
wire         ch1_ready;
wire [ 5:0]  ch1_margin;
reg  [31:0]  ch2_data;
reg          ch2_valid;
wire         ch2_ready;
wire [ 5:0]  ch2_margin;
wire [31:0]  mcdt_data;
wire         mcdt_val;
wire [ 1:0]  mcdt_id;

mcdt dut(
   .clk_i(clk)
  ,.rstn_i(rstn)
  ,.ch0_data_i(ch0_data)
  ,.ch0_valid_i(ch0_valid)
  ,.ch0_ready_o(ch0_ready)
  ,.ch0_margin_o(ch0_margin)
  ,.ch1_data_i(ch1_data)
  ,.ch1_valid_i(ch1_valid)
  ,.ch1_ready_o(ch1_ready)
  ,.ch1_margin_o(ch1_margin)
  ,.ch2_data_i(ch2_data)
  ,.ch2_valid_i(ch2_valid)
  ,.ch2_ready_o(ch2_ready)
  ,.ch2_margin_o(ch2_margin)
  ,.mcdt_data_o(mcdt_data)
  ,.mcdt_val_o(mcdt_val)
  ,.mcdt_id_o(mcdt_id)
);

task gen_clk();
  clk <= 0;
  forever begin
    #5 clk <= !clk;
  end
endtask

// clock generation
initial begin 
    gen_clk();
end

task gen_rst();
  #10 rstn <= 0;
  repeat(10) @(posedge clk);
  rstn <= 1;    
endtask
// reset trigger
initial begin 
    gen_rst();
end

//定义动态数组用于存储产生的数据
logic [31:0] chnl0_arry[];
logic [31:0] chnl1_arry[];
logic [31:0] chnl2_arry[];

initial begin
    chnl0_arry = new[100];
    chnl1_arry = new[100];
    chnl2_arry = new[100];
    foreach(chnl0_arry[i])begin
        chnl0_arry[i] = 'h00C0_0000 + i;
        chnl1_arry[i] = 'h00C1_0000 + i;
        chnl2_arry[i] = 'h00C2_0000 + i;
    end
    
end

initial begin
    @(posedge rstn);
    repeat(5) @(posedge clk_i);
    chnl0_init.set_name("chnl0_init");
    chnl1_init.set_name("chnl1_init");
    chnl2_init.set_name("chnl2_init");
    
    foreach(chnl0_arry[i]) chnl0_init.chnl_write(chnl0_arry[i]);
    foreach(chnl1_arry[i]) chnl1_init.chnl_write(chnl0_arry[i]);
    foreach(chnl2_arry[i]) chnl2_init.chnl_write(chnl0_arry[i]);
end

chnl_initiator chnl0_init(
    .clk_i      (clk_i     )    ,
    .rstn       (rstn      )    ,
    .chnl_margin(ch0_margin)    ,
    .chnl_ready (ch0_ready )    ,
    .chnl_data  (ch0_data  )    ,
    .chnl_valid (ch0_valid )
);

chnl_initiator chnl1_init(
    .clk_i      (clk_i     )    ,
    .rstn       (rstn      )    ,
    .chnl_margin(ch1_margin)    ,
    .chnl_ready (ch1_ready )    ,
    .chnl_data  (ch1_data  )    ,
    .chnl_valid (ch1_valid )
);

chnl_initiator chnl2_init(
    .clk_i      (clk_i     )    ,
    .rstn       (rstn      )    ,
    .chnl_margin(ch2_margin)    ,
    .chnl_ready (ch2_ready )    ,
    .chnl_data  (ch2_data  )    ,
    .chnl_valid (ch2_valid )
);

endmodule
