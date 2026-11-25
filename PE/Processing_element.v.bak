module processing_element #(
    parameter W = 8
)(
    input  wire clk,
    input  wire rst,
    input  wire [W-1:0]ain,
    input  wire [W-1:0]bin,
    output reg  [W-1:0]aout,      
    output reg  [W-1:0]bout,      
    output reg  [2*W-1:0]cout        
);
	
	always@(posedge (clk),posedge(rst))begin
		if(rst == 1 ) begin aout <= {W{1'b0}};
            bout <= {W{1'b0}};
            cout <= {(2*W){1'b0}};end
		else begin 
				aout <= ain;
				bout <= bin;
				cout <= cout+ain*bin;
		end
	end

endmodule 