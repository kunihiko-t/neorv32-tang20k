library ieee;
use ieee.std_logic_1164.all;

entity BTNReset_tb is
end;

architecture test of BTNReset_tb is
    signal clk: std_logic := '0';
    signal arstn_i: std_logic := '1';
    signal rstn_o: std_logic;
begin
    clk <= not clk after 5 ns;

    dut: entity work.BTNReset
        generic map (
            DEBOUNCE_CYCLES => 3
        )
        port map (
            clk => clk,
            arstn_i => arstn_i,
            rstn_o => rstn_o
        );

    stimulus: process
    begin
        wait for 0 ns;
        assert rstn_o = '0'
            report "reset must be asserted at FPGA configuration"
            severity failure;

        wait for 60 ns;
        assert rstn_o = '1'
            report "reset must deassert after the input is stable"
            severity failure;

        arstn_i <= '0';
        wait for 60 ns;
        assert rstn_o = '0'
            report "reset must assert after a stable button press"
            severity failure;

        report "BTNReset_tb passed" severity note;
        wait;
    end process;
end;
