module systolic_array #(parameter row= 8, col = 8,w = 8) // 8*8 matrix with each element having 8 bits
(input wire clk,
input wire rst,
input  wire [col*w-1:0] ain_flat,
    input  wire [row*w-1:0] bin_flat,
output wire [row*col*(2*w)-1:0] out_flat
);

		wire [w-1:0]   ain  [col-1:0];
    wire [w-1:0]   bin  [row-1:0];
    wire [2*w-1:0] out  [row-1:0][col-1:0];
    wire [w-1:0]   aout [row-1:0][col-1:0];
    wire [w-1:0]   bout [row-1:0][col-1:0];

    genvar i, k;
    generate 
        for (k = 0; k < col; k = k + 1) begin : unpack_a
            assign ain[k] = ain_flat[k*w +: w];
        end
        for (i = 0; i < row; i = i + 1) begin : unpack_b
            assign bin[i] = bin_flat[i*w +: w];
        end
	endgenerate
		generate 
			for(i=0;i<row;i=i+1)begin : row_gen
				for(k=0;k<col;k=k+1)begin : col_gen
				assign out_flat[(i*col + k)*(2*w) +: (2*w)] = out[i][k];
						if(i == 0)begin
						
								if(k==0) processing_element #(.W(w)) pe_00 (.clk(clk),.rst(rst),.ain(ain[0]),.bin(bin[0]),.aout(aout[0][0]),.bout(bout[0][0]),.cout(out[i][k]));
						
								else processing_element #(.W(w)) pe_0k (.clk(clk),.rst(rst),.ain(ain[k]),.bin(bout[i][k-1]),.aout(aout[0][k]),.bout(bout[0][k]),.cout(out[i][k]));
						end
						else begin 
						
							if(k==0) processing_element #(.W(w)) pei0 (.clk(clk),.rst(rst),.ain(aout[i-1][0]),.bin(bin[i]),.aout(aout[i][k]),.bout(bout[i][k]),.cout(out[i][k]));
							
							else processing_element #(.W(w)) peik (.clk(clk),.rst(rst),.ain(aout[i-1][k]),.bin(bout[i][k-1]),.aout(aout[i][k]),.bout(bout[i][k]),.cout(out[i][k]));
						end
					end
			end
		endgenerate

endmodule 