// 27MHzから135MHzの直列クロックを作る。480pはピクセル側を27MHz直接で使う。
// 分周設定はTang Nano 20Kの480p実績値である。
module video_pll (
    input  wire sys_clk,
    output wire serial_clk,
    output wire locked
);
    rPLL #(
        .DEVICE("GW2AR-18C"),
        .FCLKIN("27"),
        .IDIV_SEL(0),
        .FBDIV_SEL(4),
        .ODIV_SEL(4),
        .DYN_ODIV_SEL("false"),
        .DYN_FBDIV_SEL("false"),
        .DYN_IDIV_SEL("false"),
        .PSDA_SEL("0000"),
        .DYN_DA_EN("true"),
        .DUTYDA_SEL("1000"),
        .CLKOUT_FT_DIR(1'b1),
        .CLKOUTP_FT_DIR(1'b1),
        .CLKOUT_DLY_STEP(0),
        .CLKOUTP_DLY_STEP(0),
        .CLKFB_SEL("internal"),
        .CLKOUT_BYPASS("false"),
        .CLKOUTP_BYPASS("false"),
        .CLKOUTD_BYPASS("false"),
        .DYN_SDIV_SEL(2),
        .CLKOUTD_SRC("CLKOUT"),
        .CLKOUTD3_SRC("CLKOUT")
    ) pll (
        .CLKOUT(serial_clk),
        .LOCK(locked),
        .CLKOUTP(),
        .CLKOUTD(),
        .CLKOUTD3(),
        .RESET(1'b0),
        .RESET_P(1'b0),
        .CLKIN(sys_clk),
        .CLKFB(1'b0),
        .FBDSEL(6'b00000),
        .IDSEL(6'b00000),
        .ODSEL(6'b0),
        .PSDA(4'b0),
        .DUTYDA(4'b0),
        .FDLY(4'b0)
    );
endmodule
