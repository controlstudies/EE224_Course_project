`timescale 1ns / 1ps

module Processing_element_TB;

    localparam W = 8;
    localparam CLK_PERIOD = 10; // 100 MHz clock

    reg clk;
    reg rst;
    reg [W-1:0] ain;
    reg [W-1:0] bin;
    wire [W-1:0] aout;
    wire [W-1:0] bout;
    wire [2*W-1:0] cout;

    // expected outputs
    reg [W-1:0] exp_aout;
    reg [W-1:0] exp_bout;
    reg [2*W-1:0] exp_cout;
    integer errors = 0;

    Processing_element #(
        .W(W)
    ) dut (
        .clk(clk),
        .rst(rst),
        .ain(ain),
        .bin(bin),
        .aout(aout),
        .bout(bout),
        .cout(cout)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // give inputs at negedge and check after posedge
    task apply_and_check(input [W-1:0] a, input [W-1:0] b);
        begin
            @(negedge clk);
            ain = a;
            bin = b;

            exp_aout = a;
            exp_bout = b;
            exp_cout = exp_cout + (a * b);

            @(posedge clk);
            #1; // wait for outputs to update

            if (aout !== exp_aout || bout !== exp_bout || cout !== exp_cout) begin
                $display("Mismatch: ain=%0d bin=%0d, cout=%0d (expected %0d)",
                         ain, bin, cout, exp_cout);
                errors = errors + 1;
            end
            $display("ain = %3d  bin = %3d  cout = %5d", ain, bin, cout);
        end
    endtask

    initial begin
        rst = 1;
        ain = 0;
        bin = 0;
        exp_aout = 0;
        exp_bout = 0;
        exp_cout = 0;

        // check reset
        #(CLK_PERIOD);
        if (aout !== 0 || bout !== 0 || cout !== 0) begin
            $display("[FAIL] Reset failed! aout=%0d bout=%0d cout=%0d", aout, bout, cout);
            errors = errors + 1;
        end
        @(negedge clk);
        rst = 0;

        // check accumulation
        apply_and_check(8'd3,  8'd4);   // cout = 0 + 12 = 12
        apply_and_check(8'd5,  8'd6);   // cout = 12 + 30 = 42
        apply_and_check(8'd10, 8'd2);   // cout = 42 + 20 = 62

        // cout should not change for zero inputs
        apply_and_check(8'd0,  8'd15);  // cout = 62 + 0 = 62
        apply_and_check(8'd20, 8'd0);   // cout = 62 + 0 = 62

        // reset in between clock edges
        #3;
        rst = 1;
        exp_aout = 0;
        exp_bout = 0;
        exp_cout = 0;
        #1;
        if (aout !== 0 || bout !== 0 || cout !== 0) begin
            $display("[FAIL] Async reset failed! aout=%0d bout=%0d cout=%0d", aout, bout, cout);
            errors = errors + 1;
        end

        // test large values
        @(negedge clk);
        rst = 0;
        apply_and_check(8'd255, 8'd255); // cout = 65025 (max 8x8 product)

        #(CLK_PERIOD);
        $display("\nMismatches: %0d", errors);

        $finish;
    end

endmodule
