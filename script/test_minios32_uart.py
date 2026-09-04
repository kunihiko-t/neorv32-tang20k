"""Exercise a running MiniOS RV32 shell via the board's USB-UART (no flashing)."""

import argparse
import time

import serial


def exchange(port, command):
    # Exercise keyboard entry, not paste throughput: the current FPGA RX FIFO
    # holds only one byte, so an unpaced burst can lose characters.
    for byte in command:
        port.write(bytes([byte]))
        time.sleep(0.01)
    port.flush()
    response = port.read_until(b"minios> ", size=4096).replace(b"\r", b"")
    if not response.endswith(b"minios> "):
        raise AssertionError(f"No shell prompt after {command!r}: {response!r}")
    print(response.decode("ascii", errors="backslashreplace"), end="", flush=True)
    return response


def main():
    if not __debug__:
        raise SystemExit("Run without -O/PYTHONOPTIMIZE: this test requires assertions")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", nargs="?", default="/dev/cu.usbserial-20250303171")
    parser.add_argument("--baud", type=int, default=19200)
    args = parser.parse_args()
    with serial.Serial(args.port, args.baud, timeout=3, write_timeout=3) as port:
        port.reset_input_buffer()
        exchange(port, b"\r")
        help_text = exchange(port, b"help\r")
        for command in (b"help", b"info", b"echo"):
            assert command in help_text, help_text
        info = exchange(port, b"info\r")
        assert b"MiniOS" in info and b"NEORV32" in info, info
        assert b"hart id: 0" in info, info
        # Requiring a separate output line rejects a byte-echo-only implementation.
        assert b"\nhello from Mac\n" in exchange(port, b"echo hello from Mac\r")
        assert b"\nOK\n" in exchange(port, b"echo OX\x7fK\r")
        assert b"unknown command" in exchange(port, b"does-not-exist\r")
        assert b"error:" in exchange(port, b"x" * 129 + b"\r")
        assert b"\nrecovered\n" in exchange(port, b"echo recovered\n")
        assert b"\ncrlf\n" in exchange(port, b"echo crlf\r\n")
        assert port.read(1) == b"", "CRLF must not submit a second empty command"
    print("\nPASS: MiniOS commands, editing, overflow and recovery over USB-UART")


if __name__ == "__main__":
    main()
