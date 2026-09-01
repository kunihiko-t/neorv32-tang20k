#![no_main]
#![no_std]

use core::arch::global_asm;
use core::ptr::{read_volatile, write_volatile};
use minios_hello::uart_control;

const UART0_CTRL: *mut u32 = 0xfff5_0000 as *mut u32;
const UART0_DATA: *mut u32 = 0xfff5_0004 as *mut u32;
const UART_TX_FULL: u32 = 1 << 21;

global_asm!(
    r#"
    .section .text.init,"ax"
    .balign 4
    .global _start
_start:
    li sp, 0x80003f40
    call rust_main
1:
    wfi
    j 1b
"#
);

#[no_mangle]
pub extern "C" fn rust_main() -> ! {
    unsafe {
        write_volatile(UART0_CTRL, uart_control(108_000_000, 19_200));
    }

    for byte in b"MiniOS/RV32 hello\r\n" {
        uart_put(*byte);
    }

    loop {
        unsafe {
            core::arch::asm!("wfi");
        }
    }
}

fn uart_put(byte: u8) {
    unsafe {
        while read_volatile(UART0_CTRL) & UART_TX_FULL != 0 {}
        write_volatile(UART0_DATA, byte as u32);
    }
}

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo<'_>) -> ! {
    loop {
        unsafe {
            core::arch::asm!("wfi");
        }
    }
}

