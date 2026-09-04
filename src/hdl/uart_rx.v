module uart_rx #(parameter CLOCK_HZ=27000000, parameter BAUD=19200)(
  input wire clk, rst, rx,
  output reg [7:0] data,
  output reg valid
);
  localparam integer BIT_TICKS = CLOCK_HZ / BAUD;
  localparam integer HALF_TICKS = BIT_TICKS / 2;
  localparam integer CNT_W = $clog2(BIT_TICKS);
  reg rx_s0, rx_s1;
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      rx_s0 <= 1'b1;
      rx_s1 <= 1'b1;
    end else begin
      rx_s0 <= rx;
      rx_s1 <= rx_s0;
    end
  end
  localparam [1:0] ST_IDLE = 2'd0, ST_START = 2'd1, ST_DATA = 2'd2, ST_STOP = 2'd3;
  reg [1:0] state;
  reg [CNT_W-1:0] cnt;
  reg [2:0] bit_idx;
  reg [7:0] shift;
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= ST_IDLE;
      cnt <= 0;
      bit_idx <= 0;
      shift <= 0;
      data <= 0;
      valid <= 0;
    end else begin
      valid <= 1'b0;
      case (state)
        ST_IDLE: begin
          cnt <= 0;
          bit_idx <= 0;
          if (rx_s1 == 1'b0) begin
            state <= ST_START;
            cnt <= 0;
          end
        end
        ST_START: begin
          if (cnt == HALF_TICKS-1) begin
            cnt <= 0;
            if (rx_s1 == 1'b0) state <= ST_DATA;
            else state <= ST_IDLE;
          end else cnt <= cnt + 1'b1;
        end
        ST_DATA: begin
          if (cnt == BIT_TICKS-1) begin
            cnt <= 0;
            shift[bit_idx] <= rx_s1;
            if (bit_idx == 3'd7) begin
              state <= ST_STOP;
              bit_idx <= 0;
            end else bit_idx <= bit_idx + 1'b1;
          end else cnt <= cnt + 1'b1;
        end
        ST_STOP: begin
          if (cnt == BIT_TICKS-1) begin
            cnt <= 0;
            state <= ST_IDLE;
            if (rx_s1 == 1'b1) begin
              data <= shift;
              valid <= 1'b1;
            end
          end else cnt <= cnt + 1'b1;
        end
        default: state <= ST_IDLE;
      endcase
    end
  end
endmodule
