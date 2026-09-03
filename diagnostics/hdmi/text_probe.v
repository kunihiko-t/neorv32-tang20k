// 段階2(改): 単体テキスト表示。64桁x30行 (8x16文字) を720x480p60の中央512x480に出す。
// vramは2048x8で単一BRAMセルに収める (複数セルINIT/折り返しバグの回避)。
// フォントは8x8を縦2倍で16pxに引き伸ばす。bit0=左端ピクセル。
module text_probe (
    input  wire       sys_clk,
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_data_p,
    output wire [2:0] tmds_data_n,
    output wire [5:0] order_led
);
    wire serial_clk;
    wire pll_locked;

    video_pll vco (
        .sys_clk(sys_clk),
        .serial_clk(serial_clk),
        .locked(pll_locked)
    );

    reg [23:0] settle = 0;
    wire rst = ~pll_locked || !settle[23];
    always @(posedge sys_clk) begin
        if (!pll_locked)
            settle <= 0;
        else if (!settle[23])
            settle <= settle + 1'b1;
    end

    wire hsync_raw;
    wire vsync_raw;
    wire de_raw;
    wire [9:0] x;
    wire [9:0] y;

    hdmi_timing timing (
        .pix_clk(sys_clk),
        .rst(rst),
        .hsync(hsync_raw),
        .vsync(vsync_raw),
        .de(de_raw),
        .x(x),
        .y(y)
    );

    `include "font_init.vh"
    `include "text_init.vh"

    // ---- 描画パイプライン (BRAM同期読み出しx2、各1サイクル) ----
    // テキスト領域: 104 <= x < 616 (512px = 64桁)。480 = 30行 x 16px。
    reg [9:0] x_s1, x_s2, x_s3;
    reg [9:0] y_s1, y_s2, y_s3;
    reg       in_s1, in_s2, in_s3;

    wire in_text_0 = (x >= 10'd104) && (x < 10'd616);

    always @(posedge sys_clk) begin
        x_s1  <= x;    x_s2  <= x_s1;  x_s3  <= x_s2;
        y_s1  <= y;    y_s2  <= y_s1;  y_s3  <= y_s2;
        in_s1 <= de_raw && in_text_0;  in_s2 <= in_s1;  in_s3 <= in_s2;
    end

    // s1: 文字アドレス → 次サイクルにcharcode
    wire [10:0] vram_addr = {y_s1[8:4], x_s1[9:3] - 4'd13};
    reg  [7:0]  charcode;
    always @(posedge sys_clk) charcode <= vram[vram_addr[10:0]];

    // s2: フォント行 → 次サイクルにglyph (y[3:1]: 8pxフォント行を2走査線で重ねる)
    wire [9:0] font_addr = {charcode[6:0], y_s2[3:1]};
    reg  [7:0] glyph;
    always @(posedge sys_clk) glyph <= font[font_addr];

    // s3: 画素確定 (x_s3[2:0]=桁内ピクセル)
    wire pixel = glyph[x_s3[2:0]];

    // 配色: 白文字/紺背景、上下の罫線行はシアン、テキスト領域外は濃紺。
    wire rule_row = (y_s3[8:4] == 5'd0) || (y_s3[8:4] == 5'd29);
    wire [7:0] red   = (in_s3 & pixel) ? (rule_row ? 8'h00 : 8'hE0) : 8'h10;
    wire [7:0] green = (in_s3 & pixel) ? (rule_row ? 8'hD0 : 8'hE0) : 8'h10;
    wire [7:0] blue  = (in_s3 & pixel) ? (rule_row ? 8'hD0 : 8'hFF) : 8'h30;

    // エンコーダーへ。hdmi_probeと同じ相対位置関係 (dinがde比で1段先行) に合わせ、
    // in_s3をもう1段遅らせたde_dと組にする。
    reg hsync_d, vsync_d, de_d;
    always @(posedge sys_clk) begin
        hsync_d <= hsync_raw;
        vsync_d <= vsync_raw;
        de_d    <= in_s3;
    end

    wire [9:0] enc_r, enc_g, enc_b;
    tmds_encode enc0 (.pix_clk(sys_clk), .de(de_d), .ctl({vsync_d, hsync_d}), .din(blue),  .dout(enc_b));
    tmds_encode enc1 (.pix_clk(sys_clk), .de(de_d), .ctl({vsync_d, hsync_d}), .din(green), .dout(enc_g));
    tmds_encode enc2 (.pix_clk(sys_clk), .de(de_d), .ctl({vsync_d, hsync_d}), .din(red),   .dout(enc_r));

    wire [9:0] enc_clk = 10'b0000011111;

    wire ser_b, ser_g, ser_r, ser_c;

    OSER10 oser_b (.D0(enc_b[0]), .D1(enc_b[1]), .D2(enc_b[2]), .D3(enc_b[3]), .D4(enc_b[4]),
        .D5(enc_b[5]), .D6(enc_b[6]), .D7(enc_b[7]), .D8(enc_b[8]), .D9(enc_b[9]),
        .PCLK(sys_clk), .FCLK(serial_clk), .RESET(rst), .Q(ser_b));
    OSER10 oser_g (.D0(enc_g[0]), .D1(enc_g[1]), .D2(enc_g[2]), .D3(enc_g[3]), .D4(enc_g[4]),
        .D5(enc_g[5]), .D6(enc_g[6]), .D7(enc_g[7]), .D8(enc_g[8]), .D9(enc_g[9]),
        .PCLK(sys_clk), .FCLK(serial_clk), .RESET(rst), .Q(ser_g));
    OSER10 oser_r (.D0(enc_r[0]), .D1(enc_r[1]), .D2(enc_r[2]), .D3(enc_r[3]), .D4(enc_r[4]),
        .D5(enc_r[5]), .D6(enc_r[6]), .D7(enc_r[7]), .D8(enc_r[8]), .D9(enc_r[9]),
        .PCLK(sys_clk), .FCLK(serial_clk), .RESET(rst), .Q(ser_r));
    OSER10 oser_c (.D0(enc_clk[0]), .D1(enc_clk[1]), .D2(enc_clk[2]), .D3(enc_clk[3]), .D4(enc_clk[4]),
        .D5(enc_clk[5]), .D6(enc_clk[6]), .D7(enc_clk[7]), .D8(enc_clk[8]), .D9(enc_clk[9]),
        .PCLK(sys_clk), .FCLK(serial_clk), .RESET(rst), .Q(ser_c));

    TLVDS_OBUF obuf_b (.I(ser_b), .O(tmds_data_p[0]), .OB(tmds_data_n[0]));
    TLVDS_OBUF obuf_g (.I(ser_g), .O(tmds_data_p[1]), .OB(tmds_data_n[1]));
    TLVDS_OBUF obuf_r (.I(ser_r), .O(tmds_data_p[2]), .OB(tmds_data_n[2]));
    TLVDS_OBUF obuf_c (.I(ser_c), .O(tmds_clk_p), .OB(tmds_clk_n));

    assign order_led = 6'b111110;
endmodule
