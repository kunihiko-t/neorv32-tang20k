#![no_std]

pub const fn uart_control(clock_hz: u32, baud_rate: u32) -> u32 {
    if clock_hz == 0 || baud_rate == 0 {
        return 0;
    }

    let mut prescaler = 0u32;
    let mut divisor = (clock_hz as u64) / (2 * baud_rate as u64);

    while divisor >= 0x3ff {
        divisor >>= if prescaler == 2 || prescaler == 4 {
            3
        } else {
            1
        };
        prescaler += 1;
    }

    1 | (prescaler << 3) | (((divisor as u32) - 1) << 6)
}

#[cfg(test)]
mod tests {
    use super::uart_control;

    #[test]
    fn configures_108_mhz_uart_for_19200_baud() {
        assert_eq!(uart_control(108_000_000, 19_200), 0x0000_af91);
    }

    #[test]
    fn rejects_zero_clock_or_baud() {
        assert_eq!(uart_control(0, 19_200), 0);
        assert_eq!(uart_control(108_000_000, 0), 0);
    }
}
