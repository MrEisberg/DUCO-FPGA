// DUCO-S1 Miner Core
// Iterates nonce from 0 to max_nonce, computes SHA1(base_hash || ascii(nonce)),
// and compares against target_hash.

module duco_miner (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [319:0] base_hash,    // 40 ASCII hex bytes (byte 0 at MSB [319:312])
    input  wire [159:0] target_hash,  // Expected 160-bit SHA-1 digest
    input  wire [31:0]  max_nonce,    // Maximum nonce to test (inclusive)
    output reg          busy,
    output reg          done,         // Pulses high when search finishes (found or exhausted)
    output reg          found,        // High if target_hash was matched
    output reg  [31:0]  found_nonce
);

    localparam [1:0] IDLE      = 2'd0;
    localparam [1:0] START_SHA = 2'd1;
    localparam [1:0] WAIT_SHA  = 2'd2;

    reg [1:0]  state;
    reg [31:0] nonce;

    // 10-digit decimal counter (digits[0] = least significant digit)
    reg [3:0]  digits [0:9];
    reg [3:0]  num_digits; // 1..10

    reg          sha_start;
    reg  [511:0] sha_block;
    wire         sha_done;
    wire [159:0] sha_digest;

    sha1_core u_sha1 (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (sha_start),
        .block  (sha_block),
        /* verilator lint_off PINCONNECTEMPTY */
        .busy   (),
        /* verilator lint_on PINCONNECTEMPTY */
        .done   (sha_done),
        .digest (sha_digest)
    );

    // Build 512-bit (64-byte) padded SHA-1 block combinationally
    // Byte 0 is sha_block[511:504], Byte 63 is sha_block[7:0]
    integer b;
    reg [7:0] msg_bytes [0:63];
    reg [15:0] bit_len;

    always @(*) begin
        for (b = 0; b < 64; b = b + 1) begin
            msg_bytes[b] = 8'h00;
        end

        // First 40 bytes: base_hash
        for (b = 0; b < 40; b = b + 1) begin
            msg_bytes[b] = base_hash[319 - b*8 -: 8];
        end

        // Next num_digits bytes: ASCII decimal of nonce (MSD first)
        for (b = 0; b < 10; b = b + 1) begin
            if (b < {28'd0, num_digits}) begin
                msg_bytes[40 + b] = 8'h30 + {4'd0, digits[num_digits - 4'd1 - b[3:0]]};
            end
        end

        // SHA-1 padding: 0x80 immediately after message
        msg_bytes[6'd40 + {2'd0, num_digits}] = 8'h80;

        // 64-bit big-endian bit length at bytes 56..63 (fits in 16 bits)
        bit_len = (16'd40 + {12'd0, num_digits}) << 3;
        msg_bytes[62] = bit_len[15:8];
        msg_bytes[63] = bit_len[7:0];

        for (b = 0; b < 64; b = b + 1) begin
            sha_block[511 - b*8 -: 8] = msg_bytes[b];
        end
    end

    // Increment 10-digit decimal counter
    integer d_idx;
    reg carry;
    reg [3:0] next_digits [0:9];
    reg [3:0] next_num_digits;

    always @(*) begin
        carry = 1'b1;
        for (d_idx = 0; d_idx < 10; d_idx = d_idx + 1) begin
            if (carry) begin
                if (digits[d_idx] == 4'd9) begin
                    next_digits[d_idx] = 4'd0;
                    carry = 1'b1;
                end else begin
                    next_digits[d_idx] = digits[d_idx] + 4'd1;
                    carry = 1'b0;
                end
            end else begin
                next_digits[d_idx] = digits[d_idx];
            end
        end

        next_num_digits = num_digits;
        if (num_digits < 4'd10 && next_digits[num_digits] != 4'd0) begin
            next_num_digits = num_digits + 4'd1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= IDLE;
            busy        <= 1'b0;
            done        <= 1'b0;
            found       <= 1'b0;
            found_nonce <= 32'd0;
            nonce       <= 32'd0;
            sha_start   <= 1'b0;
            num_digits  <= 4'd1;
            for (d_idx = 0; d_idx < 10; d_idx = d_idx + 1) begin
                digits[d_idx] <= 4'd0;
            end
        end else begin
            done      <= 1'b0;
            sha_start <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        busy        <= 1'b1;
                        found       <= 1'b0;
                        found_nonce <= 32'd0;
                        nonce       <= 32'd0;
                        num_digits  <= 4'd1;
                        for (d_idx = 0; d_idx < 10; d_idx = d_idx + 1) begin
                            digits[d_idx] <= 4'd0;
                        end
                        state <= START_SHA;
                    end
                end

                START_SHA: begin
                    sha_start <= 1'b1;
                    state     <= WAIT_SHA;
                end

                WAIT_SHA: begin
                    if (sha_done) begin
                        if (sha_digest == target_hash) begin
                            found       <= 1'b1;
                            found_nonce <= nonce;
                            busy        <= 1'b0;
                            done        <= 1'b1;
                            state       <= IDLE;
                        end else if (nonce >= max_nonce) begin
                            found       <= 1'b0;
                            busy        <= 1'b0;
                            done        <= 1'b1;
                            state       <= IDLE;
                        end else begin
                            nonce      <= nonce + 32'd1;
                            num_digits <= next_num_digits;
                            for (d_idx = 0; d_idx < 10; d_idx = d_idx + 1) begin
                                digits[d_idx] <= next_digits[d_idx];
                            end
                            state <= START_SHA;
                        end
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
