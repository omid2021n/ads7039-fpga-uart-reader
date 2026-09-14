module adc7039_tb;

    logic         clk;
    logic         rst_n;
    logic         start;
    logic [11:0]  dout;
    logic         done;
    // ADC SPI Signals
    logic         max_clk;
    logic         max_ao;
    logic         max_cs;
    
    adc7039 dut (
        .clk(clk), 
        .rst_n(rst_n), 
        .start(start), 
        .dout(dout), 
        .done(done), 
        .max_clk(max_clk),
        .max_ao(max_ao),
        .max_cs(max_cs)
    );
    
    initial clk = 1'b0;
    always #20 clk = ~clk; // 25 MHz clock
    
    // Corrected task: Do NOT wait for max_cs at the end. Let check_dout handle it.
    task send_adc_data(input logic [11:0] data);
        integer i;
        begin
            @(negedge max_cs);           // Wait for DUT to open the window (CS goes low)
            for (i = 11; i >= 0; i = i - 1) begin
                max_ao = data[i];        // Set data
                @(posedge max_clk);      // DUT samples on rising edge
                @(negedge max_clk);      // Wait for SCLK to go low before changing data
            end
        end
    endtask

    // Corrected task: Wait for `done` directly.
    task check_dout(input logic [11:0] expected);
        begin
            @(posedge done);             // Wait for DUT to assert done
            #1;                          // Small delay to let signals settle
            if (dout === expected)
                $display("[%0t] PASS: Dout = %03h", $time, dout);
            else
                $display("[%0t] FAIL: expected %03h, got %03h", $time, expected, dout);
        end
    endtask

    initial begin
        rst_n  = 1'b0;
        start  = 1'b0;
        max_ao = 12'd0;
        
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        
        // Test Case 1
        start = 1'b1;
        @(posedge clk);
        start = 1'b0; // One-cycle pulse
        send_adc_data(12'h255);
        check_dout(12'h255); 

        // Test Case 2
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        send_adc_data(12'h1AA);
        check_dout(12'h1AA);

        // Test Case 3
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        send_adc_data(12'h33C);
        check_dout(12'h33C);

        // Test Case 4
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;
        send_adc_data(12'h0F0);
        check_dout(12'h0F0);

        $finish;
    end

endmodule
