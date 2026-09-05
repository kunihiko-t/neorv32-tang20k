#![no_std]
#![no_main]

use core::{
    arch::{asm, global_asm},
    fmt::{self, Write},
    ptr::{read_volatile, write_volatile},
};
use sd_probe::{Bus, Error};

const GPIO: *mut u32 = 0xfffc_0000 as *mut u32;
const UART: *mut u32 = 0xfff5_0000 as *mut u32;
const CYCLES_MS: u32 = 96_000;
const GPIO_SCK: u32 = 1 << 0;
const GPIO_MOSI: u32 = 1 << 1;
const GPIO_SELECT: u32 = 1 << 2;
const GPIO_MISO: u32 = 1 << 3;
const HALF_CYCLE: u32 = 128; // at most 375 kHz from a 96 MHz CPU

global_asm!(
    r#"
    .section .text.init,"ax"
    .global _start
    .option push
    .option norvc
_start:
    csrw mie, zero
    csrw mstatus, zero
    csrw mcountinhibit, zero
    la t0, 6f
    csrw mtvec, t0
    li sp, 0x80003f40
    .option norelax
    la gp, __global_pointer$
    .option relax
    la t0, _data_load
    la t1, _data_start
    la t2, _data_end
1:  bgeu t1, t2, 2f
    lw t3, 0(t0)
    sw t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j 1b
2:  la t1, _bss_start
    la t2, _bss_end
3:  bgeu t1, t2, 4f
    sw zero, 0(t1)
    addi t1, t1, 4
    j 3b
4:  call rust_main
5:  wfi
    j 5b
6:  j 6b
    .option pop
"#
);

fn cycles() -> u32 {
    let n;
    unsafe { asm!("rdcycle {0}", out(reg) n, options(nomem, nostack)) };
    n
}

fn delay_cycles(n: u32) {
    let start = cycles();
    while cycles().wrapping_sub(start) < n {
        core::hint::spin_loop();
    }
}

struct GpioSpi {
    output: u32,
}
impl GpioSpi {
    fn write(&self) {
        unsafe { write_volatile(GPIO.add(1), self.output) };
    }
}
impl Bus for GpioSpi {
    fn select(&mut self, active: bool) -> Result<(), Error> {
        self.output &= !GPIO_SCK;
        self.output |= GPIO_MOSI;
        if active {
            self.output |= GPIO_SELECT;
        } else {
            self.output &= !GPIO_SELECT;
        }
        self.write();
        Ok(())
    }
    fn transfer(&mut self, tx: u8) -> Result<u8, Error> {
        let mut rx = 0u8;
        for bit in (0..8).rev() {
            self.output &= !GPIO_SCK;
            if tx & (1 << bit) != 0 {
                self.output |= GPIO_MOSI;
            } else {
                self.output &= !GPIO_MOSI;
            }
            self.write();
            delay_cycles(HALF_CYCLE);
            self.output |= GPIO_SCK;
            self.write();
            delay_cycles(HALF_CYCLE);
            rx = (rx << 1) | ((unsafe { read_volatile(GPIO) } & GPIO_MISO != 0) as u8);
        }
        self.output &= !GPIO_SCK;
        self.write();
        Ok(rx)
    }
    fn delay_ms(&mut self, ms: u32) {
        for _ in 0..ms {
            let start = cycles();
            while cycles().wrapping_sub(start) < CYCLES_MS {
                core::hint::spin_loop();
            }
        }
    }
}

struct Console;
impl Write for Console {
    fn write_str(&mut self, text: &str) -> fmt::Result {
        for byte in text.bytes() {
            let start = cycles();
            while unsafe { read_volatile(UART) } & (1 << 21) != 0 {
                if cycles().wrapping_sub(start) >= CYCLES_MS * 100 {
                    return Err(fmt::Error);
                }
            }
            unsafe { write_volatile(UART.add(1), byte as u32) };
        }
        Ok(())
    }
}

#[no_mangle]
extern "C" fn rust_main() {
    unsafe {
        write_volatile(UART, 0);
        write_volatile(UART, 0x9c11); // 96 MHz, 19200 baud, no IRQ.
        write_volatile(GPIO.add(1), GPIO_MOSI);
    }
    let mut console = Console;
    let mut bus = GpioSpi { output: GPIO_MOSI };
    let _ = console.write_str("\r\nSD READ-ONLY PROBE (GPIO SPI, <=375kHz)\r\n");
    match sd_probe::init(&mut bus) {
        Ok(ocr) => {
            let _ = write!(console, "SDHC/SDXC ready, OCR={ocr:08x}\r\n");
            let mut first = [0u8; 512];
            let mut second = [0u8; 512];
            match sd_probe::read_block0(&mut bus, &mut first)
                .and_then(|crc| sd_probe::read_block0(&mut bus, &mut second).map(|_| crc))
            {
                Ok(crc) if first == second => {
                    let _ = write!(
                        console,
                        "PASS: block0 512 bytes, CRC16={crc:04x}, reread identical\r\n"
                    );
                    let _ = write!(
                        console,
                        "Boot signature: {:02x}{:02x}\r\n",
                        first[510], first[511]
                    );
                }
                Ok(_) => {
                    let _ = console.write_str("FAIL: repeated reads differ\r\n");
                }
                Err(e) => {
                    let _ = write!(console, "FAIL: block0 read {e:?}\r\n");
                }
            }
        }
        Err(e) => {
            let _ = write!(console, "FAIL: SD init {e:?}\r\n");
        }
    }
    // Also releases CS if the protocol cleanup stopped early.
    unsafe { write_volatile(GPIO.add(1), GPIO_MOSI) };
    let _ = console.write_str("Probe finished; no media write commands issued.\r\n");
}

#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    unsafe { write_volatile(GPIO.add(1), GPIO_MOSI) };
    let _ = Console.write_str("\r\nPANIC: SD probe stopped\r\n");
    loop {
        unsafe { asm!("wfi") };
    }
}
