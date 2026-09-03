// 2セルBRAMのINITマッピングテスト: 4096x8 (2ブロック分)。
// 前半アドレス=右回り巡回パターン、後半=別パターン。
// どちらかのブロックが化ければ、巡回の途中でパターンが壊れる。
module multi_test (
    input  wire       sys_clk,
    output wire [5:0] led
);
    reg [7:0] rom [0:4095];
    integer i;
    initial begin
        for (i = 0; i < 2048; i = i + 1)
            rom[i]      = (i % 2 == 0) ? 8'h3F : 8'h15;   // 前半: 全点灯/交互
        for (i = 2048; i < 4096; i = i + 1)
            rom[i]      = (i % 2 == 0) ? 8'h0A : 8'h2A;   // 後半: 逆交互
    end

    reg [15:0] div = 0;
    reg [11:0] addr = 0;
    always @(posedge sys_clk) begin
        div <= div + 1;
        if (div == 16'hFFFF) addr <= addr + 1;
    end

    reg [7:0] data = 0;
    always @(posedge sys_clk) data <= rom[addr];

    assign led = ~data[5:0];
endmodule
