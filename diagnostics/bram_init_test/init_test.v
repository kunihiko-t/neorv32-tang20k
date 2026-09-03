// BRAM INITの実機テスト: 1024x8 ROMを初期化し、内容をLEDで順番に表示する。
// INITがビットストリームに効いていればLEDがパターンを巡回し、
// 欠落していれば全LED消灯のままになる。
module init_test (
    input  wire       sys_clk,
    output wire [5:0] led
);
    reg [7:0] rom [0:1023];
    initial begin
        rom[0] = 8'h00; rom[1] = 8'h3F; rom[2] = 8'h00; rom[3] = 8'h15;
        rom[4] = 8'h00; rom[5] = 8'h3F; rom[6] = 8'h00; rom[7] = 8'h0A;
        rom[8] = 8'h2A; rom[9] = 8'h15; rom[10] = 8'h2A; rom[11] = 8'h15;
        rom[12] = 8'h3F; rom[13] = 8'h15; rom[14] = 8'h0A; rom[15] = 8'h15;
        // 16..1023 は暗黙に0
    end

    // 27MHz / 2^24 = 約1.6Hzでアドレスを進める
    reg [23:0] div = 0;
    reg [3:0] addr = 0;
    always @(posedge sys_clk) begin
        div <= div + 1;
        if (div == 24'hFFFFFF) begin
            addr <= addr + 1;
        end
    end

    // ROM読み出し (同期読み出しでBRAM推論を確定させる)
    reg [7:0] data = 0;
    always @(posedge sys_clk) data <= rom[addr];

    assign led = ~data[5:0];   // LEDは負論理
endmodule
