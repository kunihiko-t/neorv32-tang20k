library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

library neorv32;
use neorv32.neorv32_package.all;

entity top is
    port (
        sys_clk: in std_logic;
        key1, key2: in std_logic;
        sys_led: out std_logic_vector(5 downto 0);
        sys_tx: out std_logic;
        sys_rx: in std_logic;
        sys_tms: in std_logic;
        sys_tck: in std_logic;
        sys_tdi: in std_logic;
        sys_tdo: out std_logic;
        mspi_do: in std_logic;
        mspi_di: out std_logic;
        mspi_cs: out std_logic;
        mspi_clk: out std_logic;
        mspi_wp: out std_logic;
        tmds_clk_p, tmds_clk_n: out std_logic;
        tmds_data_p, tmds_data_n: out std_logic_vector(2 downto 0)
    );
end;

architecture impl of top is
    constant STARTUP_CYCLES: integer := 480_000_000;

    signal clk, rstn, pll_locked: std_logic;

    signal arstn_btn: std_logic;
    signal rstn_btn: std_logic;
    signal startup_done: std_logic := '0';
    signal startup_counter: integer range 0 to STARTUP_CYCLES := 0;
    signal rstn_wdt_o: std_ulogic;
    signal con_gpio_out: std_ulogic_vector(31 downto 0);
    signal con_gpio_in: std_ulogic_vector(31 downto 0) := (others => 'L');
    signal con_spi_csn: std_ulogic_vector(7 downto 0);
    signal con_uart_tx: std_ulogic;

    component hdmi_console is
        port (
            sys_clk, cpu_reset_n, uart_tx: in std_logic;
            tmds_clk_p, tmds_clk_n: out std_logic;
            tmds_data_p, tmds_data_n: out std_logic_vector(2 downto 0)
        );
    end component;

    component SysPLL is
        port (
            sys_clk: in std_logic;
            enable: in std_logic;
            clk: out std_logic;
            locked: out std_logic
        );
    end component;

begin
    -- LED 2 shows if the external clock is available
    -- Never reset: We want to debug only the clock, not the reset signal
    blink: entity work.LEDBlink
        generic map (
            TOGGLE_CYCLES => 50000000
        )
        port map (
            clk => clk,
            arstn => '1',
            led => sys_led(2)
        );

    -- Key1 is high-active, so invert it before debouncing.
    arstn_btn <= not key1;
    rst: entity work.BTNReset
        generic map (
            DEBOUNCE_CYCLES => 15
        )
        port map (
            clk => clk,
            arstn_i => arstn_btn,
            rstn_o => rstn_btn
        );

    -- Hold the CPU in reset for five seconds after configuration. This leaves
    -- enough time for the onboard USB debugger to switch from JTAG to UART.
    startup: process(clk)
    begin
        if rising_edge(clk) then
            if pll_locked = '0' then
                startup_counter <= 0;
                startup_done <= '0';
            elsif startup_counter /= STARTUP_CYCLES then
                startup_counter <= startup_counter + 1;
            else
                startup_done <= '1';
            end if;
        end if;
    end process;

    rstn <= rstn_btn and startup_done and pll_locked;
    -- LED 0 shows if the reset signal is asserted. LED is low active, as is rstn.
    -- So if the LED is on, the reset is active.
    sys_led(0) <= rstn;


    -- PLL: Generate 96 MHz from 27 MHz input
    pll: SysPLL
        port map (
            sys_clk => sys_clk,
            enable => '1',
            clk => clk,
            locked => pll_locked
        );
    sys_led(1) <= not pll_locked;

    neorv: neorv32_top
        generic map (
            -- Clocking --
            CLOCK_FREQUENCY   => 96000000,          -- clock frequency of clk_i in Hz
            -- Boot Configuration --
            BOOT_MODE_SELECT  => 0,                 -- boot via internal bootloader
            -- Enable JTAG / Debugger --
            OCD_EN            => true,
            -- RISC-V CPU Extensions --
            RISCV_ISA_M       => true,              -- implement mul/div extension?
            RISCV_ISA_Zicntr  => true,              -- implement base counters?
            -- Internal Instruction memory --
            MEM_INT_IMEM_EN   => true,              -- implement processor-internal instruction memory
            MEM_INT_IMEM_SIZE => 24288,              -- size of processor-internal instruction memory in bytes
            -- Internal Data memory --
            MEM_INT_DMEM_EN   => true,              -- implement processor-internal data memory
            MEM_INT_DMEM_SIZE => 16192,              -- size of processor-internal data memory in bytes
            -- Processor peripherals --
            IO_GPIO_NUM       => 4,                 -- number of GPIO input/output pairs (0..64)
            IO_CLINT_EN       => true,              -- implement core local interruptor (CLINT)?
            IO_UART0_EN       => true,              -- implement primary universal asynchronous receiver/transmitter (UART0)?
            IO_SPI_EN         => true,              -- Used for flash bootloader
            IO_GPTMR_EN       => true,
            IO_DMA_EN         => true
        )
        port map (
            -- Global control --
            clk_i       => clk,          -- global clock, rising edge
            rstn_i      => rstn,         -- global reset, low-active, async
            -- JTAG for Debugging --
            jtag_tck_i  => sys_tck,
            jtag_tdi_i  => sys_tdi,
            jtag_tdo_o  => sys_tdo,
            jtag_tms_i  => sys_tms,
            -- GPIO (available if IO_GPIO_NUM > 0) --
            gpio_o      => con_gpio_out,
            gpio_i      => con_gpio_in,
            -- SPI (available if IO_SPI_EN = true) --
            spi_clk_o   => mspi_clk,
            spi_dat_o   => mspi_di,
            spi_dat_i   => mspi_do,
            spi_csn_o   => con_spi_csn,
            -- primary UART0 (available if IO_UART0_EN = true) --
            uart0_txd_o => con_uart_tx,  -- Mirror internally before sending to BL616
            uart0_rxd_i => sys_rx,        -- UART0 receive data. Connect to BL616
            rstn_wdt_o => rstn_wdt_o
        );

    -- LEDs 2 to 5 are driven by software
    sys_led(5 downto 3) <= std_logic_vector(con_gpio_out(2 downto 0));
    -- Write protect (low active) for flash chip
    mspi_wp <= '1' when rstn_wdt_o = '1' else '0';
    -- Input 0 is button 2
    con_gpio_in(0) <= key2;

    -- CS0 is SPI flash
    mspi_cs <= con_spi_csn(0);

    sys_tx <= con_uart_tx;
    console_video: hdmi_console
        port map (
            sys_clk => sys_clk, cpu_reset_n => rstn, uart_tx => con_uart_tx,
            tmds_clk_p => tmds_clk_p, tmds_clk_n => tmds_clk_n,
            tmds_data_p => tmds_data_p, tmds_data_n => tmds_data_n
        );

end;
