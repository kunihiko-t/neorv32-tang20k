module uart_probe (
    input  wire sys_clk,
    output reg  sys_tx = 1'b1,
    output wire sys_led
);
    // 27 MHz / 234 = 115384 baud (+0.16% from 115200).
    localparam integer CLKS_PER_BIT = 234;
    localparam integer GAP_CYCLES = 2700000; // 100 ms

    reg [7:0] baud_counter = 0;
    reg [3:0] bit_index = 0;
    reg [21:0] gap_counter = GAP_CYCLES;

    assign sys_led = sys_tx;

    always @(posedge sys_clk) begin
        if (gap_counter != 0) begin
            gap_counter <= gap_counter - 1'b1;
            sys_tx <= 1'b1;
        end else if (baud_counter != 0) begin
            baud_counter <= baud_counter - 1'b1;
        end else begin
            baud_counter <= CLKS_PER_BIT - 1;
            case (bit_index)
                0: begin sys_tx <= 1'b0; bit_index <= 1; end // start
                1: begin sys_tx <= 1'b1; bit_index <= 2; end // 0x55 bit 0
                2: begin sys_tx <= 1'b0; bit_index <= 3; end
                3: begin sys_tx <= 1'b1; bit_index <= 4; end
                4: begin sys_tx <= 1'b0; bit_index <= 5; end
                5: begin sys_tx <= 1'b1; bit_index <= 6; end
                6: begin sys_tx <= 1'b0; bit_index <= 7; end
                7: begin sys_tx <= 1'b1; bit_index <= 8; end
                8: begin sys_tx <= 1'b0; bit_index <= 9; end
                9: begin sys_tx <= 1'b1; bit_index <= 10; end // stop
                default: begin
                    sys_tx <= 1'b1;
                    bit_index <= 0;
                    gap_counter <= GAP_CYCLES;
                end
            endcase
        end
    end
endmodule
