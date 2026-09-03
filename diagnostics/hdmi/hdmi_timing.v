// 720x480p@60(CEA-861 VIC2)の走査信号。ピクセルクロックは27MHzを直接使う。
// 水平:表示720+前16+同期62+後60=858。垂直:表示480+前9+同期6+後30=525。
// 同期は負極性である。
module hdmi_timing (
    input  wire       pix_clk,
    input  wire       rst,
    output reg        hsync,
    output reg        vsync,
    output reg        de,
    output reg  [9:0] x,
    output reg  [9:0] y
);
    localparam H_ACTIVE = 720;
    localparam H_FRONT  = 16;
    localparam H_SYNC   = 62;
    localparam H_BACK   = 60;
    localparam H_TOTAL  = 858;
    localparam V_ACTIVE = 480;
    localparam V_FRONT  = 9;
    localparam V_SYNC   = 6;
    localparam V_BACK   = 30;
    localparam V_TOTAL  = 525;

    reg [9:0] cx;
    reg [9:0] cy;

    always @(posedge pix_clk) begin
        if (rst) begin
            cx <= 0;
            cy <= 0;
        end else if (cx == H_TOTAL - 1) begin
            cx <= 0;
            cy <= (cy == V_TOTAL - 1) ? 0 : cy + 1'b1;
        end else begin
            cx <= cx + 1'b1;
        end
    end

    always @(posedge pix_clk) begin
        if (rst) begin
            hsync <= 1'b1;
            vsync <= 1'b1;
            de    <= 1'b0;
            x     <= 0;
            y     <= 0;
        end else begin
            hsync <= ~((cx >= H_ACTIVE + H_FRONT) && (cx < H_ACTIVE + H_FRONT + H_SYNC));
            vsync <= ~((cy >= V_ACTIVE + V_FRONT) && (cy < V_ACTIVE + V_FRONT + V_SYNC));
            de    <= (cx < H_ACTIVE) && (cy < V_ACTIVE);
            x     <= (cx < H_ACTIVE) ? cx : 0;
            y     <= (cy < V_ACTIVE) ? cy : 0;
        end
    end
endmodule
