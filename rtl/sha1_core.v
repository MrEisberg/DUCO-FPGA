// Synthesizable 1-round/cycle SHA-1 core with k + w[t] pre-addition (80 cycles)
// Optimized for high Fmax in 4-core Tang Nano 20K builds.

module sha1_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [511:0] block,
    output reg          busy,
    output reg          done,
    output reg  [159:0] digest
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
    reg [31:0] kw;

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

    wire [3:0]  idx0     = t[3:0];
    wire [3:0]  idx0_m3  = idx0 - 4'd3;
    wire [3:0]  idx0_m8  = idx0 - 4'd8;
    wire [3:0]  idx0_m14 = idx0 - 4'd14;
    wire [31:0] wt_exp   = rotl32(w[idx0_m3] ^ w[idx0_m8] ^ w[idx0_m14] ^ w[idx0], 5'd1);

    wire [31:0] temp = rotl32(a, 5'd5) + sha1_f(t, b, c, d) + e + kw;

    wire [6:0]  t_next  = t + 7'd1;
    wire [3:0]  idx_n   = idx0 + 4'd1;
    wire [31:0] next_kw = sha1_k(t_next) + w[idx_n];

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= IDLE;
            busy   <= 1'b0;
            done   <= 1'b0;
            t      <= 7'd0;
            digest <= 160'd0;
            a <= 32'd0; b <= 32'd0; c <= 32'd0; d <= 32'd0; e <= 32'd0;
            kw <= 32'd0;
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
                        kw    <= 32'h5A827999 + block[511:480];
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

                    w[idx0] <= wt_exp;
                    kw      <= next_kw;

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
