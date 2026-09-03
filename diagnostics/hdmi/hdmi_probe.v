// HDMI単体のカラーバー診断回路。CPUなしで720x480p@60を出す。
// ピクセル27MHz直結、直列135MHz、TMDSは自前エンコーダー+OSER10である。
module hdmi_probe (
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

    // PLL確定までリセットに保つ。高アクティブである。
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

    // 8色の縦縞。xの上位3ビットで帯を選ぶ。
    wire [2:0] bar = x[9:7] < 3'd7 ? x[9:7] + 3'd1 : 3'd0;
    wire [7:0] red   = {8{bar[0]}};
    wire [7:0] green = {8{bar[1]}};
    wire [7:0] blue  = {8{bar[2]}};

    // エンコーダーの1段パイプラインに走査信号をそろえる。
    reg hsync_d;
    reg vsync_d;
    reg de_d;
    always @(posedge sys_clk) begin
        hsync_d <= hsync_raw;
        vsync_d <= vsync_raw;
        de_d    <= de_raw;
    end

    wire [9:0] enc_r;
    wire [9:0] enc_g;
    wire [9:0] enc_b;

    tmds_encode enc0 (.pix_clk(sys_clk), .de(de_d), .ctl({vsync_d, hsync_d}), .din(blue), .dout(enc_b));
    tmds_encode enc1 (.pix_clk(sys_clk), .de(de_d), .ctl({vsync_d, hsync_d}), .din(green), .dout(enc_g));
    tmds_encode enc2 (.pix_clk(sys_clk), .de(de_d), .ctl({vsync_d, hsync_d}), .din(red), .dout(enc_r));

    // DVIクロック信号は10'b0000011111の固定符号である。
    wire [9:0] enc_clk = 10'b0000011111;

    wire ser_b;
    wire ser_g;
    wire ser_r;
    wire ser_c;
    wire ser_nb;
    wire ser_ng;
    wire ser_nr;
    wire ser_nc;

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

    // LED並び調査用の固定パターン(LEDは負論理、0で点灯)。
    // order_led[0..5]がピン15..20に対応する。
    assign order_led = 6'b101010;
endmodule
