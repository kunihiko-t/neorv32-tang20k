#!/usr/bin/env python3
"""Build a bounded NEORV32 bootloader image from a MiniOS RV32 ELF."""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import struct
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_IMEM_SIZE = 24_288
DEFAULT_DMEM_BASE = 0x8000_0000
DEFAULT_DMEM_SIZE = 16_192
EXE_SIGNATURE = 0x4788_CAFE
ELF32_MACHINE_RISCV = 243
PT_LOAD = 1
PF_X = 1
MAX_ELF_SIZE = 16 * 1024 * 1024
MAX_PROGRAM_HEADERS = 128
UINT32_LIMIT = 1 << 32
ELF_HEADER = struct.Struct("<16sHHIIIIIHHHHHH")
PROGRAM_HEADER = struct.Struct("<8I")


class ImageError(ValueError):
    """An ELF or NEORV32 executable image violates the boot contract."""


@dataclass(frozen=True)
class LoadSegment:
    index: int
    vaddr: int
    paddr: int
    filesz: int
    memsz: int
    flags: int
    data: bytes

    @property
    def vaddr_end(self) -> int:
        return self.vaddr + self.memsz

    @property
    def paddr_end(self) -> int:
        return self.paddr + self.filesz


@dataclass(frozen=True)
class ElfLayout:
    entry: int
    segments: tuple[LoadSegment, ...]
    payload: bytes


def _checked_end(start: int, size: int, label: str) -> int:
    end = start + size
    if start < 0 or size < 0 or end > UINT32_LIMIT:
        raise ImageError(f"{label} range overflows")
    return end


def parse_elf(
    path: Path,
) -> ElfLayout:
    """Validate the narrow ELF32/PT_LOAD contract and make an IMEM payload.

    `p_paddr` is deliberately used for file bytes: the MiniOS linker places
    `.data` in DMEM (`p_vaddr`) with its initialization bytes in IMEM (`p_paddr`).
    The bootloader copies this payload to address zero and starts there.
    """
    try:
        data = path.read_bytes()
    except OSError as error:
        raise ImageError(f"cannot read ELF {path}: {error}") from error
    if len(data) > MAX_ELF_SIZE:
        raise ImageError(f"ELF exceeds bounded parser limit ({MAX_ELF_SIZE} bytes)")
    if len(data) < ELF_HEADER.size:
        raise ImageError("ELF header is truncated")

    ident, e_type, machine, version, entry, phoff, _, _, ehsize, phentsize, phnum, *_ = (
        ELF_HEADER.unpack_from(data)
    )
    if ident[:4] != b"\x7fELF" or ident[4] != 1 or ident[5] != 1:
        raise ImageError("ELF must be 32-bit little-endian")
    if machine != ELF32_MACHINE_RISCV:
        raise ImageError(f"ELF machine {machine} is not RISC-V")
    if version != 1 or e_type != 2:
        raise ImageError("ELF must be a fixed-address ET_EXEC executable")
    if ehsize != ELF_HEADER.size or phentsize != PROGRAM_HEADER.size:
        raise ImageError("unsupported ELF/program-header size")
    if phnum == 0 or phnum > MAX_PROGRAM_HEADERS:
        raise ImageError(f"invalid program-header count: {phnum}")
    ph_end = _checked_end(phoff, phnum * phentsize, "program-header table")
    if phoff < ELF_HEADER.size or ph_end > len(data):
        raise ImageError("program-header table is outside the ELF")

    dmem_end = _checked_end(DEFAULT_DMEM_BASE, DEFAULT_DMEM_SIZE, "DMEM")
    segments: list[LoadSegment] = []
    for index in range(phnum):
        p_type, p_offset, vaddr, paddr, filesz, memsz, flags, _ = PROGRAM_HEADER.unpack_from(
            data, phoff + index * phentsize
        )
        if p_type != PT_LOAD:
            continue
        if filesz > memsz:
            raise ImageError(f"PT_LOAD[{index}] filesz exceeds memsz")
        file_end = _checked_end(p_offset, filesz, f"PT_LOAD[{index}] file")
        if file_end > len(data):
            raise ImageError(f"PT_LOAD[{index}] file range is outside the ELF")
        vaddr_end = _checked_end(vaddr, memsz, f"PT_LOAD[{index}] virtual")
        if vaddr < DEFAULT_DMEM_BASE:
            if vaddr_end > DEFAULT_IMEM_SIZE:
                raise ImageError(f"PT_LOAD[{index}] virtual range exceeds IMEM")
            if filesz and paddr != vaddr:
                raise ImageError(f"PT_LOAD[{index}] IMEM VMA and LMA differ")
        elif vaddr_end > dmem_end:
            raise ImageError(f"PT_LOAD[{index}] virtual range exceeds DMEM")
        if filesz and (paddr % 4 or filesz % 4):
            raise ImageError(f"PT_LOAD[{index}] file range is not word-aligned")
        if filesz:
            paddr_end = _checked_end(paddr, filesz, f"PT_LOAD[{index}] load")
            if paddr_end > DEFAULT_IMEM_SIZE:
                raise ImageError(f"PT_LOAD[{index}] load range exceeds IMEM")
        segments.append(
            LoadSegment(index, vaddr, paddr, filesz, memsz, flags, data[p_offset:file_end])
        )

    if not segments:
        raise ImageError("ELF has no PT_LOAD segments")
    if entry != 0:
        raise ImageError(f"ELF entry 0x{entry:08x} is not bootloader start 0x00000000")
    entry_segments = [
        segment
        for segment in segments
        if segment.flags & PF_X and segment.vaddr <= entry < segment.vaddr + segment.filesz
    ]
    if not entry_segments or entry_segments[0].vaddr != 0 or entry_segments[0].paddr != 0:
        raise ImageError("ELF entry is not backed by the IMEM PT_LOAD at address zero")

    file_segments = sorted((segment for segment in segments if segment.filesz), key=lambda s: s.paddr)
    payload_end = max((segment.paddr_end for segment in file_segments), default=0)
    payload = bytearray(payload_end)
    occupied: list[tuple[int, int]] = []
    for segment in file_segments:
        for start, end in occupied:
            if segment.paddr < end and start < segment.paddr_end:
                raise ImageError(f"PT_LOAD[{segment.index}] file ranges overlap in IMEM")
        payload[segment.paddr : segment.paddr_end] = segment.data
        occupied.append((segment.paddr, segment.paddr_end))
    if not payload or len(payload) % 4:
        raise ImageError("IMEM payload must be non-empty and word-aligned")
    return ElfLayout(entry, tuple(segments), bytes(payload))


def verify_executable(image: bytes, expected_payload: bytes | None = None) -> None:
    """Verify signature, byte length, payload and complement checksum."""
    if len(image) < 12:
        raise ImageError("NEORV32 executable is shorter than its 12-byte header")
    signature, size, checksum = struct.unpack_from("<3I", image)
    payload = image[12:]
    if signature != EXE_SIGNATURE:
        raise ImageError(f"unexpected executable signature 0x{signature:08x}")
    if size != len(payload) or size % 4:
        raise ImageError(f"executable header size {size} does not match {len(payload)} bytes")
    if expected_payload is not None and payload != expected_payload:
        raise ImageError("image generator changed the validated IMEM payload")
    words_sum = sum(word[0] for word in struct.iter_unpack("<I", payload)) & 0xFFFF_FFFF
    if (words_sum + checksum) & 0xFFFF_FFFF:
        raise ImageError("NEORV32 executable checksum is invalid")


def _image_generator(temporary: Path) -> str:
    env_tool = os.environ.get("NEORV32_IMAGE_GEN")
    if env_tool:
        return env_tool
    existing = ROOT / "sw" / "minios_hello" / "build" / "image_gen"
    if existing.is_file():
        return str(existing)
    compiler = os.environ.get("CC") or shutil.which("cc")
    if not compiler:
        raise ImageError("required tool not found: cc (source script/env.sh first)")
    binary = temporary / "image_gen"
    try:
        subprocess.run(
            [compiler, "-O2", str(ROOT / "lib" / "neorv32" / "sw" / "image_gen" / "image_gen.c"), "-o", str(binary)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        detail = getattr(error, "stderr", "") or str(error)
        raise ImageError(f"failed to build NEORV32 image_gen: {detail.strip()}") from error
    return str(binary)


def build_image(
    elf: Path,
    output: Path,
) -> tuple[ElfLayout, bytes]:
    """Validate ELF, run vendored image_gen, and atomically publish the image."""
    layout = parse_elf(elf)
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="minios32-image-", dir=output.parent) as temporary_name:
        temporary = Path(temporary_name)
        raw = temporary / "payload.bin"
        generated = temporary / "neorv32_exe.bin"
        raw.write_bytes(layout.payload)
        generator = _image_generator(temporary)
        try:
            subprocess.run(
                [generator, "-app_bin", str(raw), str(generated), "minios32"],
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
        except (OSError, subprocess.CalledProcessError) as error:
            detail = getattr(error, "stderr", "") or str(error)
            raise ImageError(f"NEORV32 image_gen failed: {detail.strip()}") from error
        image = generated.read_bytes()
        verify_executable(image, layout.payload)
        os.replace(generated, output)
    return layout, image


def _default_elf(minios: Path) -> Path:
    target = minios / "target" / "riscv32im-unknown-none-elf" / "release"
    candidate = target / "minios-kernel"
    if candidate.is_file():
        return candidate
    raise ImageError(f"MiniOS RV32 release ELF not found: {candidate}")


def _print_layout(layout: ElfLayout, output: Path, image: bytes) -> None:
    print(f"entry=0x{layout.entry:08x}")
    for segment in layout.segments:
        print(
            f"PT_LOAD[{segment.index}] "
            f"VMA=0x{segment.vaddr:08x}..0x{segment.vaddr_end:08x} "
            f"LMA=0x{segment.paddr:08x}..0x{segment.paddr_end:08x} "
            f"filesz={segment.filesz} memsz={segment.memsz} flags=0x{segment.flags:x}"
        )
    print(f"payload={len(layout.payload)} bytes; IMEM limit={DEFAULT_IMEM_SIZE} bytes")
    print(f"image={output.resolve()} size={len(image)} sha256={hashlib.sha256(image).hexdigest()}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    default_minios = Path(os.environ.get("MINIOS", str(ROOT.parent.parent / "minios")))
    parser.add_argument("--minios", type=Path, default=default_minios)
    parser.add_argument("--elf", type=Path, help="MiniOS RV32 release ELF (default: --minios release ELF)")
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT / "build" / "minios32" / "neorv32_exe.bin",
        help="NEORV32 executable output path",
    )
    args = parser.parse_args(argv)

    try:
        elf = args.elf or _default_elf(args.minios)
        layout, image = build_image(elf, args.output)
    except (ImageError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    _print_layout(layout, args.output, image)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
