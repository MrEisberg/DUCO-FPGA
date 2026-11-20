// Synthesizable 2x-unrolled iterative SHA-1 core (2 rounds per clock cycle, 40 cycles)
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
    reg [31:0] kw0, kw1;

    function automatic [31:0] rotl32(input [31:0] x, input [4:0] n);
        begin
            rotl32 = (x << n) | (x >> (32 - n));
        end
    endfunction

    function automatic [31:0] sha1_f(
        input [6:0]  round_idx,
        input [31:0] bx,
        input [31:0] cx,
        input [31:0] dx
    );
        begin
            if (round_idx < 7'd20)
                sha1_f = (bx & cx) | ((~bx) & dx);
            else if (round_idx < 7'd40)
                sha1_f = bx ^ cx ^ dx;
            else if (round_idx < 7'd60)
                sha1_f = (bx & cx) | (bx & dx) | (cx & dx);
            else
                sha1_f = bx ^ cx ^ dx;
        end
    endfunction

    function automatic [31:0] sha1_k(input [6:0] round_idx);
        begin
            if (round_idx < 7'd20)
                sha1_k = 32'h5A827999;
            else if (round_idx < 7'd40)
                sha1_k = 32'h6ED9EBA1;
            else if (round_idx < 7'd60)
                sha1_k = 32'h8F1BBCDC;
            else
                sha1_k = 32'hCA62C1D6;
        end
    endfunction

    // Round t
    wire [3:0]  idx0     = t[3:0];
    wire [3:0]  idx0_m3  = idx0 - 4'd3;
    wire [3:0]  idx0_m8  = idx0 - 4'd8;
    wire [3:0]  idx0_m14 = idx0 - 4'd14;
    wire [31:0] wt0_exp  = rotl32(w[idx0_m3] ^ w[idx0_m8] ^ w[idx0_m14] ^ w[idx0], 5'd1);

    wire [31:0] temp0 = rotl32(a, 5'd5) + sha1_f(t, b, c, d) + e + kw0;
    wire [31:0] a1    = temp0;
    wire [31:0] b1    = a;
    wire [31:0] c1    = rotl32(b, 5'd30);
    wire [31:0] d1    = c;
    wire [31:0] e1    = d;

    // Round t + 1 (idx1 = idx0 + 1, which is distinct from idx0 so w[idx1] is unchanged by wt0_exp)
    wire [6:0]  t1       = t + 7'd1;
    wire [3:0]  idx1     = idx0 + 4'd1;
    wire [3:0]  idx1_m3  = idx1 - 4'd3;
    wire [3:0]  idx1_m8  = idx1 - 4'd8;
    wire [3:0]  idx1_m14 = idx1 - 4'd14;
    wire [31:0] wt1_exp  = rotl32(w[idx1_m3] ^ w[idx1_m8] ^ w[idx1_m14] ^ w[idx1], 5'd1);

    wire [31:0] temp1 = rotl32(a1, 5'd5) + sha1_f(t1, b1, c1, d1) + e1 + kw1;

    // Pre-add k + w for next cycle (t + 2, t + 3)
    wire [6:0]  t_next0 = t + 7'd2;
    wire [6:0]  t_next1 = t + 7'd3;
    wire [3:0]  idx_n0  = idx0 + 4'd2;
    wire [3:0]  idx_n1  = idx0 + 4'd3;
    wire [31:0] next_kw0 = sha1_k(t_next0) + w[idx_n0];
    wire [31:0] next_kw1 = sha1_k(t_next1) + w[idx_n1];
    wire [31:0] a2    = temp1;
    wire [31:0] b2    = a1;
    wire [31:0] c2    = rotl32(b1, 5'd30);
    wire [31:0] d2    = c1;
    wire [31:0] e2    = d1;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= IDLE;
            busy   <= 1'b0;
            done   <= 1'b0;
            t      <= 7'd0;
            digest <= 160'd0;
            a <= 32'd0; b <= 32'd0; c <= 32'd0; d <= 32'd0; e <= 32'd0;
            kw0 <= 32'd0; kw1 <= 32'd0;
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
                        kw0   <= 32'h5A827999 + block[511:480];
                        kw1   <= 32'h5A827999 + block[479:448];
                        busy  <= 1'b1;
                        state <= ROUNDS;
                    end
                end

                ROUNDS: begin
                    a <= a2;
                    b <= b2;
                    c <= c2;
                    d <= d2;
                    e <= e2;

                    w[idx0] <= wt0_exp;
                    w[idx1] <= wt1_exp;
                    kw0     <= next_kw0;
                    kw1     <= next_kw1;

                    if (t == 7'd78) begin
                        state <= FINISH;
                    end else begin
                        t <= t + 7'd2;
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
