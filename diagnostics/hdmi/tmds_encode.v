// DVI互換のTMDS 8b/10bエンコーダー。映像期間と制御期間の両方を出す。
// DVI仕様のFigure 3-5に沿った自前実装である。
module tmds_encode (
    input  wire       pix_clk,
    input  wire       de,
    input  wire [1:0] ctl,
    input  wire [7:0] din,
    output reg  [9:0] dout
);
    // 制御期間の固定符号。{vsync, hsync}の順である。
    function [9:0] ctl_token(input [1:0] c);
        case (c)
            2'b00:   ctl_token = 10'b1101010100;
            2'b01:   ctl_token = 10'b0010101011;
            2'b10:   ctl_token = 10'b0101010100;
            default: ctl_token = 10'b1010101011;
        endcase
    endfunction

    function [3:0] pop4(input [7:0] v);
        pop4 = v[0] + v[1] + v[2] + v[3] + v[4] + v[5] + v[6] + v[7];
    endfunction

    reg [8:0] q_m;
    reg [3:0] n1d;
    reg [3:0] n1q;
    reg signed [4:0] cnt;
    integer i;

    // 第一段:XOR/XNOR鎖。組み合わせ回路である。
    always @(*) begin
        n1d = pop4(din);
        q_m[0] = din[0];
        if (n1d > 4 || (n1d == 4 && din[0] == 1'b0)) begin
            for (i = 1; i < 8; i = i + 1)
                q_m[i] = ~(q_m[i - 1] ^ din[i]);
            q_m[8] = 1'b0;
        end else begin
            for (i = 1; i < 8; i = i + 1)
                q_m[i] = q_m[i - 1] ^ din[i];
            q_m[8] = 1'b1;
        end
        n1q = pop4(q_m[7:0]);
    end

    wire [3:0] n0q = 8 - n1q;

    // 第二段:直流平衡。レジスター出力である。
    always @(posedge pix_clk) begin
        if (!de) begin
            cnt  <= 0;
            dout <= ctl_token(ctl);
        end else if (cnt == 0 || n1q == 4) begin
            dout[9]   <= ~q_m[8];
            dout[8]   <= q_m[8];
            dout[7:0] <= q_m[8] ? q_m[7:0] : ~q_m[7:0];
            if (q_m[8])
                cnt <= cnt + $signed({1'b0, n1q}) - $signed({1'b0, n0q});
            else
                cnt <= cnt + $signed({1'b0, n0q}) - $signed({1'b0, n1q});
        end else if ((cnt > 0 && n1q > 4) || (cnt < 0 && n0q > 4)) begin
            dout[9]   <= 1'b1;
            dout[8]   <= q_m[8];
            dout[7:0] <= ~q_m[7:0];
            cnt <= cnt + ($signed({1'b0, q_m[8], 1'b0})) + $signed({1'b0, n0q}) - $signed({1'b0, n1q});
        end else begin
            dout[9]   <= 1'b0;
            dout[8]   <= q_m[8];
            dout[7:0] <= q_m[7:0];
            cnt <= cnt - ($signed({1'b0, ~q_m[8], 1'b0})) - $signed({1'b0, n0q}) + $signed({1'b0, n1q});
        end
    end
endmodule
