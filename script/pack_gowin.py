"""Work around the bundled apycula GW2A left-PLL coordinate bug.

Only the affected process is patched, never the installed toolchain. Remove
this wrapper after upgrading to an apycula version that handles both PLLs.
"""
from types import SimpleNamespace

from apycula import gowin_pack


def fix_gw2a_pll():
    try:
        list(gowin_pack.GW2A.get_pll_bels(None, SimpleNamespace(x=0, y=45)))
    except UnboundLocalError:
        # Left PLL extends rightwards, right PLL extends leftwards. This is
        # also the coordinate mapping used by apycula's GW1N_9 implementation.
        def pll_bels(self, bel):
            direction = -1 if bel.x > 27 else 1
            for offset in range(4):
                yield bel.x + direction * offset, bel.y

        gowin_pack.GW2A.get_pll_bels = pll_bels


if __name__ == "__main__":
    fix_gw2a_pll()
    raise SystemExit(gowin_pack.main())
