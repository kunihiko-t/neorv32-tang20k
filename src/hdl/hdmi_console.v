// Mirror the CPU's existing UART TX internally; no new MiniOS device driver.
module hdmi_console(
 input wire sys_clk,cpu_reset_n,uart_tx,
 output wire tmds_clk_p,tmds_clk_n,
 output wire [2:0] tmds_data_p,tmds_data_n
);
 wire serial_clk,locked;
 video_pll pll(.sys_clk(sys_clk),.serial_clk(serial_clk),.locked(locked));
 reg [23:0] settle=0;
 always @(posedge sys_clk)
  if(!locked) settle<=0;
  else if(!settle[23]) settle<=settle+1'b1;
 wire video_rst=!locked || !settle[23];
 reg [1:0] reset_sync=0;
 always @(posedge sys_clk or negedge cpu_reset_n)
  if(!cpu_reset_n) reset_sync<=0;
  else reset_sync<={reset_sync[0],1'b1};
 wire text_rst=video_rst || !reset_sync[1];

 wire [7:0] byte_data,char_data;
 wire byte_valid,ready;
 wire [5:0] col;
 wire [4:0] row;
 uart_rx receiver(.clk(sys_clk),.rst(text_rst),.rx(uart_tx),.data(byte_data),.valid(byte_valid));
 terminal_buffer terminal(.clk(sys_clk),.rst(text_rst),.char_data(byte_data),
  .char_valid(byte_valid && ready),.ready(ready),.rd_col(col),.rd_row(row),
  .rd_data(char_data),.cursor_col(),.cursor_row());

 wire [9:0] x,y;
 wire hs,vs,de;
 hdmi_timing timing(.pix_clk(sys_clk),.rst(video_rst),.hsync(hs),.vsync(vs),.de(de),.x(x),.y(y));
 wire [7:0] red,green,blue;
 wire hs_out,vs_out,de_out;
 text_pixels pixels(.clk(sys_clk),.rst(video_rst),.x(x),.y(y),.de(de),.hsync(hs),.vsync(vs),
  .char_data(ready ? char_data : 8'h20),.rd_col(col),.rd_row(row),
  .red(red),.green(green),.blue(blue),.de_out(de_out),.hsync_out(hs_out),.vsync_out(vs_out));

 wire [9:0] encoded[0:3];
 tmds_encode enc_b(.pix_clk(sys_clk),.de(de_out),.ctl({vs_out,hs_out}),.din(blue),.dout(encoded[0]));
 tmds_encode enc_g(.pix_clk(sys_clk),.de(de_out),.ctl(2'b00),.din(green),.dout(encoded[1]));
 tmds_encode enc_r(.pix_clk(sys_clk),.de(de_out),.ctl(2'b00),.din(red),.dout(encoded[2]));
 assign encoded[3]=10'b0000011111;
 wire [3:0] serial;
 genvar channel;
 generate for(channel=0;channel<4;channel=channel+1) begin: serializers
  OSER10 oser(.D0(encoded[channel][0]),.D1(encoded[channel][1]),.D2(encoded[channel][2]),
   .D3(encoded[channel][3]),.D4(encoded[channel][4]),.D5(encoded[channel][5]),
   .D6(encoded[channel][6]),.D7(encoded[channel][7]),.D8(encoded[channel][8]),.D9(encoded[channel][9]),
   .PCLK(sys_clk),.FCLK(serial_clk),.RESET(video_rst),.Q(serial[channel]));
 end endgenerate
 TLVDS_OBUF out_b(.I(serial[0]),.O(tmds_data_p[0]),.OB(tmds_data_n[0]));
 TLVDS_OBUF out_g(.I(serial[1]),.O(tmds_data_p[1]),.OB(tmds_data_n[1]));
 TLVDS_OBUF out_r(.I(serial[2]),.O(tmds_data_p[2]),.OB(tmds_data_n[2]));
 TLVDS_OBUF out_c(.I(serial[3]),.O(tmds_clk_p),.OB(tmds_clk_n));
endmodule
