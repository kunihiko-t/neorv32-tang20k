`timescale 1ns/1ps
module text_pixels_tb;
 reg clk=0;
 always #5 clk=~clk;
 reg rst=1, de=0,hsync=1,vsync=1;
 reg [9:0] x=0,y=0;
 wire [5:0] col;
 wire [4:0] row;
 reg [7:0] char_data;
 wire [7:0] red,green,blue;
 wire de_out,hsync_out,vsync_out;
 integer scan;
 reg [2:0] expected_control;
 reg expected_ink;
 text_pixels dut(clk,rst,x,y,de,hsync,vsync,char_data,col,row,red,green,blue,de_out,hsync_out,vsync_out);
 // Same one-cycle read contract as the real terminal BRAM.
 always @(posedge clk)
  if(row==0 && col==0) char_data <= "A";
  else if(row==16 && col==0) char_data <= "B";
  else if(row==29 && col==63) char_data <= "B";
  else char_data <= " ";
 task pixel(input [9:0] px,py,input active,h,v,input ink);
 begin
  @(negedge clk); x=px;y=py;de=active;hsync=h;vsync=v;
  repeat(2) @(posedge clk);
  #1;
  if({de_out,hsync_out,vsync_out} !== {active,h,v}) $fatal(1,"sync alignment at %0d,%0d",px,py);
  if(ink && {red,green,blue} !== 24'he0e0ff) $fatal(1,"missing glyph at %0d,%0d: %h",px,py,{red,green,blue});
  if(!ink && {red,green,blue} !== 24'h101030) $fatal(1,"expected background at %0d,%0d",px,py);
 end
 endtask
 initial begin
  repeat(3) @(negedge clk); rst=0;
  pixel(104,0,1,1,1,0); // A row0=0x0c, leftmost pixel is clear.
  pixel(106,0,1,1,1,1);
  pixel(106,1,1,1,1,1); // Font is doubled vertically.
  pixel(104,256,1,1,1,1); // B bit0 is set; A bit0 is clear. Catch row aliasing.
  pixel(611,464,1,1,1,1); // Last column/row, B row0=0x3f.
  if(col!==63 || row!==29) $fatal(1,"last cell address truncated");
  pixel(616,0,1,1,1,0); // Border is active video, not a blanking period.
  pixel(0,0,1,1,1,0);
  pixel(106,0,0,0,1,0);
  pixel(106,0,0,1,0,0);
  // Change character, coordinates and controls every cycle: a held-pixel
  // test alone would not detect a one-cycle pipeline mismatch.
  for(scan=0;scan<64;scan=scan+1) begin
   @(negedge clk);
   x=100+scan; y=scan[0] ? 256 : 0;
   de=(scan%7)!=0; hsync=scan[1]; vsync=scan[2];
   @(posedge clk); #1;
   if(scan>0) begin
    if({de_out,hsync_out,vsync_out} !== expected_control)
     $fatal(1,"stream control pipeline at step %0d",scan);
    if({red,green,blue} !== (expected_ink ? 24'he0e0ff : 24'h101030))
     $fatal(1,"stream glyph pipeline at step %0d",scan);
   end
   expected_control={de,hsync,vsync};
   expected_ink=de && (y==0 ? (x==106 || x==107) : (x>=104 && x<=109));
  end
  $display("PASS text pixel addresses, font and control alignment"); $finish;
 end
endmodule
