#!/usr/bin/env python3
"""ELFのLOADセグメントをOpenOCDのmww書き込み行へ変換する。

`load_image`のprogram-buffer経路がNEORV32でbusy失敗するため、
abstract-accessの`mww`で1ワードずつ書く。ファイル内容はLMAへ書くため、
`.data AT>IMEM`のようなLMA/VMA分離も正しく配置される。
BSS(NOLOAD)は対象外。カーネル側のentry.Sがゼロ化する。

使い方: gen_mww_load.py <input.elf> <output.cfg>
"""

import struct
import sys


def load_segments(path):
    with open(path, "rb") as image:
        data = image.read()
    if data[:4] != b"\x7fELF":
        raise SystemExit(f"not an ELF file: {path}")
    if data[4] != 1 or data[5] != 1:
        raise SystemExit("only 32-bit little-endian ELF is supported")
    e_phoff = struct.unpack("<I", data[0x1C:0x20])[0]
    e_phentsize = struct.unpack("<H", data[0x2A:0x2C])[0]
    e_phnum = struct.unpack("<H", data[0x2C:0x2E])[0]
    segments = []
    for index in range(e_phnum):
        offset = e_phoff + index * e_phentsize
        p_type, p_offset, _, p_paddr, p_filesz, _, _, _ = struct.unpack(
            "<8I", data[offset : offset + 32]
        )
        if p_type == 1 and p_filesz > 0:
            segments.append((p_paddr, data[p_offset : p_offset + p_filesz]))
    return segments


def main():
    elf_path, cfg_path = sys.argv[1], sys.argv[2]
    pairs = []
    with open(cfg_path, "w") as cfg:
        cfg.write("set PAIRS {\n")
        for paddr, blob in load_segments(elf_path):
            padding = (-len(blob)) % 4
            blob = blob + b"\x00" * padding
            for index in range(0, len(blob), 4):
                word = struct.unpack("<I", blob[index : index + 4])[0]
                cfg.write(f"    {{{paddr + index:#x} {word:#x}}}\n")
                pairs.append(1)
        cfg.write("}\n")
    print(f"wrote {len(pairs)} pairs to {cfg_path}")


if __name__ == "__main__":
    main()
