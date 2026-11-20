// Tang Nano 20K Top-Level Wrapper for DUCO-S1 Dual-Core Miner
// Protocol over UART (115200 8N1):
//   RX: <40-char base_hash>,<40-char hex target_hash>,<decimal max_nonce>\n
//   TX: <0|1>,<decimal found_nonce>,0\n

module duco_top (
    input  wire       clk,      // 27 MHz onboard oscillator (pin 4)
    input  wire       rst_n,    // Active-low reset button (pin 88)
    input  wire       uart_rx,  // UART RX (pin 70)
    output wire       uart_tx,  // UART TX (pin 69)
    output wire [1:0] led       // Active-low onboard LEDs (pins 15, 16)
);

    localparam integer CLKS_PER_BIT = 234; // 27,000,000 / 115,200

    wire       rx_valid;
    wire [7:0] rx_data;
    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_busy;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk      (clk),
        .rst_n    (rst_n),
        .rx       (uart_rx),
        .rx_valid (rx_valid),
        .rx_data  (rx_data)
    );

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx       (uart_tx),
        .tx_busy  (tx_busy)
    );

    reg          miner_start;
    reg  [319:0] base_hash;
    reg  [159:0] target_hash;
    reg  [31:0]  max_nonce;
    wire         miner_busy;
    wire         miner_done;
    wire         miner_found;
    wire [31:0]  miner_nonce;

    duco_miner u_miner (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (miner_start),
        .base_hash   (base_hash),
        .target_hash (target_hash),
        .max_nonce   (max_nonce),
        .busy        (miner_busy),
        .done        (miner_done),
        .found       (miner_found),
        .found_nonce (miner_nonce)
    );

    function automatic [3:0] ascii_to_hex(input [7:0] ch);
        begin
            if (ch >= "0" && ch <= "9")
                ascii_to_hex = ch[3:0];
            else if (ch >= "a" && ch <= "f")
                ascii_to_hex = ch[3:0] + 4'd9;
            else if (ch >= "A" && ch <= "F")
                ascii_to_hex = ch[3:0] + 4'd9;
            else
                ascii_to_hex = 4'd0;
        end
    endfunction

    localparam [2:0] ST_RX_BASE   = 3'd0;
    localparam [2:0] ST_RX_TARGET = 3'd1;
    localparam [2:0] ST_RX_MAX    = 3'd2;
    localparam [2:0] ST_MINING    = 3'd3;
    localparam [2:0] ST_BIN2BCD   = 3'd4;
    localparam [2:0] ST_TX_RESP   = 3'd5;

    reg [2:0]  state;
    reg [5:0]  char_cnt;
    reg [7:0]  tx_buf [0:15];
    reg [3:0]  tx_len;
    reg [3:0]  tx_idx;
    reg [31:0] bcd_shift_bin;
    reg [39:0] bcd_digits;
    reg [5:0]  bcd_cnt;
    reg [23:0] hb_cnt;
    reg [22:0] share_cnt;
    integer    k;

    assign led[0] = !(miner_busy && hb_cnt[23]);
    assign led[1] = !(share_cnt != 23'd0);

    reg [39:0] bcd_adj;
    always @(*) begin
        bcd_adj = bcd_digits;
        for (k = 0; k < 10; k = k + 1) begin
            if (bcd_adj[k*4 +: 4] >= 4'd5)
                bcd_adj[k*4 +: 4] = bcd_adj[k*4 +: 4] + 4'd3;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_RX_BASE;
            char_cnt    <= 6'd0;
            miner_start <= 1'b0;
            tx_start    <= 1'b0;
            tx_data     <= 8'd0;
            tx_len      <= 4'd0;
            tx_idx      <= 4'd0;
            base_hash   <= 320'd0;
            target_hash <= 160'd0;
            max_nonce   <= 32'd0;
            hb_cnt      <= 24'd0;
            share_cnt   <= 23'd0;
        end else begin
            miner_start <= 1'b0;
            tx_start    <= 1'b0;
            hb_cnt      <= hb_cnt + 24'd1;
            if (share_cnt != 23'd0)
                share_cnt <= share_cnt - 23'd1;

            case (state)
                ST_RX_BASE: begin
                    if (rx_valid) begin
                        if (rx_data == ",") begin
                            char_cnt <= 6'd0;
                            state    <= ST_RX_TARGET;
                        end else if (rx_data != "\r" && rx_data != "\n") begin
                            base_hash <= {base_hash[311:0], rx_data};
                            char_cnt  <= char_cnt + 6'd1;
                        end
                    end
                end

                ST_RX_TARGET: begin
                    if (rx_valid) begin
                        if (rx_data == ",") begin
                            max_nonce <= 32'd0;
                            state     <= ST_RX_MAX;
                        end else if (rx_data != "\r" && rx_data != "\n") begin
                            target_hash <= {target_hash[155:0], ascii_to_hex(rx_data)};
                        end
                    end
                end

                ST_RX_MAX: begin
                    if (rx_valid) begin
                        if (rx_data == "\n" || rx_data == "\r") begin
                            miner_start <= 1'b1;
                            state       <= ST_MINING;
                        end else if (rx_data >= "0" && rx_data <= "9") begin
                            max_nonce <= (max_nonce * 32'd10) + {28'd0, rx_data[3:0]};
                        end
                    end
                end

                ST_MINING: begin
                    if (miner_done) begin
                        if (miner_found)
                            share_cnt <= 23'd5400000; // ~0.2s pulse @ 27 MHz
                        tx_buf[0] <= miner_found ? "1" : "0";
                        tx_buf[1] <= ",";
                        if (!miner_found) begin
                            tx_buf[2] <= "0";
                            tx_buf[3] <= ",";
                            tx_buf[4] <= "0";
                            tx_buf[5] <= "\n";
                            tx_len    <= 4'd6;
                            tx_idx    <= 4'd0;
                            state     <= ST_TX_RESP;
                        end else begin
                            bcd_shift_bin <= miner_nonce;
                            bcd_digits    <= 40'd0;
                            bcd_cnt       <= 6'd0;
                            state         <= ST_BIN2BCD;
                        end
                    end
                end

                ST_BIN2BCD: begin
                    if (bcd_cnt < 6'd32) begin
                        bcd_digits    <= {bcd_adj[38:0], bcd_shift_bin[31]};
                        bcd_shift_bin <= {bcd_shift_bin[30:0], 1'b0};
                        bcd_cnt       <= bcd_cnt + 6'd1;
                    end else begin
                        for (k = 0; k < 10; k = k + 1) begin
                            tx_buf[2 + k] <= 8'h30 + {4'd0, bcd_digits[(9 - k)*4 +: 4]};
                        end
                        tx_buf[12] <= ",";
                        tx_buf[13] <= "0";
                        tx_buf[14] <= "\n";
                        tx_len     <= 4'd15;
                        tx_idx     <= 4'd0;
                        state      <= ST_TX_RESP;
                    end
                end

                ST_TX_RESP: begin
                    if (!tx_busy && !tx_start) begin
                        if (tx_idx < tx_len) begin
                            tx_data  <= tx_buf[tx_idx];
                            tx_start <= 1'b1;
                            tx_idx   <= tx_idx + 4'd1;
                        end else begin
                            char_cnt <= 6'd0;
                            state    <= ST_RX_BASE;
                        end
                    end
                end

                default: state <= ST_RX_BASE;
            endcase
        end
    end

endmodule
