#!/usr/bin/env python3
"""Mechanical check of the in-guard bounds argument for the clamp fix.

The fix wraps the three non-constant piecewise connectedShare expressions of
Dynawo's ElectronicLoad in min(1, max(0, ...)). It is behavior-preserving if
each expression already lies in [0, 1] whenever its if-guard holds. This
script samples (Ud1Pu, Ud2Pu, recoveringShare, UPu, UMinPu) tuples on dense
grids, keeps exactly those satisfying the model's guard predicates (as
written, in floating point), and asserts the guarded expression is in [0, 1]
so the clamp returns it unchanged.

Guards checked (from ElectronicLoad.mo, with UMinPu >= Ud2Pu from the filter
equation, which freezes UMinPu at Ud2Pu):
  branch 1 (falling):   Ud2Pu <= UPu < Ud1Pu and UPu <= UMinPu
  branch 2 (recovery):  Ud2Pu <= UPu < Ud1Pu and UPu >  UMinPu
  branch 3 (above Ud1): UPu >= Ud1Pu and UMinPu < Ud1Pu

Boundary note (documented, not a failure): within one ulp of a guard
boundary, floating-point rounding of the division can produce a value one
ulp above 1.0 for an argument that is mathematically in-guard. The clamp
maps such values to exactly 1.0 -- a sub-ulp correction in the fix's favor.
The assertion below therefore allows exactly-representable results up to
1.0; any sample exceeding 1.0 must lie within one ulp of a guard boundary,
which the script verifies explicitly and reports.
"""
import math
import sys

STEPS = 80


def frange(lo, hi, n):
    return [lo + (hi - lo) * i / (n - 1) for i in range(n)]


def main():
    checked = 0
    boundary_ulps = 0
    for ud2, ud1 in [(0.5, 0.7), (0.3, 0.9), (0.6, 0.61), (0.0, 1.0), (0.4, 0.8)]:
        band = ud1 - ud2
        for r in frange(0.0, 1.0, 11):
            for u in frange(ud2 - 0.05, ud1 + 0.05, STEPS):
                for umin in frange(ud2, ud1 + 0.05, 40):
                    in_band = (ud2 <= u < ud1)
                    if in_band and u <= umin:            # branch 1: falling
                        x = (u - ud2) / band
                    elif in_band and u > umin:           # branch 2: recovery
                        x = ((umin - ud2) + r * (u - umin)) / band
                    elif u >= ud1 and umin < ud1:        # branch 3: above Ud1
                        x = ((umin - ud2) + r * (ud1 - umin)) / band
                    else:
                        continue
                    checked += 1
                    if 0.0 <= x <= 1.0:
                        continue
                    # Any excess must be a single-ulp rounding artifact at a
                    # guard boundary; anything larger fails the check.
                    if x > 1.0 and (x - 1.0) <= math.ulp(1.0) and (
                            abs(u - ud1) <= 2 * math.ulp(ud1)
                            or abs(umin - ud1) <= 2 * math.ulp(ud1)):
                        boundary_ulps += 1
                        continue
                    raise AssertionError((ud1, ud2, r, u, umin, x))
    print(f"PASS: {checked} guard-satisfying samples across 5 (Ud1Pu, Ud2Pu) "
          f"bands x 11 recoveringShare values: every in-guard expression is "
          f"in [0,1] (clamp inert), except {boundary_ulps} samples exactly on "
          f"a guard boundary where fp rounding overshoots 1.0 by one ulp -- "
          f"which the clamp corrects to 1.0.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
