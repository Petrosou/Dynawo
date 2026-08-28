#!/usr/bin/env python3
"""Identity test: the branchless ElectronicLoad share law equals the clamped
piecewise ladder on the whole invariant domain (UMin >= Ud2, 0 <= r <= 1).

Ladder (the round-1..4 clamped fix):
  U <  Ud2:            0
  Ud2 <= U < Ud1:
    U <= UMin:         clamp01((U - Ud2)/d)
    else:              clamp01(((UMin - Ud2) + r*(U - UMin))/d)
  U >= Ud1:
    UMin >= Ud1:       1
    else:              clamp01(((UMin - Ud2) + r*(Ud1 - UMin))/d)

Branchless (round-5 relay):
  down(x) = clamp01((x - Ud2)/d); m = min(U, UMin)
  share   = down(m) + r*(down(U) - down(m))

Exits nonzero on any mismatch (float grid > 1e-14, exact rationals != 0).
"""
import random
import sys
from fractions import Fraction


def clamp01(x):
    return min(1, max(0, x))


def ladder(U, UMin, r, Ud1, Ud2):
    d = Ud1 - Ud2
    if U < Ud2:
        return 0 * U  # keep Fraction type
    if U < Ud1:
        if U <= UMin:
            return clamp01((U - Ud2) / d)
        return clamp01(((UMin - Ud2) + r * (U - UMin)) / d)
    if UMin >= Ud1:
        return 1 + 0 * U
    return clamp01(((UMin - Ud2) + r * (Ud1 - UMin)) / d)


def branchless(U, UMin, r, Ud1, Ud2):
    d = Ud1 - Ud2
    down = lambda x: clamp01((x - Ud2) / d)
    m = min(U, UMin)
    return down(m) + r * (down(U) - down(m))


def float_grid(Ud1, Ud2):
    maxdiff = 0.0
    n = 0
    boundary = [Ud2, Ud1, (Ud1 + Ud2) / 2]
    us = [i * 1e-3 for i in range(0, 1501)] + boundary
    umins = [Ud2 + i * 1e-3 for i in range(0, int((1.5 - Ud2) * 1000) + 1)] + boundary
    for r in (0.0, 0.3, 0.7, 1.0):
        for U in us:
            for UMin in umins:
                if UMin < Ud2:
                    continue
                dv = abs(ladder(U, UMin, r, Ud1, Ud2) - branchless(U, UMin, r, Ud1, Ud2))
                if dv > maxdiff:
                    maxdiff = dv
                n += 1
    return n, maxdiff


def exact_random(Ud1, Ud2, k=100_000):
    rng = random.Random(128)
    Ud1, Ud2 = Fraction(Ud1), Fraction(Ud2)
    bad = 0
    for _ in range(k):
        U = Fraction(rng.randint(0, 3_000_000), 2_000_000)          # [0, 1.5]
        UMin = Ud2 + Fraction(rng.randint(0, 2_000_000), 2_000_000)  # [Ud2, Ud2+1]
        r = Fraction(rng.randint(0, 1000), 1000)
        if ladder(U, UMin, r, Ud1, Ud2) != branchless(U, UMin, r, Ud1, Ud2):
            bad += 1
    return bad


ok = True
for (ud1, ud2) in ((0.7, 0.5), (1.0, 0.1)):
    n, md = float_grid(ud1, ud2)
    print(f"float grid  (Ud1={ud1}, Ud2={ud2}): {n} points, max |diff| = {md:.3e}")
    ok &= md <= 1e-14
    bad = exact_random(Fraction(str(ud1)), Fraction(str(ud2)))
    print(f"exact Fraction (Ud1={ud1}, Ud2={ud2}): 100000 random points, {bad} mismatches")
    ok &= bad == 0

print("IDENTITY", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
