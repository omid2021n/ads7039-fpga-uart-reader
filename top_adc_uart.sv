module top_adc_uart (
    input  logic        clk_25MHz,
    input  logic        rst_n,

    // ADC SPI pins
    output logic        max_clk,
    input  logic        max_ao,
    output logic        max_cs,

    // UART pins
    output logic        uart_tx_out,

    // Status LED
    output logic        led1
);

    // ============================================================
    //  1. Sampling Tick Generator (~1 kSPS – matched to UART)
    // ============================================================
    localparam int CLK_HZ = 25_000_000;
    localparam int Fs     = 1_000;                   // 1 kSPS
    localparam int DIV    = CLK_HZ / Fs;             // 25_000
    localparam int CNT_W  = $clog2(DIV);

    logic [CNT_W-1:0] sample_counter;
    logic             sample_tick;

    // ============================================================
    //  2. ADC ↔ UART Handshake Controller FSM
    // ============================================================
    typedef enum logic [2:0] {
        IDLE,
        ADC_START,
        ADC_WAIT,
        UART_BYTE1,
        UART_BYTE1_W,
        UART_BYTE2,
        UART_BYTE2_W
    } ctrl_t;

    ctrl_t ctrl_state;

    logic [9:0] adc_data_from_adc;   // 10-bit ADC output
    logic [9:0] adc_data;            // latched copy
    logic       adc_valid;
    logic       adc_start;

    logic [7:0] uart_data;
    logic       uart_tx_en;
    logic       uart_done;

    // ------------------------------------------------------------
    //  Sampling tick
    // ------------------------------------------------------------
    always_ff @(posedge clk_25MHz or negedge rst_n) begin
        if (!rst_n) begin
            sample_counter <= '0;
            sample_tick    <= 1'b0;
            led1           <= 1'b0;
        end else if (sample_counter == DIV - 1) begin
            sample_counter <= '0;
            sample_tick    <= 1'b1;
            led1           <= ~led1;
        end else begin
            sample_counter <= sample_counter + 1'b1;
            sample_tick    <= 1'b0;
        end
    end

    // ------------------------------------------------------------
    //  Controller FSM
    // ------------------------------------------------------------
    always_ff @(posedge clk_25MHz or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_state <= IDLE;
            adc_start  <= 1'b0;
            uart_tx_en <= 1'b0;
            uart_data  <= 8'd0;
            adc_data   <= 10'd0;               // ← 10 bits, not 12
        end else begin
            // Defaults
            adc_start  <= 1'b0;
            uart_tx_en <= 1'b0;

            case (ctrl_state)
                IDLE: begin
                    if (sample_tick) begin
                        ctrl_state <= ADC_START;
                    end
                end

                ADC_START: begin
                    adc_start  <= 1'b1;
                    ctrl_state <= ADC_WAIT;
                end

                ADC_WAIT: begin
                    if (adc_valid) begin
                        adc_data   <= adc_data_from_adc;
                        ctrl_state <= UART_BYTE1;
                    end
                end

                UART_BYTE1: begin
                    // Upper 2 bits of the 10-bit ADC, zero-padded to 8
                    uart_data  <= {6'b0, adc_data[9:8]};
                    uart_tx_en <= 1'b1;
                    ctrl_state <= UART_BYTE1_W;
                end

                UART_BYTE1_W: begin
                    if (uart_done) begin
                        ctrl_state <= UART_BYTE2;
                    end
                end

                UART_BYTE2: begin
                    // Lower 8 bits of the 10-bit ADC
                    uart_data  <= adc_data[7:0];
                    uart_tx_en <= 1'b1;
                    ctrl_state <= UART_BYTE2_W;
                end

                UART_BYTE2_W: begin
                    if (uart_done) begin
                        ctrl_state <= IDLE;
                    end
                end

                default: ctrl_state <= IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------
    //  ADC driver (10-bit output)
    // ------------------------------------------------------------
    adc7039 u_adc (
        .clk      (clk_25MHz),
        .rst_n    (rst_n),
        .start    (adc_start),
        .dout     (adc_data_from_adc),
        .done     (adc_valid),
        .max_clk  (max_clk),
        .max_ao   (max_ao),
        .max_cs   (max_cs)
    );

    // ------------------------------------------------------------
    //  UART transmitter
    // ------------------------------------------------------------
    uart_tx u_uart (
        .clk      (clk_25MHz),
        .rst_n    (rst_n),
        .tx_en    (uart_tx_en),
        .tx_data  (uart_data),
        .tx_out   (uart_tx_out),
        .done     (uart_done)
    );

endmodule
