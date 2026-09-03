OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
  IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 24288
  DMEM (rwx) : ORIGIN = 0x80000000, LENGTH = 16192
}

SECTIONS
{
  .text : ALIGN(4)
  {
    KEEP(*(.text.init))
    *(.text .text.*)
    *(.rodata .rodata.*)
    . = ALIGN(4);
  } > IMEM

  .data : ALIGN(4)
  {
    *(.data .data.*)
    *(.sdata .sdata.*)
    . = ALIGN(4);
  } > DMEM AT > IMEM

  .bss (NOLOAD) : ALIGN(4)
  {
    *(.bss .bss.*)
    *(.sbss .sbss.*)
    *(COMMON)
    . = ALIGN(4);
  } > DMEM

  /DISCARD/ :
  {
    *(.eh_frame*)
    *(.comment*)
  }
}

