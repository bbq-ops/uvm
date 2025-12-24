`timescale 1ns/1ns

module tb;
reg                 clk_i       ;
reg                 rstn_i      ;
reg  [31:0]         ch0_data_i  ;
reg                 ch0_valid_i ;
wire                ch0_ready_o ;
wire [5:0]          ch0_margin_o;
reg  [31:0]         ch1_data_i  ;
reg                 ch1_valid_i ;
wire                ch1_ready_o ;
wire [5:0]          ch1_margin_o;
reg  [31:0]         ch2_data_i  ;
reg                 ch2_valid_i ;
wire                ch2_ready_o ;
wire [5:0]          ch2_margin_o;
wire [31:0]         mcdt_data_o ;
wire                mcdt_val_o  ;
wire [1:0]          mcdt_id_o   ;

mcdt dut(
.clk_i        (clk_i       )  ,
.rstn_i       (rstn_i      )  ,
.ch0_data_i   (ch0_data_i  )  ,
.ch0_valid_i  (ch0_valid_i )  ,
.ch0_ready_o  (ch0_ready_o )  ,
.ch0_margin_o (ch0_margin_o)  ,
.ch1_data_i   (ch1_data_i  )  ,
.ch1_valid_i  (ch1_valid_i )  ,
.ch1_ready_o  (ch1_ready_o )  ,
.ch1_margin_o (ch1_margin_o)  ,  
.ch2_data_i   (ch2_data_i  )  ,
.ch2_valid_i  (ch2_valid_i )  ,
.ch2_ready_o  (ch2_ready_o )  ,
.ch2_margin_o (ch2_margin_o)  ,
.mcdt_data_o  (mcdt_data_o )  ,
.mcdt_val_o   (mcdt_val_o  )  ,
.mcdt_id_o    (mcdt_id_o   )
);

initial begin
    clk_i <= 0;
    forever begin
    #5 clk_i <= !clk_i;
    end
end

initial begin
    #10 rstn_i <= 0;
    repeat(10) @(posedge clk_i)
        rstn_i <= 1;
end

task chnl_write(input reg [1:0] id,input reg [31:0] data);
    case(id)
        0: begin
           @(posedge clk_i);
           ch0_valid_i <= 1'b1;
           ch0_data_i  <= data;
           @(posedge clk_i);
           ch0_valid_i <= 1'b0;
           ch0_data_i  <= 0;
        end
        1: begin
           @(posedge clk_i);
           ch1_valid_i <= 1'b1;
           ch1_data_i  <= data;
           @(posedge clk_i);
           ch0_valid_i <= 1'b0;
           ch0_data_i  <= 0;           
        end
        2: begin
           @(posedge clk_i)
           ch2_valid_i <= 1'b1;
           ch2_data_i  <= data;
           @(posedge clk_i);
           ch0_valid_i <= 1'b0;
           ch0_data_i  <= 0;
        end
        default: $error("channel id %0d is invalid",id);
    endcase
endtask

initial begin
    @(posedge rstn_i);
    repeat(5) @(posedge clk_i);
    chnl_write(0,'h00C0_0000);
    chnl_write(0,'h00C0_0001);
    chnl_write(0,'h00C0_0002);
    chnl_write(0,'h00C0_0003);
    chnl_write(0,'h00C0_0004);
    chnl_write(0,'h00C0_0005);
    chnl_write(0,'h00C0_0006);
    chnl_write(0,'h00C0_0007);
    chnl_write(0,'h00C0_0008);
    chnl_write(0,'h00C0_0009);
    
    chnl_write(1,'h00C1_0000);
    chnl_write(1,'h00C1_0001);
    chnl_write(1,'h00C1_0002);
    chnl_write(1,'h00C1_0003);
    chnl_write(1,'h00C1_0004);
    chnl_write(1,'h00C1_0005);
    chnl_write(1,'h00C1_0006);
    chnl_write(1,'h00C1_0007);
    chnl_write(1,'h00C1_0008);
    chnl_write(1,'h00C1_0009);

    chnl_write(2,'h00C2_0000);
    chnl_write(2,'h00C2_0001);
    chnl_write(2,'h00C2_0002);
    chnl_write(2,'h00C2_0003);
    chnl_write(2,'h00C2_0004);
    chnl_write(2,'h00C2_0005);
    chnl_write(2,'h00C2_0006);
    chnl_write(2,'h00C2_0007);
    chnl_write(2,'h00C2_0008);
    chnl_write(2,'h00C2_0009);    
end
endmodule