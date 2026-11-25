`timescale 1ns / 1ps

module Testbench;

    parameter ROW = 4;
    parameter COL = 4;
    parameter W = 8;
    parameter A = 32;
    parameter K = 4;

    reg clk;
    reg rst;
    reg [COL*W-1:0] ain_flat;
    reg [ROW*W-1:0] bin_flat;
    wire [ROW*COL*A-1:0] out_flat;

    // matrices to be multiplied
    reg [W-1:0] A_mat [0:K-1][0:COL-1]; // top inputs
    reg [W-1:0] B_mat [0:ROW-1][0:K-1]; // left inputs
    reg [A-1:0] C_golden [0:ROW-1][0:COL-1];
    wire [A-1:0] out_2d [0:ROW-1][0:COL-1];

    // convert out_flat to a 2D matrix for the waveform
    genvar gi, gk;
    generate
        for (gi = 0; gi < ROW; gi = gi + 1) begin : unpack_out_r
            for (gk = 0; gk < COL; gk = gk + 1) begin : unpack_out_c
                assign out_2d[gi][gk] = out_flat[(gi*COL + gk)*A +: A];
            end
        end
    endgenerate

    systolic_array #(
        .row(ROW),
        .col(COL),
        .w(W),
        .a(A)
    ) uut (
        .clk(clk),
        .rst(rst),
        .ain_flat(ain_flat),
        .bin_flat(bin_flat),
        .out_flat(out_flat)
    );

    // 10 ns clock period
    always #5 clk = ~clk;

    initial begin : test
        integer r, c, m, t, errors;
        clk = 0;
        rst = 1;
        ain_flat = 0;
        bin_flat = 0;
        errors = 0;

        // initialise matrices
        for (r = 0; r < ROW; r = r + 1) begin
            for (c = 0; c < COL; c = c + 1) begin
                C_golden[r][c] = 0;
            end
        end

        for (r = 0; r < ROW; r = r + 1)
            for (m = 0; m < K; m = m + 1)
                B_mat[r][m] = r + 1;

        for (m = 0; m < K; m = m + 1)
            for (c = 0; c < COL; c = c + 1)
                A_mat[m][c] = c + 1;

        // calculate B_mat * A_mat for comparison
        for (r = 0; r < ROW; r = r + 1) begin
            for (c = 0; c < COL; c = c + 1) begin
                for (m = 0; m < K; m = m + 1) begin
                    C_golden[r][c] = C_golden[r][c] + (B_mat[r][m] * A_mat[m][c]);
                end
            end
        end

        #12 rst = 0;

        // send inputs for K+ROW+COL-2 cycles
        for (t = 0; t < (K + ROW + COL - 2); t = t + 1) begin
            @(negedge clk);

            // delay row r by r cycles
            for (r = 0; r < ROW; r = r + 1) begin
                if (t >= r && (t - r) < K)
                    bin_flat[r*W +: W] = B_mat[r][t - r];
                else
                    bin_flat[r*W +: W] = {W{1'b0}};
            end

            // delay column c by c cycles
            for (c = 0; c < COL; c = c + 1) begin
                if (t >= c && (t - c) < K)
                    ain_flat[c*W +: W] = A_mat[t - c][c];
                else
                    ain_flat[c*W +: W] = {W{1'b0}};
            end
        end

        @(negedge clk);
        ain_flat = 0;
        bin_flat = 0;

        #20;

        // print and compare the result
        $display("\nOutput matrix:");
        for (r = 0; r < ROW; r = r + 1) begin
            for (c = 0; c < COL; c = c + 1) begin
                $write("%4d ", out_2d[r][c]);
                if (out_2d[r][c] !== C_golden[r][c]) begin
                    errors = errors + 1;
                end
            end
            $write("\n");
        end

        $display("\nMatrix mismatches: %0d/%0d", errors, ROW*COL);

        $finish;
    end

endmodule
