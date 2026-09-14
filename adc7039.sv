module adc7039 (
    input  logic        clk,        // 25 MHz FPGA clock
    input  logic        rst_n,      // Active-low reset
    input  logic        start,      // One-cycle pulse to begin conversion
    output logic [9:0] dout,       // 12-bit ADC data
    output logic        done,       // Asserted when data is valid
    
    // ADC SPI Signals
    output logic        max_clk,    // SPI_SCLK
    input  logic        max_ao,     // ADC_SDO
    output logic        max_cs      // ADC_CSn
);

    // FSM States using SystemVerilog enum
    typedef enum logic [2:0] {
        IDLE, ASSERT_CS, WAIT_CS, SHIFT, HOLD_CS, DONE_ST
    } state_t;

    state_t state;
    logic [11:0] shift_reg;
    logic [3:0]  bit_count;
    logic [1:0]  wait_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            max_cs     <= 1'b1;
            max_clk    <= 1'b0;
            shift_reg  <= 12'd0;
            dout       <= 12'd0;
            done       <= 1'b0;
            bit_count  <= 4'd0;
            wait_count <= 2'd0;
        end else begin
            case (state)
                IDLE: begin
                    done     <= 1'b0; // Clean 1-cycle pulse
                    max_cs   <= 1'b1;
                    max_clk  <= 1'b0;
                    if (start) begin
                        state <= ASSERT_CS;
                    end
                end

                ASSERT_CS: begin
                    max_cs     <= 1'b0; // Assert CS
                    wait_count <= 2'd0;
                    bit_count  <= 4'd0;
                    state      <= WAIT_CS;
                end

                WAIT_CS: begin
                    // t_su_csck min = 12ns. 2 cycles @ 25MHz = 80ns. Safe margin.
                    if (wait_count == 2'd1) begin
                        state <= SHIFT;
                    end else begin
                        wait_count <= wait_count + 1'b1;
                    end
                end

                SHIFT: begin
                    max_clk <= ~max_clk;
                    // Sample data on rising edge of max_clk
                    if (max_clk == 1'b0) begin 
                        shift_reg <= {shift_reg[10:0], max_ao};
                        bit_count <= bit_count + 1'b1;
                        if (bit_count == 4'd11) begin // 12 bits (0 to 11)
                            state <= HOLD_CS;
                        end
                    end
                end

                HOLD_CS: begin
                    max_clk <= 1'b0; // Ensure final falling edge
                    // t_d_csck min = 10ns. 1 cycle @ 25MHz = 40ns. Safe margin.
                    state <= DONE_ST;
                end

                DONE_ST: begin
                    max_cs    <= 1'b1; // Deassert CS
                    dout      <= shift_reg[9:0];
                    done      <= 1'b1;
                    state     <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
