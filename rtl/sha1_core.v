// Synthesizable iterative SHA-1 core (1 round per clock cycle, 80 rounds)
// Suitable for Verilator simulation and Gowin GW2AR-18 (Tang Nano 20K)

module sha1_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [511:0] block,   // Big-endian 512-bit padded message block
    output reg          busy,
    output reg          done,
    output reg  [159:0] digest   // {h0, h1, h2, h3, h4}
);

    localparam [31:0] H0_INIT = 32'h67452301;
    localparam [31:0] H1_INIT = 32'hEFCDAB89;
    localparam [31:0] H2_INIT = 32'h98BADCFE;
    localparam [31:0] H3_INIT = 32'h10325476;
    localparam [31:0] H4_INIT = 32'hC3D2E1F0;

    localparam [1:0] IDLE   = 2'd0;
    localparam [1:0] ROUNDS = 2'd1;
    localparam [1:0] FINISH = 2'd2;

    reg [1:0]  state;
    reg [6:0]  t;
    reg [31:0] w [0:15];
    reg [31:0] a, b, c, d, e;

    function automatic [31:0] rotl32(input [31:0] x, input [4:0] n);
        begin
            rotl32 = (x << n) | (x >> (32 - n));
        end
    endfunction

    // Current W[t] and next expanded W[t]
    wire [3:0]  idx3    = t[3:0] - 4'd3;
    wire [3:0]  idx8    = t[3:0] - 4'd8;
    wire [3:0]  idx14   = t[3:0] - 4'd14;
    wire [31:0] wt_curr = w[t[3:0]];
    wire [31:0] wt_exp  = rotl32(
        w[idx3] ^ w[idx8] ^ w[idx14] ^ w[t[3:0]],
        5'd1
    );

    reg [31:0] f_val;
    reg [31:0] k_val;

    always @(*) begin
        if (t < 7'd20) begin
            f_val = (b & c) | ((~b) & d);
            k_val = 32'h5A827999;
        end else if (t < 7'd40) begin
            f_val = b ^ c ^ d;
            k_val = 32'h6ED9EBA1;
        end else if (t < 7'd60) begin
            f_val = (b & c) | (b & d) | (c & d);
            k_val = 32'h8F1BBCDC;
        end else begin
            f_val = b ^ c ^ d;
            k_val = 32'hCA62C1D6;
        end
    end

    wire [31:0] temp = rotl32(a, 5'd5) + f_val + e + k_val + wt_curr;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= IDLE;
            busy   <= 1'b0;
            done   <= 1'b0;
            t      <= 7'd0;
            digest <= 160'd0;
            a <= 32'd0; b <= 32'd0; c <= 32'd0; d <= 32'd0; e <= 32'd0;
            for (i = 0; i < 16; i = i + 1) begin
                w[i] <= 32'd0;
            end
        end else begin
            done <= 1'b0;

            case (state)
                IDLE: begin
                    if (start) begin
                        for (i = 0; i < 16; i = i + 1) begin
                            w[i] <= block[511 - i*32 -: 32];
                        end
                        a     <= H0_INIT;
                        b     <= H1_INIT;
                        c     <= H2_INIT;
                        d     <= H3_INIT;
                        e     <= H4_INIT;
                        t     <= 7'd0;
                        busy  <= 1'b1;
                        state <= ROUNDS;
                    end
                end

                ROUNDS: begin
                    e <= d;
                    d <= c;
                    c <= rotl32(b, 5'd30);
                    b <= a;
                    a <= temp;

                    // Pre-compute W[t+16] in-place for rounds >= 16
                    w[t[3:0]] <= wt_exp;

                    if (t == 7'd79) begin
                        state <= FINISH;
                    end else begin
                        t <= t + 7'd1;
                    end
                end

                FINISH: begin
                    digest <= {
                        H0_INIT + a,
                        H1_INIT + b,
                        H2_INIT + c,
                        H3_INIT + d,
                        H4_INIT + e
                    };
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
