module systolic_array #(
parameter row= 4, col = 4,// 4*4 array with 8-bit inputs
w = 8,// Bit-width of input elements (A and B)
 a = 32 // bit-width of accumulated individual results
) 
(input wire clk,
input wire rst,
input  wire [col*w-1:0] ain_flat,
    input  wire [row*w-1:0] bin_flat, //since verilog does not allow matrices of wires as inputs to module
	 //we use a single flat array of wires to represent a matrix as we were taught in class
output wire [row*col*(a)-1:0] out_flat
);

	  wire [w-1:0]   ain  [col-1:0];
    wire [w-1:0]   bin  [row-1:0];
    wire [a-1:0] out  [row-1:0][col-1:0];
    wire [w-1:0]   aout [row-1:0][col-1:0];
    wire [w-1:0]   bout [row-1:0][col-1:0];

//   - ain flows vertically (top to bottom) across rows
//   - bin flows horizontally (left to right) across columns
    genvar i, k; // i denote ith row and k denotes k th column
    generate 
        for (k = 0; k < col; k = k + 1) begin : unpack_a
            assign ain[k] = ain_flat[k*w +: w];
        end
        for (i = 0; i < row; i = i + 1) begin : unpack_b
            assign bin[i] = bin_flat[i*w +: w];
        end
	endgenerate
generate
        for (i = 0; i < row; i = i + 1) begin : row_gen
            for (k = 0; k < col; k = k + 1) begin : col_gen

                // Pack each PE's accumulated output into the flat output bus (row-major)
                assign out_flat[(i*col + k)*a +: a] = out[i][k];

                if (i == 0) begin
                    // Top row: receives ain  from external top-edge inputs
                    if (k == 0) begin
                        // top-left corner PE: receives both ain and bin from external inputs
                        Processing_element #(.W(w), .A(a)) pe_00 (
                            .clk  (clk),
                            .rst  (rst),
                            .ain  (ain[0]),
                            .bin  (bin[0]),
                            .aout (aout[0][0]),
                            .bout (bout[0][0]),
                            .cout (out[i][k])
                        );
                    end else begin
                        Processing_element #(.W(w), .A(a)) pe_0k (
                            .clk  (clk),
                            .rst  (rst),
                            .ain  (ain[k]),
                            .bin  (bout[i][k-1]),
                            .aout (aout[0][k]),
                            .bout (bout[0][k]),
                            .cout (out[i][k])
                        );
                    end
                end else begin
                    if (k == 0) begin
                        // leftmost column: ain from top neighbor, bin from external left-edge input
                        Processing_element #(.W(w), .A(a)) pei0 (
                            .clk  (clk),
                            .rst  (rst),
                            .ain  (aout[i-1][0]),
                            .bin  (bin[i]),
                            .aout (aout[i][k]),
                            .bout (bout[i][k]),
                            .cout (out[i][k])
                        );
                    end else begin
                        // interior PEs receive ain from top neighbor, bin from left neighbor
                        Processing_element #(.W(w), .A(a)) peik (
                            .clk  (clk),
                            .rst  (rst),
                            .ain  (aout[i-1][k]),
                            .bin  (bout[i][k-1]),
                            .aout (aout[i][k]),
                            .bout (bout[i][k]),
                            .cout (out[i][k])
                        );
                    end
                end

            end
        end
    endgenerate

endmodule 
