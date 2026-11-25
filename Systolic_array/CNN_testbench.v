`timescale 1ns/1ps
module CNN_Testbench;
    parameter NUM_IMAGES = 100;
    parameter VERIFY_MAC = 1; // check matrix products separately
    localparam W = 8, A = 32;
    localparam W1 = 0, W2 = 45, W3 = 495, W4 = 32495;
    localparam B1 = 0, B2 = 5, B3 = 15, B4 = 143;

    reg clk, rst;
    reg [4*W-1:0] ain_flat, bin_flat;
    wire [4*4*A-1:0] out_flat;
    systolic_array #(.row(4), .col(4), .w(W), .a(A)) uut (
        .clk(clk), .rst(rst), .ain_flat(ain_flat),
        .bin_flat(bin_flat), .out_flat(out_flat)
    );
    always #5 clk = ~clk;

    // data from python (channel index changes fastest)
    reg [7:0] weights [0:33774];
    reg signed [31:0] biases [0:152];
    reg [31:0] divisors [0:2];
    reg [7:0] images [0:NUM_IMAGES*784-1];
    reg [7:0] labels [0:NUM_IMAGES-1];

    // arrays reused for each layer
    reg [7:0] feature [0:3379];
    reg [7:0] patch_matrix [0:6083]; // largest: 676 x 9
    reg signed [63:0] mac_result [0:3379]; // largest: 676 x 5
    reg signed [63:0] logits [0:9];
    integer cycles, tiles, mac_checks, mac_errors;

    // multiply an M x K matrix with a K x N matrix
    // 4 rows and 4 columns at a time
    // ain -> image data, bin -> weights
    task matmul;
        input integer M, K, N, weight_offset;
        integer rb, cb, t, r, c, k;
        reg signed [63:0] expected_mac, raw, activation_sum;
        integer signed_weight, activation;
        begin
            for (rb = 0; rb < M; rb = rb+4) begin
                for (cb = 0; cb < N; cb = cb+4) begin
                    // reset before the next 4x4 block
                    @(negedge clk);
                    rst = 1; ain_flat = 0; bin_flat = 0;
                    @(posedge clk); #1;

                    for (t = 0; t < K+6; t = t+1) begin
                        @(negedge clk);
                        rst = 0;
                        ain_flat = 0; bin_flat = 0;
                        // delay activation row r by r cycles
                        for (r = 0; r < 4; r = r+1) begin
                            k = t-r;
                            if ((rb+r < M) && (k >= 0) && (k < K))
                                ain_flat[r*W +: W] = patch_matrix[(rb+r)*K+k];
                        end
                        // delay weight column c by c cycles
                        for (c = 0; c < 4; c = c+1) begin
                            k = t-c;
                            if ((cb+c < N) && (k >= 0) && (k < K))
                                bin_flat[c*W +: W] = weights[weight_offset+k*N+cb+c];
                        end
                        @(posedge clk); #1; // wait for PE outputs
                        cycles = cycles+1;
                    end
                    // read the array outputs
                    for (r = 0; r < 4; r = r+1) begin
                        activation_sum = 0;
                        if (rb+r < M)
                            for (k = 0; k < K; k = k+1)
                                activation_sum = activation_sum+patch_matrix[(rb+r)*K+k];
                        for (c = 0; c < 4; c = c+1)
                            if ((rb+r < M) && (cb+c < N)) begin
                                // PE[c][r] gives output[r][c] since ain enters from top
                                raw = {32'b0, out_flat[(c*4+r)*A +: A]};
                                // subtract the offset added to the weights in python
                                mac_result[(rb+r)*N+cb+c] = raw - 128*activation_sum;
                                // check using normal matrix multiplication
                                if (VERIFY_MAC) begin
                                    expected_mac = 0;
                                    for (k = 0; k < K; k = k+1) begin
                                        activation = patch_matrix[(rb+r)*K+k];
                                        signed_weight = weights[weight_offset+k*N+cb+c];
                                        signed_weight = signed_weight-128;
                                        expected_mac = expected_mac+activation*signed_weight;
                                    end
                                    mac_checks = mac_checks+1;
                                    if ($signed(mac_result[(rb+r)*N+cb+c]) !== expected_mac) begin
                                        mac_errors = mac_errors+1;
                                        if (mac_errors <= 5)
                                            $display("Matrix mismatch: row=%0d col=%0d actual=%0d expected=%0d", rb+r, cb+c, mac_result[(rb+r)*N+cb+c], expected_mac);
                                    end
                                end
                            end
                    end
                    tiles = tiles+1;
                end
            end
        end
    endtask

    // ReLU and scale back to 8 bits
    function [7:0] relu_quant;
        input signed [63:0] acc;
        input [31:0] D;
        reg signed [63:0] scaled, divisor;
        begin
            divisor = {32'b0, D};
            if (acc <= 0) relu_quant = 0;
            else begin
                scaled = (acc+divisor/2)/divisor;
                if (scaled > 255) relu_quant = 255;
                else relu_quant = scaled[7:0];
            end
        end
    endfunction

    // put each 3x3 image region in a row (including all channels)
    task im2col;
        input integer H, IWIDTH, channels;
        integer y, x, dy, dx, ch, p, k;
        begin
            p = 0;
            for (y = 0; y < H-2; y = y+1)
                for (x = 0; x < IWIDTH-2; x = x+1) begin
                    k = 0;
                    for (dy = 0; dy < 3; dy = dy+1)
                        for (dx = 0; dx < 3; dx = dx+1)
                            for (ch = 0; ch < channels; ch = ch+1) begin
                                patch_matrix[p*9*channels+k] =
                                    feature[((y+dy)*IWIDTH+x+dx)*channels+ch];
                                k = k+1;
                            end
                    p = p+1;
                end
        end
    endtask

    // bias, ReLU, scaling and 2x2 max pooling
    task conv_postprocess;
        input integer H, IWIDTH, channels, bias_offset, div_index;
        integer y, x, ch, dy, dx, idx, ow;
        reg signed [63:0] acc;
        reg [7:0] val, maxval;
        begin
            ow = IWIDTH/2;
            for (y = 0; y < H/2; y = y+1)
                for (x = 0; x < IWIDTH/2; x = x+1)
                    for (ch = 0; ch < channels; ch = ch+1) begin
                        maxval = 0;
                        for (dy = 0; dy < 2; dy = dy+1)
                            for (dx = 0; dx < 2; dx = dx+1) begin
                                idx = ((2*y+dy)*IWIDTH+2*x+dx)*channels+ch;
                                acc = $signed(mac_result[idx]);
                                acc = acc+$signed(biases[bias_offset+ch]);
                                val = relu_quant(acc, divisors[div_index]);
                                if (val > maxval) maxval = val;
                            end
                        feature[(y*ow+x)*channels+ch] = maxval;
                    end
        end
    endtask

    task inference;
        input integer image_index;
        integer i;
        reg signed [63:0] acc;
        begin
            for (i = 0; i < 784; i = i+1)
                feature[i] = images[image_index*784+i];

            // conv1: 676x9 * 9x5, pool to 13x13x5
            im2col(28, 28, 1);
            matmul(676, 9, 5, W1);
            conv_postprocess(26, 26, 5, B1, 0);

            // conv2: 121x45 * 45x10, pool to 5x5x10
            im2col(13, 13, 5);
            matmul(121, 45, 10, W2);
            conv_postprocess(11, 11, 10, B2, 1);

            // feature is already flattened, 5*5*10 = 250
            // no dropout during testing
            for (i = 0; i < 250; i = i+1) patch_matrix[i] = feature[i];
            // dense1: 1x250 * 250x128
            matmul(1, 250, 128, W3);
            for (i = 0; i < 128; i = i+1) begin
                acc = $signed(mac_result[i]);
                acc = acc+$signed(biases[B3+i]);
                patch_matrix[i] = relu_quant(acc, divisors[2]);
            end

            // dense2: 1x128 * 128x10 (no ReLU)
            matmul(1, 128, 10, W4);
            for (i = 0; i < 10; i = i+1) begin
                acc = $signed(mac_result[i]);
                logits[i] = acc+$signed(biases[B4+i]);
            end
        end
    endtask

    integer img, predicted;
    initial begin : test
        integer j, correct, fd, errors_before;
        clk = 0; rst = 1; ain_flat = 0; bin_flat = 0;
        correct = 0; mac_checks = 0; mac_errors = 0;
        $readmemh("weights.mem", weights);
        $readmemh("biases.mem", biases);
        $readmemh("divisors.mem", divisors);
        $readmemh("images.mem", images);
        $readmemh("labels.mem", labels);
        // check if all memory files were read correctly
        for (j = 0; j < 33775; j = j+1)
            if (^weights[j] === 1'bx) begin
                $display("ERROR: missing weights");
                $finish;
            end
        for (j = 0; j < 153; j = j+1)
            if (^biases[j] === 1'bx) begin
                $display("ERROR: missing biases");
                $finish;
            end
        for (j = 0; j < 3; j = j+1)
            if ((^divisors[j] === 1'bx) || divisors[j] <= 0) begin
                $display("ERROR: invalid divisors");
                $finish;
            end
        for (j = 0; j < NUM_IMAGES*784; j = j+1)
            if ((^images[j] === 1'bx)) begin
                $display("ERROR: invalid images");
                $finish;
            end
        for (j = 0; j < NUM_IMAGES; j = j+1)
            if ((^labels[j] === 1'bx) || labels[j]>9) begin
                $display("ERROR: invalid labels");
                $finish;
            end
        fd = $fopen("simulation_results.csv","w");
        if (fd == 0) begin
            $display("ERROR: cannot open results file");
            $finish;
        end
        $fwrite(fd,"image,label,predicted,mac_mismatches,active_cycles,reset_cycles");
        for (j = 0; j < 10; j = j+1) $fwrite(fd,",logit%0d", j);
        $fwrite(fd,"\n");
        for (img = 0; img < NUM_IMAGES; img = img+1) begin
            cycles = 0; tiles = 0; errors_before = mac_errors;
            inference(img);
            predicted = 0;
            for (j = 1; j < 10; j = j+1)
                if (logits[j] > logits[predicted]) predicted = j;
            if (predicted == labels[img]) correct = correct+1;
            $display("Image %2d:  Label = %0d   Predicted = %0d",
                     img, labels[img], predicted);
            $fwrite(fd,"%0d,%0d,%0d,%0d,%0d,%0d", img, labels[img], predicted, mac_errors-errors_before, cycles, tiles);
            for (j = 0; j < 10; j = j+1) $fwrite(fd,",%0d", logits[j]);
            $fwrite(fd,"\n");
        end
        $fclose(fd);
        $display("\nAccuracy                  : %0d/%0d (%0.2f%%)", correct, NUM_IMAGES, 100.0*correct/NUM_IMAGES);
        if (VERIFY_MAC) $display("Matrix product mismatches : %0d/%0d", mac_errors, mac_checks);
        $display("Active cycles per image   : %0d", cycles);
        $display("Resets per image          : %0d", tiles);
        $finish;
    end
endmodule
