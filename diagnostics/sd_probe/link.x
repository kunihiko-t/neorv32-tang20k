OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY {
    IMEM (rx) : ORIGIN = 0, LENGTH = 24288
    DMEM (rwx) : ORIGIN = 0x80000000, LENGTH = 16192
}
SECTIONS {
    .text : ALIGN(4) {
        KEEP(*(.text.init))
        *(.text .text.*) *(.rodata .rodata.*)
        . = ALIGN(4);
    } > IMEM
    .data : ALIGN(4) {
        _data_start = .;
        *(.data .data.*) *(.sdata .sdata.*)
        . = ALIGN(4);
        _data_end = .;
    } > DMEM AT > IMEM
    _data_load = LOADADDR(.data);
    __global_pointer$ = ORIGIN(DMEM) + 0x800;
    .bss (NOLOAD) : ALIGN(4) {
        _bss_start = .;
        *(.bss .bss.*) *(.sbss .sbss.*) *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > DMEM
    /DISCARD/ : { *(.eh_frame*) *(.comment*) }
}
