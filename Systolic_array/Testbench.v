`timescale 1ns / 1ps

module Testbench;

    parameter ROW = 8;
    parameter COL = 8;
    parameter W   = 8;

    reg                          clk;
    reg                          rst;
    reg  [COL*W-1:0]             ain_flat;
    reg  [ROW*W-1:0]             bin_flat;
    wire [ROW*COL*(2*W)-1:0]     out_flat;

    // Internal 2D arrays in testbench (allowed inside Verilog-2001 modules)
    reg  [W-1:0]   A_mat    [0:ROW-1][0:COL-1]; // Enters top edge (ain)
    reg  [W-1:0]   B_mat    [0:ROW-1][0:COL-1]; // Enters left edge (bin)
    reg  [2*W-1:0] C_golden [0:ROW-1][0:COL-1];
    wire [2*W-1:0] out_2d   [0:ROW-1][0:COL-1];

    // Unpack out_flat back into a 2D wire array for easy viewing & checking
    genvar gi, gk;
    generate
        for (gi = 0; gi < ROW; gi = gi + 1) begin : unpack_out_r
            for (gk = 0; gk < COL; gk = gk + 1) begin : unpack_out_c
                assign out_2d[gi][gk] = out_flat[(gi*COL + gk)*(2*W) +: (2*W)];
            end
        end
    endgenerate

    // Instantiate Unit Under Test (UUT)
    systolic_array #(
        .row(ROW),
        .col(COL),
        .w(W)
    ) uut (
        .clk(clk),
        .rst(rst),
        .ain_flat(ain_flat),
        .bin_flat(bin_flat),
        .out_flat(out_flat)
    );

    // 100 MHz Clock (10 ns period)
    always #5 clk = ~clk;

    integer r, c, m, t, errors;

    initial begin
        clk = 0;
        rst = 1;
        ain_flat = 0;
        bin_flat = 0;
        errors = 0;

        // 1. Initialize test matrices
        for (r = 0; r < ROW; r = r + 1) begin
            for (c = 0; c < COL; c = c + 1) begin
                B_mat[r][c]    = r + 1; // Row matrix values (1 to 8)
                A_mat[r][c]    = c + 1; // Col matrix values (1 to 8)
                C_golden[r][c] = 0;
            end
        end

        // 2. Compute expected golden result: C[r][c] = sum_m( B_mat[r][m] * A_mat[m][c] )
        for (r = 0; r < ROW; r = r + 1) begin
            for (c = 0; c < COL; c = c + 1) begin
                for (m = 0; m < ROW; m = m + 1) begin
                    C_golden[r][c] = C_golden[r][c] + (B_mat[r][m] * A_mat[m][c]);
                end
            end
        end

        // Release reset
        #15 rst = 0;

        // 3. Feed diagonally skewed data into flattened buses over (3*N) cycles
        for (t = 0; t < (3 * ROW); t = t + 1) begin
            @(negedge clk);

            // Pack skewed bin (left edge): row r is delayed by r cycles
            for (r = 0; r < ROW; r = r + 1) begin
                if (t >= r && (t - r) < COL)
                    bin_flat[r*W +: W] = B_mat[r][t - r];
                else
                    bin_flat[r*W +: W] = {W{1'b0}};
            end

            // Pack skewed ain (top edge): col c is delayed by c cycles
            for (c = 0; c < COL; c = c + 1) begin
                if (t >= c && (t - c) < ROW)
                    ain_flat[c*W +: W] = A_mat[t - c][c];
                else
                    ain_flat[c*W +: W] = {W{1'b0}};
            end
        end

        // Clear inputs after streaming finishes
        @(negedge clk);
        ain_flat = 0;
        bin_flat = 0;

        #20;

        // 4. Verify hardware output against golden reference
        $display("\n--- Systolic Array 8x8 Output Matrix ---");
        for (r = 0; r < ROW; r = r + 1) begin
            for (c = 0; c < COL; c = c + 1) begin
                $write("%4d ", out_2d[r][c]);
                if (out_2d[r][c] !== C_golden[r][c]) begin
                    errors = errors + 1;
                end
            end
            $write("\n");
        end

        if (errors == 0)
            $display("\nSUCCESS: All 64 PE outputs match the golden matrix multiplication!");
        else
            $display("\nERROR: Found %0d mismatches.", errors);

        $finish;
    end

endmodule