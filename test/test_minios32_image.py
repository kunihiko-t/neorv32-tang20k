import subprocess
import struct
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "script" / "build_minios32_image.py"
sys.path.insert(0, str(SCRIPT.parent / "ocd"))
from gen_mww_load import load_segments

IMEM_SIZE = 24_288
DMEM_BASE = 0x8000_0000
DMEM_SIZE = 16_192
EXE_SIGNATURE = 0x4788_CAFE


def write_elf(path, segments, entry=0, e_type=2):
    """Write a tiny ELF32 fixture with only the program headers under test."""
    phoff = 52
    phentsize = 32
    data_offset = phoff + phentsize * len(segments)
    data_offset = (data_offset + 0xFF) & ~0xFF
    image = bytearray(data_offset)
    image[:16] = bytes([0x7F]) + b"ELF" + bytes([1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    struct.pack_into(
        "<HHIIIIIHHHHHH",
        image,
        16,
        e_type,
        243,
        1,
        entry,
        phoff,
        0,
        0,
        52,
        phentsize,
        len(segments),
        0,
        0,
        0,
    )
    for index, (vaddr, paddr, payload, memsz, flags) in enumerate(segments):
        offset = data_offset
        image.extend(payload)
        data_offset += len(payload)
        struct.pack_into(
            "<8I",
            image,
            phoff + index * phentsize,
            1,
            offset if payload else 0,
            vaddr,
            paddr,
            len(payload),
            memsz,
            flags,
            4,
        )
    path.write_bytes(image)


def run_builder(elf, output):
    return subprocess.run(
        [sys.executable, str(SCRIPT), "--elf", str(elf), "--output", str(output)],
        capture_output=True,
        text=True,
    )


class MiniOSImageWorkflowTests(unittest.TestCase):
    def test_image_builder_exposes_help(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--help"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("NEORV32", result.stdout)

    def test_builds_contiguous_lma_payload_with_verified_bootloader_header(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            elf = root / "kernel"
            output = root / "neorv32_exe.bin"
            write_elf(
                elf,
                [
                    (0, 0, b"ABCD", 4, 5),
                    (DMEM_BASE, 4, b"WXYZ", 4, 6),
                    (DMEM_BASE + 4, 8, b"", 4, 6),
                ],
            )

            result = run_builder(elf, output)

            self.assertEqual(result.returncode, 0, result.stderr)
            image = output.read_bytes()
            signature, size, checksum = struct.unpack_from("<3I", image)
            payload = image[12:]
            self.assertEqual(signature, EXE_SIGNATURE)
            self.assertEqual(size, 8)
            self.assertEqual(payload, b"ABCDWXYZ")
            words = struct.unpack("<2I", payload)
            self.assertEqual((sum(words) + checksum) & 0xFFFF_FFFF, 0)
            self.assertIn("entry=0x00000000", result.stdout)
            self.assertIn("LMA=0x00000004", result.stdout)

    def test_rejects_payload_that_exceeds_imem_before_writing_output(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            elf = root / "oversized"
            output = root / "neorv32_exe.bin"
            write_elf(elf, [(0, 0, b"A" * (IMEM_SIZE + 4), IMEM_SIZE + 4, 5)])

            result = run_builder(elf, output)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("IMEM", result.stderr)
            self.assertFalse(output.exists())

    def test_rejects_dmem_segment_that_exceeds_dmem(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            elf = root / "dmem-overflow"
            output = root / "neorv32_exe.bin"
            write_elf(
                elf,
                [(0, 0, b"ABCD", 4, 5), (DMEM_BASE + DMEM_SIZE - 2, 4, b"WXYZ", 4, 6)],
            )

            result = run_builder(elf, output)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("DMEM", result.stderr)
            self.assertFalse(output.exists())

    def test_rejects_nonzero_entry_for_bootloader_start(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            elf = root / "wrong-entry"
            output = root / "neorv32_exe.bin"
            write_elf(elf, [(0, 0, b"ABCD", 4, 5)], entry=4)

            result = run_builder(elf, output)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("entry", result.stderr)
            self.assertFalse(output.exists())

    def test_mww_load_uses_lma_for_data_initialization(self):
        with tempfile.TemporaryDirectory() as directory:
            elf = Path(directory) / "kernel"
            write_elf(
                elf,
                [
                    (0, 0, b"ABCD", 4, 5),
                    (DMEM_BASE, 4, b"WXYZ", 4, 6),
                ],
            )

            segments = load_segments(str(elf))

            self.assertEqual(segments, [(0, b"ABCD"), (4, b"WXYZ")])

    def test_allows_bss_with_a_non_imem_load_address(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            elf = root / "kernel"
            output = root / "neorv32_exe.bin"
            write_elf(
                elf,
                [
                    (0, 0, b"ABCD", 4, 5),
                    (DMEM_BASE, 4, b"WXYZ", 4, 6),
                    (DMEM_BASE + 4, 0x9000_0000, b"", 4, 6),
                ],
            )

            result = run_builder(elf, output)

            self.assertEqual(result.returncode, 0, result.stderr)

    def test_rejects_file_backed_imem_mapping_with_a_distinct_lma(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            elf = root / "wrong-lma"
            output = root / "neorv32_exe.bin"
            write_elf(
                elf,
                [(0, 0, b"ABCD", 4, 5), (4, 8, b"WXYZ", 4, 5)],
            )

            result = run_builder(elf, output)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("VMA", result.stderr)
            self.assertFalse(output.exists())

    def test_rejects_entry_that_only_lies_in_zero_fill(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            elf = root / "entry-bss"
            output = root / "neorv32_exe.bin"
            write_elf(
                elf,
                [(0, 0, b"", 4, 5), (4, 4, b"ABCD", 4, 5)],
            )

            result = run_builder(elf, output)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("entry", result.stderr)
            self.assertFalse(output.exists())

    def test_rejects_position_independent_elf_for_fixed_boot_address(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            elf = root / "pie"
            output = root / "neorv32_exe.bin"
            write_elf(elf, [(0, 0, b"ABCD", 4, 5)], e_type=3)

            result = run_builder(elf, output)

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("ET_EXEC", result.stderr)
            self.assertFalse(output.exists())

    def test_default_rejects_a_stale_binary_with_a_different_name(self):
        with tempfile.TemporaryDirectory() as directory:
            minios = Path(directory) / "minios"
            release = minios / "target" / "riscv32im-unknown-none-elf" / "release"
            release.mkdir(parents=True)
            write_elf(release / "kernel", [(0, 0, b"ABCD", 4, 5)])
            output = Path(directory) / "neorv32_exe.bin"

            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--minios", str(minios), "--output", str(output)],
                capture_output=True,
                text=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("minios-kernel", result.stderr)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
