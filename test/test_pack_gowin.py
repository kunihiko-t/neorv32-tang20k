import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "script"))
from pack_gowin import fix_gw2a_pll, gowin_pack


class PLLCoordinates(unittest.TestCase):
    def test_both_sides_and_repeated_setup(self):
        fix_gw2a_pll()
        fix_gw2a_pll()
        for x, columns in [(0, [0, 1, 2, 3]), (55, [55, 54, 53, 52])]:
            with self.subTest(x=x):
                bel = SimpleNamespace(x=x, y=45)
                self.assertEqual(
                    list(gowin_pack.GW2A.get_pll_bels(None, bel)),
                    [(col, 45) for col in columns],
                )
