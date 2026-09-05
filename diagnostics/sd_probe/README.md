# Read-only SD probe

Temporary RV32 firmware for the Tang Nano 20K's built-in microSD slot.
This is not integrated into MiniOS and does not implement a filesystem.
It supports modern SDHC/SDXC cards only.

The probe initializes the card using GPIO bit-banged SPI at up to 375 kHz,
reads LBA 0 twice,
checks each 512-byte block's CRC16, and compares both reads.
It prints the OCR, CRC, and boot signature, not the sector contents.
Only CMD0, CMD8, CMD55/ACMD41, CMD58 and CMD17 are implemented.
There are no write, erase, or format operations.

## Build and test

```sh
. script/env.sh
gmake test-sd sd-probe-firmware
gmake OBJDIR=build/sd_probe bitstream summary
python3 script/ocd/gen_mww_load.py build/sd_probe/probe.elf build/sd_probe/mww_words.cfg
```

The Rust tests exercise initialization, command framing, card errors, CRC,
timeouts, and CS release after failure using a simulated SPI transport.
These checks do not establish that a physical card has been read successfully.

## Verified hardware result

The GPIO implementation has been exercised on a Tang Nano 20K with a card in
the built-in slot. The probe reported OCR `c0ff8000`, read LBA 0 twice with
matching CRC16 `016d`, and found boot signature `55aa`. No media write command
was implemented or issued during the test.

## Hardware

The existing SPI controller and its input path remain dedicated to boot flash.
The probe uses GPIO0 for SD CLK, GPIO1 for CMD/MOSI, GPIO2 as an active-high
select that the FPGA inverts for DAT3/CS, and GPIO3 for DAT0/MISO. This
inversion keeps the card deselected while the CPU and GPIO block are reset.
The pin mapping follows the [official board example](https://github.com/sipeed/TangNano-20K-example/blob/main/nestang/src/nestang.cst):
CLK=83, CMD/MOSI=82, DAT0/MISO=84, DAT3/CS=81.
DAT1 and DAT2 are not driven in SPI mode.

Keep the card inserted. Load only `build/sd_probe/top.fs` into FPGA SRAM
after entering the native Gowin configuration TAP with S2 held during power-up.
Do not add `-f` and do not erase or reprogram either flash region.

Once the CPU debug TAP is available, `script/ocd/run_bin.cfg` can load
`build/sd_probe/mww_words.cfg` using `MWW_WORDS`.
Require `unmatched=0` before starting the probe with `script/ocd/reboot.cfg`.
Open USB-UART at 19200 baud after FPGA programming and before starting the CPU.
The HDMI mirror should display the same diagnostic output.

A normal power cycle restores the saved FPGA/MiniOS flash image.
