// Simple 8N1 UART Receiver (default 115200 baud @ 27 MHz -> CLKS_PER_BIT = 234)
module uart_rx #(
    parameter integer CLKS_PER_BIT = 234
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg        rx_valid,
    output reg  [7:0] rx_data
);

    localparam [1:0] IDLE  = 2'd0;
    localparam [1:0] START = 2'd1;
    localparam [1:0] DATA  = 2'd2;
    localparam [1:0] STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift_reg;
    reg        rx_sync1, rx_sync2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            clk_cnt   <= 16'd0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
            rx_valid  <= 1'b0;
            rx_data   <= 8'd0;
        end else begin
            rx_valid <= 1'b0;

            case (state)
                IDLE: begin
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (!rx_sync2) begin
                        state <= START;
                    end
                end

                START: begin
                    if (clk_cnt == (CLKS_PER_BIT / 2) - 1) begin
                        if (!rx_sync2) begin
                            clk_cnt <= 16'd0;
                            state   <= DATA;
                        end else begin
                            state <= IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt            <= 16'd0;
                        shift_reg[bit_idx] <= rx_sync2;
                        if (bit_idx == 3'd7) begin
                            bit_idx <= 3'd0;
                            state   <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 3'd1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt  <= 16'd0;
                        rx_valid <= 1'b1;
                        rx_data  <= shift_reg;
                        state    <= IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
