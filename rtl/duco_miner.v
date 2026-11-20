// DUCO-S1 10-Core Lockstep Shift-Register Miner
// All 10 cores share a single prefix counter, round counter, and K-constant generator.
// Core g (0..9) tests nonce = 10*prefix + g in exact lockstep (0 Kolka penalty).

module duco_miner (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [319:0] base_hash,
    input  wire [159:0] target_hash,
    input  wire [31:0]  max_nonce,
    output reg          busy,
    output reg          done,
    output reg          found,
    output reg  [31:0]  found_nonce
);

    localparam [31:0] H0_INIT = 32'h67452301;
    localparam [31:0] H1_INIT = 32'hEFCDAB89;
    localparam [31:0] H2_INIT = 32'h98BADCFE;
    localparam [31:0] H3_INIT = 32'h10325476;
    localparam [31:0] H4_INIT = 32'hC3D2E1F0;

    localparam [1:0] ST_IDLE  = 2'd0;
    localparam [1:0] ST_LOAD  = 2'd1;
    localparam [1:0] ST_RUN   = 2'd2;
    localparam [1:0] ST_CHECK = 2'd3;

    reg [1:0]   state;
    reg [6:0]   t;
    reg [31:0]  nonce_base;
    reg [159:0] adj_target;

    // Shared 9-digit BCD prefix counter (nonce_base / 10)
    reg [3:0] prefix_digits [0:8];
    reg [3:0] prefix_len; // 0..9

    // Shared round_sel and k_next for all 10 lockstep cores
    wire [1:0] round_sel = (t < 7'd20) ? 2'd0 :
                           (t < 7'd40) ? 2'd1 :
                           (t < 7'd60) ? 2'd2 : 2'd3;

    wire [6:0] t_next = t + 7'd1;
    wire [31:0] k_next = (t_next < 7'd20) ? 32'h5A827999 :
                         (t_next < 7'd40) ? 32'h6ED9EBA1 :
                         (t_next < 7'd60) ? 32'h8F1BBCDC : 32'hCA62C1D6;

    wire core_load = (state == ST_LOAD);
    wire core_run  = (state == ST_RUN);

    // Build shared 12-byte template for W[10..12] (bytes 40..51)
    // Byte at index prefix_len is 8'h30; each core g ORs its constant digit g[3:0] into it.
    integer b;
    reg [7:0]  tpl [0:11];
    wire [15:0] bit_len = (16'd41 + {12'd0, prefix_len}) << 3;

    always @(*) begin
        for (b = 0; b < 12; b = b + 1) begin
            tpl[b] = 8'h00;
        end
        for (b = 0; b < 9; b = b + 1) begin
            if (b < {28'd0, prefix_len}) begin
                tpl[b] = 8'h30 + {4'd0, prefix_digits[prefix_len - 4'd1 - b[3:0]]};
            end
        end
        tpl[prefix_len]          = 8'h30;
        tpl[prefix_len + 4'd1]   = 8'h80;
    end

    wire [95:0] tpl_flat = {
        tpl[0], tpl[1], tpl[2],  tpl[3],
        tpl[4], tpl[5], tpl[6],  tpl[7],
        tpl[8], tpl[9], tpl[10], tpl[11]
    };

    // Instantiate 10 lockstep shift-register SHA-1 cores (last digit 0..9)
    wire [9:0] core_match;

    genvar g;
    generate
        for (g = 0; g < 10; g = g + 1) begin : gen_cores
            wire [95:0] digit_mask = {92'd0, g[3:0]} << ((4'd11 - prefix_len) * 8);
            wire [95:0] core_w10_12 = tpl_flat | digit_mask;

            sha1_core u_sha1 (
                .clk        (clk),
                .rst_n      (rst_n),
                .load       (core_load),
                .run        (core_run),
                .round_sel  (round_sel),
                .k_next     (k_next),
                .base_hash  (base_hash),
                .w10_in     (core_w10_12[95:64]),
                .w11_in     (core_w10_12[63:32]),
                .w12_in     (core_w10_12[31:0]),
                .bit_len_in (bit_len),
                .adj_target (adj_target),
                .match      (core_match[g])
            );
        end
    endgenerate

    // Next prefix BCD calculation
    integer d;
    reg       carry;
    reg [3:0] next_prefix_digits [0:8];
    reg [3:0] next_prefix_len;

    always @(*) begin
        carry = 1'b0;
        if (prefix_len == 4'd0) begin
            next_prefix_digits[0] = 4'd1;
            for (d = 1; d < 9; d = d + 1) begin
                next_prefix_digits[d] = 4'd0;
            end
            next_prefix_len = 4'd1;
        end else begin
            carry = 1'b1;
            for (d = 0; d < 9; d = d + 1) begin
                if (carry) begin
                    if (prefix_digits[d] == 4'd9) begin
                        next_prefix_digits[d] = 4'd0;
                        carry = 1'b1;
                    end else begin
                        next_prefix_digits[d] = prefix_digits[d] + 4'd1;
                        carry = 1'b0;
                    end
                end else begin
                    next_prefix_digits[d] = prefix_digits[d];
                end
            end
            next_prefix_len = prefix_len;
            if (prefix_len < 4'd9 && next_prefix_digits[prefix_len] != 4'd0) begin
                next_prefix_len = prefix_len + 4'd1;
            end
        end
    end

    // Valid match check (ensure winning nonce <= max_nonce)
    reg        any_valid_match;
    reg [3:0]  win_digit;
    integer    m;

    always @(*) begin
        any_valid_match = 1'b0;
        win_digit       = 4'd0;
        for (m = 0; m < 10; m = m + 1) begin
            if (!any_valid_match && core_match[m] && (nonce_base + m <= max_nonce)) begin
                any_valid_match = 1'b1;
                win_digit       = m[3:0];
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            busy        <= 1'b0;
            done        <= 1'b0;
            found       <= 1'b0;
            found_nonce <= 32'd0;
            t           <= 7'd0;
            nonce_base  <= 32'd0;
            adj_target  <= 160'd0;
            prefix_len  <= 4'd0;
            for (d = 0; d < 9; d = d + 1) begin
                prefix_digits[d] <= 4'd0;
            end
        end else begin
            done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start) begin
                        busy        <= 1'b1;
                        found       <= 1'b0;
                        found_nonce <= 32'd0;
                        nonce_base  <= 32'd0;
                        prefix_len  <= 4'd0;
                        for (d = 0; d < 9; d = d + 1) begin
                            prefix_digits[d] <= 4'd0;
                        end
                        adj_target <= {
                            target_hash[159:128] - H0_INIT,
                            target_hash[127:96]  - H1_INIT,
                            target_hash[95:64]   - H2_INIT,
                            target_hash[63:32]   - H3_INIT,
                            target_hash[31:0]    - H4_INIT
                        };
                        state <= ST_LOAD;
                    end
                end

                ST_LOAD: begin
                    t     <= 7'd0;
                    state <= ST_RUN;
                end

                ST_RUN: begin
                    if (t == 7'd79) begin
                        state <= ST_CHECK;
                    end else begin
                        t <= t + 7'd1;
                    end
                end

                ST_CHECK: begin
                    if (any_valid_match) begin
                        found       <= 1'b1;
                        found_nonce <= nonce_base + {28'd0, win_digit};
                        busy        <= 1'b0;
                        done        <= 1'b1;
                        state       <= ST_IDLE;
                    end else if (nonce_base + 32'd10 > max_nonce) begin
                        found <= 1'b0;
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        nonce_base <= nonce_base + 32'd10;
                        prefix_len <= next_prefix_len;
                        for (d = 0; d < 9; d = d + 1) begin
                            prefix_digits[d] <= next_prefix_digits[d];
                        end
                        state <= ST_LOAD;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
