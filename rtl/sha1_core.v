// Ultra-compact Shift-Register SHA-1 Core (1 round/cycle, lockstep-ready)
// - Uses a 16-word shift register instead of an indexed ring buffer (zero 16:1 muxes)
// - Pre-adds (e + K + W) one cycle ahead to shorten the critical path
// - Compares against pre-subtracted adj_target (zero H_INIT adders)

module sha1_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         load,
    input  wire         run,
    input  wire [1:0]   round_sel,   // 0: 0..19, 1: 20..39, 2: 40..59, 3: 60..79
    input  wire [31:0]  k_next,      // sha1_k(t + 1)
    input  wire [319:0] base_hash,   // W[0..9] (shared across cores)
    input  wire [31:0]  w10_in,
    input  wire [31:0]  w11_in,
    input  wire [31:0]  w12_in,
    input  wire [15:0]  bit_len_in,
    input  wire [159:0] adj_target,  // target_hash - {H0..H4}_INIT
    output wire         match
);

    localparam [31:0] H0_INIT = 32'h67452301;
    localparam [31:0] H1_INIT = 32'hEFCDAB89;
    localparam [31:0] H2_INIT = 32'h98BADCFE;
    localparam [31:0] H3_INIT = 32'h10325476;
    localparam [31:0] H4_INIT = 32'hC3D2E1F0;
    localparam [31:0] K0      = 32'h5A827999;

    reg [31:0] w [0:15];
    reg [31:0] a, b, c, d, e_final;
    reg [31:0] e_plus_kw;

    function automatic [31:0] rotl32(input [31:0] x, input [4:0] n);
        begin
            rotl32 = (x << n) | (x >> (32 - n));
        end
    endfunction

    reg [31:0] f_val;
    always @(*) begin
        case (round_sel)
            2'd0:    f_val = (b & c) | ((~b) & d);
            2'd1:    f_val = b ^ c ^ d;
            2'd2:    f_val = (b & c) | (b & d) | (c & d);
            default: f_val = b ^ c ^ d;
        endcase
    end

    wire [31:0] wt_exp = rotl32(w[13] ^ w[8] ^ w[2] ^ w[0], 5'd1);
    wire [31:0] temp   = rotl32(a, 5'd5) + f_val + e_plus_kw;

    // Registered state compared directly against pre-subtracted target
    assign match = ({a, b, c, d, e_final} == adj_target);

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a         <= 32'd0;
            b         <= 32'd0;
            c         <= 32'd0;
            d         <= 32'd0;
            e_final   <= 32'd0;
            e_plus_kw <= 32'd0;
            for (i = 0; i < 16; i = i + 1) begin
                w[i] <= 32'd0;
            end
        end else if (load) begin
            for (i = 0; i < 10; i = i + 1) begin
                w[i] <= base_hash[319 - i*32 -: 32];
            end
            w[10] <= w10_in;
            w[11] <= w11_in;
            w[12] <= w12_in;
            w[13] <= 32'd0;
            w[14] <= 32'd0;
            w[15] <= {16'd0, bit_len_in};

            a         <= H0_INIT;
            b         <= H1_INIT;
            c         <= H2_INIT;
            d         <= H3_INIT;
            e_final   <= H4_INIT;
            e_plus_kw <= (H4_INIT + K0) + base_hash[319:288];
        end else if (run) begin
            a         <= temp;
            b         <= a;
            c         <= rotl32(b, 5'd30);
            d         <= c;
            e_final   <= d;
            e_plus_kw <= d + k_next + w[1];

            for (i = 0; i < 15; i = i + 1) begin
                w[i] <= w[i + 1];
            end
            w[15] <= wt_exp;
        end
    end

endmodule
