module arbiter(
    input           clk_i,
    input           rstn_i,
    
);
    
always @(posedge clk_i or negedge rstn_i)
    if(!rstn_i)
        
endmodule