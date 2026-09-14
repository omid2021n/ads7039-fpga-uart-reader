module uart_tx (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        tx_en,      // one-cycle pulse: begin a transmission
    input  wire [7:0]  tx_data,
    output reg         tx_out,
    output reg         done        // one-cycle pulse: transmission complete
);

    reg  [9:0] shift_tx;
    reg        baudrate;
    reg  [7:0] baudrate_freq;
    reg  [3:0] bit_count;
    reg        busy;

    // Baud rate generator: 115200 baud @ 25 MHz -> pulse every 217 clocks
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baudrate      <= 1'b0;
            baudrate_freq <= 8'd0;
        end else begin
            if (baudrate_freq == 8'd216) begin
                baudrate_freq <= 8'd0;
                baudrate      <= 1'b1;
            end else begin
                baudrate_freq <= baudrate_freq + 1'b1;
                baudrate      <= 1'b0;
            end
        end
    end

    // Transmit shift register + busy/done handshake
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_tx  <= 10'b11_1111_1111;
            tx_out    <= 1'b1; // idle state is logic 1
            bit_count <= 4'd0;
            busy      <= 1'b0;
            done      <= 1'b0;
        end else begin
            done <= 1'b0; // done defaults low every cycle -> becomes a clean 1-cycle pulse

            if (!busy) begin
                if (tx_en) begin
                    shift_tx  <= {1'b1, tx_data, 1'b0}; // stop, data, start
                    busy      <= 1'b1;
                    bit_count <= 4'd0;
                end
            end else if (baudrate) begin
                tx_out    <= shift_tx[0];
                shift_tx  <= {1'b1, shift_tx[9:1]};
                bit_count <= bit_count + 1'b1;

                if (bit_count == 4'd9) begin // 10th bit (the stop bit) just went out
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end

endmodule
