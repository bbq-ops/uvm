module slave_fifo(
    input               clk_i,
    input               rstn ,
    input      [31:0]   chx_data_i,
    input               chx_val_i,
    input               a2sx_ack,
    
    
    output     [5:0]    chx_margin_o,
    output reg          chx_ready_o,
    output reg [31:0]   chx_data_o,
    output reg          chx_val_o,
    output reg          chx_req_o
);

    reg [5:0] wr_cnt;
    reg [5:0] rd_cnt;
    reg [31:0] mem [31:0];
    wire [5:0] data_cnt;
    
    wire full_s;
    wire empty_s;
    wire rd_en;
    
    assign full_s = {~wr_cnt[5],wr_cnt[4:0]} == rd_cnt;  //写计数器比读计数器多32位，代表已写满
    assign empty_s = wr_cnt == rd_cnt;
    assign rd_en = a2sx_ack;
    assign data_cnt = (6'd32 - (wr_cnt - rd_cnt));
    assign chx_margin_o = data_cnt;
    
    
    
    always @(*)
        if(!full_s)
            chx_ready_o = 1'b1;
        else
            chx_ready_o = 1'b0;
        
    always @(*)
        if(!rstn)
            chx_req_o = 1'b0;
        else if(!empty_s)
            chx_req_o = 1'b1;
        else
            chx_req_o = 1'b0;
    
    always @(posedge clk_i or negedge rstn)
        if(!rstn)
            wr_cnt <= 6'b0;
        else if(chx_val_i && chx_ready_o)
            wr_cnt <= wr_cnt + 1'b1;
            
    always @(posedge clk_i or negedge rstn)
        if(!rstn)
            rd_cnt <= 6'b0;
        else if(rd_en && !empty_s)
            rd_cnt <= rd_cnt + 1'b1;
            
    always @(posedge clk_i or negedge rstn)
        if(!rstn)
            chx_val_o <= 1'b0;
        else if(rd_en && !empty_s)
            chx_val_o <= 1'b1;
        else
            chx_val_o <= 1'b0;
            
    always @(posedge clk_i)
        if(rstn && chx_val_i && chx_ready_o)
            mem[wr_cnt[4:0]] <= chx_data_i;
            
    always @(posedge clk_i)
        if(rstn && rd_en && !empty_s)
        chx_data_o <= mem[rd_cnt[4:0]];

endmodule