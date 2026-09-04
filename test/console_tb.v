`timescale 1ns/1ps
module tb_console;
 reg clk=0;
 always #5 clk=~clk;
 reg rst=1, rx=1;
 wire [7:0] data;
 wire valid;
 uart_rx #(.CLOCK_HZ(160),.BAUD(10)) uart(clk,rst,rx,data,valid);
 reg [7:0] char_data=0;
 reg char_valid=0;
 reg link_uart=0;
 wire ready;
 reg [5:0] rd_col=0;
 reg [4:0] rd_row=0;
 wire [7:0] rd_data;
 wire [5:0] cursor_col;
 wire [4:0] cursor_row;
 terminal_buffer term(clk,rst,link_uart ? data : char_data,
  link_uart ? (valid && ready) : char_valid,ready,rd_col,rd_row,rd_data,cursor_col,cursor_row);
 integer errors=0, received=0, i;
 reg [7:0] last_data;
 reg [7:0] first_data;
 always @(posedge clk) if(valid) begin
  if(received==0) first_data=data;
  received=received+1; last_data=data;
 end
 task check(input condition, input [511:0] label);
 begin if(condition !== 1'b1) begin errors=errors+1; $display("FAIL %0s",label); end end
 endtask
 task reset_all;
 begin
  @(negedge clk); rst=1; char_valid=0; rx=1;
  repeat(4) @(negedge clk);
  rst=0;
  repeat(2100) @(negedge clk);
  check(ready,"reset clearing finishes");
 end
 endtask
 task frame(input [7:0] b,input stop_bit);
 integer bit_index;
 begin
  rx=0; repeat(16) @(negedge clk);
  for(bit_index=0;bit_index<8;bit_index=bit_index+1) begin
   rx=b[bit_index]; repeat(16) @(negedge clk);
  end
  rx=stop_bit; repeat(16) @(negedge clk);
 end
 endtask
 task put(input [7:0] b);
 begin
  while(!ready) @(negedge clk);
  char_data=b; char_valid=1;
  @(negedge clk); char_valid=0;
  @(negedge clk);
  while(!ready) @(negedge clk);
 end
 endtask
 task cell_is(input [4:0] row,input [5:0] col,input [7:0] expected);
 begin
  @(negedge clk); rd_row=row; rd_col=col;
  @(posedge clk); #1;
  if(rd_data !== expected) begin errors=errors+1; $display("FAIL cell[%0d,%0d] got=%02x want=%02x",row,col,rd_data,expected); end
  @(negedge clk);
 end
 endtask
 initial begin
  reset_all;
  frame(8'ha5,1); frame(8'h3c,1); rx=1; repeat(32) @(negedge clk);
  check(received==2 && first_data==8'ha5 && last_data==8'h3c,"UART back-to-back bytes and valid pulse");
  frame(8'h12,0); rx=1; repeat(32) @(negedge clk);
  check(received==2,"UART rejects bad stop bit");
  rx=0; repeat(3) @(negedge clk); rx=1; repeat(32) @(negedge clk);
  check(received==2,"UART rejects short start glitch");
  cell_is(0,0,8'h20); cell_is(29,63,8'h20);
  put("A"); put("B"); put(8'h08); put(" "); put(8'h08);
  cell_is(0,0,"A"); cell_is(0,1," ");
  check(cursor_col==1 && cursor_row==0,"backspace-space-backspace cursor");
  put(8'h0d); put("Z"); put(8'h0a); put("C");
  cell_is(0,0,"Z"); cell_is(1,0,"C");
  reset_all;
  for(i=0;i<64;i=i+1) put("A");
  put("B"); cell_is(0,63,"A"); cell_is(1,0,"B");
  check(cursor_col==1 && cursor_row==1,"wrap after column63");
  reset_all;
  for(i=0;i<64;i=i+1) put("A");
  put(8'h08); put(" "); put(8'h08);
  cell_is(0,62,"A"); cell_is(0,63," ");
  check(cursor_col==63 && cursor_row==0,"erase last cell while delayed wrap pending");
  reset_all;
  for(i=0;i<64;i=i+1) put("A");
  put(8'h0a); put("X");
  cell_is(1,0,"X");
  check(cursor_row==1 && cursor_col==1,"64 columns then LF advances only once");
  reset_all;
  for(i=0;i<35;i=i+1) begin
   if(i!=0) put(8'h0a);
   put(8'h41+(i%26));
  end
  cell_is(0,0,"F"); cell_is(29,0,"I"); cell_is(29,1," ");
  for(i=35;i<80;i=i+1) begin put(8'h0a); put(8'h41+(i%26)); end
  cell_is(0,0,"Y"); cell_is(29,0,"B"); cell_is(29,63," ");
  check(cursor_row==29 && cursor_col==1,"scroll and row-ring wrap cursor");
  reset_all;
  link_uart=1;
  frame("H",1); frame("i",1); rx=1; repeat(32) @(negedge clk);
  cell_is(0,0,"H"); cell_is(0,1,"i");
  check(cursor_col==2 && cursor_row==0,"UART-to-terminal integration");
  if(errors) $fatal(1,"%0d checks failed",errors);
  $display("PASS UART and text buffer behavior"); $finish;
 end
 initial begin #10000000; $fatal(1,"test timed out"); end
endmodule
