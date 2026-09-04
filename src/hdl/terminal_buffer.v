module terminal_buffer(
  input wire clk, rst,
  input wire [7:0] char_data,
  input wire char_valid,
  output wire ready,
  input wire [5:0] rd_col,
  input wire [4:0] rd_row,
  output reg [7:0] rd_data,
  output wire [5:0] cursor_col,
  output wire [4:0] cursor_row
);
  reg [7:0] mem [0:2047];
  reg [4:0] top_row;
  reg [4:0] cur_row;
  reg [5:0] cur_col;
  reg wrap_pending;
  localparam [1:0] ST_IDLE = 2'd0, ST_RST = 2'd1, ST_ROW = 2'd2;
  reg [1:0] state;
  reg [10:0] rst_cnt;
  reg [5:0] clr_cnt;
  reg [4:0] clr_row;
  reg [7:0] stored_char;
  reg stored_has_char;
  reg wr_en;
  reg [10:0] wr_addr;
  reg [7:0] wr_data;
  // preserve all 5 row bits and 6 col bits, no 12-bit truncation
  wire [4:0] rd_phys = top_row + rd_row;
  wire [10:0] rd_addr = {rd_phys, rd_col};
  wire [4:0] cur_phys = top_row + cur_row;
  wire [4:0] next_phys = top_row + (cur_row + 5'd1);
  wire [4:0] scroll_phys = top_row + 5'd30;
  wire [10:0] cur_waddr = {cur_phys, cur_col};
  wire [10:0] next_waddr = {next_phys, 6'd0};
  assign ready = (state == ST_IDLE);
  assign cursor_col = cur_col;
  assign cursor_row = cur_row;
  always @(posedge clk) begin
    rd_data <= mem[rd_addr];
  end
  always @(posedge clk) begin
    if (wr_en) mem[wr_addr] <= wr_data;
  end
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= ST_RST;
      top_row <= 5'd0;
      cur_row <= 5'd0;
      cur_col <= 6'd0;
      wrap_pending <= 1'b0;
      rst_cnt <= 11'd0;
      clr_cnt <= 6'd0;
      clr_row <= 5'd0;
      stored_char <= 8'd0;
      stored_has_char <= 1'b0;
      wr_en <= 1'b0;
      wr_addr <= 11'd0;
      wr_data <= 8'h20;
    end else begin
      case (state)
        ST_RST: begin
          wr_en <= 1'b1;
          wr_addr <= rst_cnt;
          wr_data <= 8'h20;
          if (rst_cnt == 11'd2047) begin
            state <= ST_IDLE;
          end else begin
            rst_cnt <= rst_cnt + 11'd1;
          end
        end
        ST_ROW: begin
          wr_en <= 1'b1;
          if (stored_has_char) begin
            if (clr_cnt == 6'd0) begin
              wr_addr <= {clr_row, 6'd0};
              wr_data <= stored_char;
            end else begin
              wr_addr <= {clr_row, clr_cnt};
              wr_data <= 8'h20;
            end
          end else begin
            wr_addr <= {clr_row, clr_cnt};
            wr_data <= 8'h20;
          end
          if (clr_cnt == 6'd63) begin
            top_row <= top_row + 5'd1;
            cur_row <= 5'd29;
            if (stored_has_char) cur_col <= 6'd1;
            else cur_col <= 6'd0;
            wrap_pending <= 1'b0;
            state <= ST_IDLE;
          end else begin
            clr_cnt <= clr_cnt + 6'd1;
          end
        end
        ST_IDLE: begin
          wr_en <= 1'b0;
          if (char_valid) begin
            if (char_data == 8'h08) begin
              if (wrap_pending) begin
                wrap_pending <= 1'b0;
              end else if (cur_col != 6'd0) begin
                cur_col <= cur_col - 6'd1;
              end else if (cur_row != 5'd0) begin
                cur_row <= cur_row - 5'd1;
                cur_col <= 6'd63;
              end
            end else if (char_data == 8'h0D) begin
              cur_col <= 6'd0;
              wrap_pending <= 1'b0;
            end else if (char_data == 8'h0A) begin
              wrap_pending <= 1'b0;
              if (cur_row == 5'd29) begin
                clr_row <= scroll_phys;
                clr_cnt <= 6'd0;
                stored_has_char <= 1'b0;
                state <= ST_ROW;
              end else begin
                cur_row <= cur_row + 5'd1;
                cur_col <= 6'd0;
              end
            end else if (char_data >= 8'h20 && char_data <= 8'h7E) begin
              if (wrap_pending) begin
                wrap_pending <= 1'b0;
                if (cur_row == 5'd29) begin
                  clr_row <= scroll_phys;
                  clr_cnt <= 6'd0;
                  stored_char <= char_data;
                  stored_has_char <= 1'b1;
                  state <= ST_ROW;
                end else begin
                  wr_en <= 1'b1;
                  wr_addr <= next_waddr;
                  wr_data <= char_data;
                  cur_row <= cur_row + 5'd1;
                  cur_col <= 6'd1;
                end
              end else begin
                wr_en <= 1'b1;
                wr_addr <= cur_waddr;
                wr_data <= char_data;
                if (cur_col == 6'd63) begin
                  wrap_pending <= 1'b1;
                end else begin
                  cur_col <= cur_col + 6'd1;
                end
              end
            end
          end
        end
        default: state <= ST_IDLE;
      endcase
    end
  end
endmodule
