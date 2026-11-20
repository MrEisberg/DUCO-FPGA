// Simple 8N1 UART Transmitter (default 115200 baud @ 27 MHz -> CLKS_PER_BIT = 234)
module uart_tx #(
    parameter integer CLKS_PER_BIT = 234
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx,
    output reg        tx_busy
);

    localparam [1:0] IDLE  = 2'd0;
    localparam [1:0] START = 2'd1;
    localparam [1:0] DATA  = 2'd2;
    localparam [1:0] STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_cnt;
    reg [2:0]  bit_idx;
    reg [7:0]  shift_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            clk_cnt   <= 16'd0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
            tx        <= 1'b1;
            tx_busy   <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    tx      <= 1'b1;
                    clk_cnt <= 16'd0;
                    bit_idx <= 3'd0;
                    if (tx_start) begin
                        shift_reg <= tx_data;
                        tx_busy   <= 1'b1;
                        state     <= START;
                    end else begin
                        tx_busy <= 1'b0;
                    end
                end

                START: begin
                    tx <= 1'b0;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        state   <= DATA;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                DATA: begin
                    tx <= shift_reg[bit_idx];
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
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
                    tx <= 1'b1;
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        tx_busy <= 1'b0;
                        state   <= IDLE;
                    end else begin
                        clk_cnt <= clk_cnt + 16'd1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
