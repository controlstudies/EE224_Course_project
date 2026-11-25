module Processing_element #(
    parameter W = 8 // largest number allowed 2^w-1
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
		if(rst == 1 ) begin //initialisation
				aout <= {W{1'b0}};
            bout <= {W{1'b0}};
            cout <= {(2*W){1'b0}};
				end
		else begin 
				aout <= ain; // aout(t) = ain(t-1)
				bout <= bin; // bout(t) = bin(t-1)
				cout <= cout+ain*bin; // cout = ain(t-1)*bin(t-1) + cout(t-1)
 		end
	end

endmodule 