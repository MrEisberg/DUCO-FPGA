// DUCO-S1 Dual-Core Even/Odd Miner
// Splits a single job across 2 cores (even nonces 0,2,4... and odd nonces 1,3,5...)
// to double throughput without triggering the Kolka multi-miner penalty.

/* verilator lint_off DECLFILENAME */
module duco_miner_core #(
    parameter [31:0] INIT_NONCE = 32'd0,
    parameter [31:0] STEP_NONCE = 32'd2
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire         abort,
    input  wire [319:0] base_hash,
    input  wire [159:0] target_hash,
    input  wire [31:0]  max_nonce,
    output reg          done,
    output reg          found,
    output reg  [31:0]  found_nonce
);

    localparam [1:0] IDLE      = 2'd0;
    localparam [1:0] START_SHA = 2'd1;
    localparam [1:0] WAIT_SHA  = 2'd2;

    reg [1:0]  state;
    reg [31:0] nonce;

    // 10-digit decimal counter (digits[0] = least significant digit)
    reg [3:0]  digits [0:9];
    reg [3:0]  num_digits;

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

    integer b;
    reg [7:0]  msg_bytes [0:63];
    reg [15:0] bit_len;

    always @(*) begin
        for (b = 0; b < 64; b = b + 1) begin
            msg_bytes[b] = 8'h00;
        end

        for (b = 0; b < 40; b = b + 1) begin
            msg_bytes[b] = base_hash[319 - b*8 -: 8];
        end

        for (b = 0; b < 10; b = b + 1) begin
            if (b < {28'd0, num_digits}) begin
                msg_bytes[40 + b] = 8'h30 + {4'd0, digits[num_digits - 4'd1 - b[3:0]]};
            end
        end

        msg_bytes[6'd40 + {2'd0, num_digits}] = 8'h80;

        bit_len = (16'd40 + {12'd0, num_digits}) << 3;
        msg_bytes[62] = bit_len[15:8];
        msg_bytes[63] = bit_len[7:0];

        for (b = 0; b < 64; b = b + 1) begin
            sha_block[511 - b*8 -: 8] = msg_bytes[b];
        end
    end

    // Increment 10-digit decimal counter by STEP_NONCE (2)
    integer d_idx;
    reg [4:0] sum_d;
    reg [3:0] carry;
    reg [3:0] next_digits [0:9];
    reg [3:0] next_num_digits;

    always @(*) begin
        carry = STEP_NONCE[3:0];
        for (d_idx = 0; d_idx < 10; d_idx = d_idx + 1) begin
            sum_d = {1'b0, digits[d_idx]} + {1'b0, carry};
            if (sum_d >= 5'd10) begin
                next_digits[d_idx] = sum_d[3:0] - 4'd10;
                carry = 4'd1;
            end else begin
                next_digits[d_idx] = sum_d[3:0];
                carry = 4'd0;
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
            done        <= 1'b0;
            found       <= 1'b0;
            found_nonce <= 32'd0;
            nonce       <= INIT_NONCE;
            sha_start   <= 1'b0;
            num_digits  <= 4'd1;
            for (d_idx = 0; d_idx < 10; d_idx = d_idx + 1) begin
                digits[d_idx] <= 4'd0;
            end
        end else begin
            done      <= 1'b0;
            sha_start <= 1'b0;

            if (abort) begin
                state <= IDLE;
            end else begin
                case (state)
                    IDLE: begin
                        if (start) begin
                            found       <= 1'b0;
                            found_nonce <= 32'd0;
                            nonce       <= INIT_NONCE;
                            num_digits  <= 4'd1;
                            digits[0]   <= INIT_NONCE[3:0];
                            for (d_idx = 1; d_idx < 10; d_idx = d_idx + 1) begin
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
                                done        <= 1'b1;
                                state       <= IDLE;
                            end else if (nonce + STEP_NONCE > max_nonce) begin
                                found <= 1'b0;
                                done  <= 1'b1;
                                state <= IDLE;
                            end else begin
                                nonce      <= nonce + STEP_NONCE;
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
    end

endmodule
/* verilator lint_on DECLFILENAME */


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

    wire [3:0]  c_done;
    wire [3:0]  c_found;
    wire [31:0] c_nonce [0:3];
    reg  [3:0]  c_finished;

    wire abort_cores = |(c_done & c_found);

    genvar g;
    generate
        for (g = 0; g < 4; g = g + 1) begin : gen_cores
            duco_miner_core #(
                .INIT_NONCE(g),
                .STEP_NONCE(32'd4)
            ) u_core (
                .clk         (clk),
                .rst_n       (rst_n),
                .start       (start && !busy),
                .abort       (abort_cores),
                .base_hash   (base_hash),
                .target_hash (target_hash),
                .max_nonce   (max_nonce),
                .done        (c_done[g]),
                .found       (c_found[g]),
                .found_nonce (c_nonce[g])
            );
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy        <= 1'b0;
            done        <= 1'b0;
            found       <= 1'b0;
            found_nonce <= 32'd0;
            c_finished  <= 4'b0000;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                busy        <= 1'b1;
                found       <= 1'b0;
                found_nonce <= 32'd0;
                c_finished  <= 4'b0000;
            end else if (busy) begin
                if (c_done[0] && c_found[0]) begin
                    found <= 1'b1; found_nonce <= c_nonce[0]; busy <= 1'b0; done <= 1'b1;
                end else if (c_done[1] && c_found[1]) begin
                    found <= 1'b1; found_nonce <= c_nonce[1]; busy <= 1'b0; done <= 1'b1;
                end else if (c_done[2] && c_found[2]) begin
                    found <= 1'b1; found_nonce <= c_nonce[2]; busy <= 1'b0; done <= 1'b1;
                end else if (c_done[3] && c_found[3]) begin
                    found <= 1'b1; found_nonce <= c_nonce[3]; busy <= 1'b0; done <= 1'b1;
                end else begin
                    c_finished <= c_finished | c_done;
                    if (&(c_finished | c_done)) begin
                        found <= 1'b0;
                        busy  <= 1'b0;
                        done  <= 1'b1;
                    end
                end
            end
        end
    end

endmodule
