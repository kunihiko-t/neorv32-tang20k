// 64x30 cells, 8x8 font doubled vertically, centered in 720x480 video.
// Character RAM and font ROM each have one synchronous read stage.
module text_pixels(
 input wire clk, rst, input wire [9:0] x,y,
 input wire de,hsync,vsync, input wire [7:0] char_data,
 output wire [5:0] rd_col, output wire [4:0] rd_row,
 output wire [7:0] red,green,blue,
 output wire de_out,hsync_out,vsync_out
);
 `include "font_init.vh"
 wire [9:0] text_x=x-10'd104;
 assign rd_col=text_x[8:3];
 assign rd_row=y[8:4];
 reg [2:0] bit_s1,bit_s2,font_row_s1;
 reg inside_s1,inside_s2;
 reg [2:0] control_s1,control_s2;
 reg [7:0] glyph;
 always @(posedge clk) begin
  bit_s1 <= x[2:0];
  bit_s2 <= bit_s1;
  font_row_s1 <= y[3:1];
  if(rst) begin
   inside_s1<=0; inside_s2<=0;
   control_s1<=3'b011; control_s2<=3'b011;
  end else begin
   inside_s1<=de && x>=104 && x<616 && y<480;
   inside_s2<=inside_s1;
   control_s1<={de,hsync,vsync};
   control_s2<=control_s1;
  end
 end
 always @(posedge clk) glyph <= font[{char_data[6:0],font_row_s1}];
 wire ink=inside_s2 && glyph[bit_s2];
 assign red=ink ? 8'he0 : 8'h10;
 assign green=ink ? 8'he0 : 8'h10;
 assign blue=ink ? 8'hff : 8'h30;
 assign {de_out,hsync_out,vsync_out}=control_s2;
endmodule
