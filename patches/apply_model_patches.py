#!/usr/bin/env python3
"""Apply the guard-only-bounded clamp fixes to a Dynawo v1.7.0 Modelica library.

Usage: apply_model_patches.py <DYNAWO_DDB_DYNAWO_DIR>   (e.g. .../dynawo/ddb/Dynawo)

Replaces if/elseif/else saturation trees whose bound is enforced only by
branch selection (bypassed by Dynawo's mode-frozen algebraic restoration)
with branchless min/max clamps that are equivalent in-guard. Idempotent:
a file already patched counts as satisfied. Aborts if any file does not
match the expected number of replacements.
"""
import re
import sys
from pathlib import Path

DDB = Path(sys.argv[1])
assert (DDB / "Electrical").is_dir(), f"not a ddb/Dynawo dir: {DDB}"

failures = []


def patch(relpath, pairs):
    """Apply (old, new, count) literal replacements; tolerate already-new."""
    p = DDB / relpath
    src = p.read_text()
    changed = False
    for old, new, count in pairs:
        have_old = src.count(old)
        have_new = src.count(new)
        if have_new >= count and have_old == 0:
            continue  # already patched
        if have_old != count:
            failures.append(f"{relpath}: expected {count}x pattern, found {have_old}")
            return
        src = src.replace(old, new)
        changed = True
    if changed:
        p.write_text(src)
    print(f"patched {relpath}")


# The saturation-tree shape used across the HVDC family. Group 'raw' is the
# tested quantity, l1/l2 the limits, v the assigned variable; the else arm may
# assign a different variable (HvdcPV assigns Q1Pu with QInj1Pu == -Q1Pu).
TREE = re.compile(
    r"(?P<ind>[ ]*)if (?P<raw>(?:- )?\w+) (?P<op1><=|>=) (?P<l1>\w+) then\n"
    r"[ ]*(?P<v>\w+) = (?P=l1);\n"
    r"[ ]*elseif (?P=raw) (?P<op2><=|>=) (?P<l2>\w+) then\n"
    r"[ ]*(?P=v) = (?P=l2);\n"
    r"[ ]*else\n"
    r"[ ]*(?P<ve>\w+) = (?P<ee>[^;\n]+);\n"
    r"[ ]*end if;"
)


def clamp_trees(relpath, expected):
    p = DDB / relpath
    src = p.read_text()
    if "min(max(" in src and not TREE.search(src):
        print(f"patched {relpath} (already)")
        return

    def repl(m):
        lo = m.group("l1") if m.group("op1") == "<=" else m.group("l2")
        hi = m.group("l1") if m.group("op1") == ">=" else m.group("l2")
        raw = m.group("raw")
        # Sanity: the else arm must be the raw pass-through, either directly
        # (v = raw) or through the sign-flipped alias (ve = -raw, as in
        # HvdcPV where QInj1Pu == -Q1Pu and the else arm is Q1Pu = Q1RefPu
        # while the guard tests - Q1RefPu).
        direct = m.group("ve") == m.group("v") and m.group("ee").strip() == raw
        flipped = m.group("ve") != m.group("v") and raw == "- " + m.group("ee").strip()
        if not (direct or flipped):
            failures.append(f"{relpath}: unexpected else arm "
                            f"'{m.group('ve')} = {m.group('ee')}' for raw '{raw}'")
            return m.group(0)
        return (f"{m.group('ind')}// Clamped without branch selection so the bound also holds during\n"
                f"{m.group('ind')}// the mode-frozen algebraic restoration at discontinuities\n"
                f"{m.group('ind')}{m.group('v')} = min(max({raw}, {lo}), {hi});")

    out, n = TREE.subn(repl, src)
    if n != expected:
        failures.append(f"{relpath}: expected {expected} saturation trees, matched {n}")
        return
    p.write_text(out)
    print(f"patched {relpath} ({n} trees)")


# --- ElectronicLoad: clamp the three non-constant connectedShare expressions
patch("Electrical/Loads/ElectronicLoad.mo", [
    ("connectedShare = (UPu.value - Ud2Pu) / (Ud1Pu - Ud2Pu);",
     "connectedShare = min(1, max(0, (UPu.value - Ud2Pu) / (Ud1Pu - Ud2Pu)));", 1),
    ("connectedShare = ((UMinPu - Ud2Pu) + recoveringShare * (UPu.value - UMinPu)) / (Ud1Pu - Ud2Pu);",
     "connectedShare = min(1, max(0, ((UMinPu - Ud2Pu) + recoveringShare * (UPu.value - UMinPu)) / (Ud1Pu - Ud2Pu)));", 1),
    ("connectedShare = ((UMinPu - Ud2Pu) + recoveringShare * (Ud1Pu - UMinPu)) / (Ud1Pu - Ud2Pu);",
     "connectedShare = min(1, max(0, ((UMinPu - Ud2Pu) + recoveringShare * (Ud1Pu - UMinPu)) / (Ud1Pu - Ud2Pu)));", 1),
])

# --- HVDC family: reactive-power capability limits
clamp_trees("Electrical/HVDC/HvdcPQProp/HvdcPQProp.mo", 2)
clamp_trees("Electrical/HVDC/HvdcPQProp/HvdcPQPropDangling.mo", 1)
clamp_trees("Electrical/HVDC/HvdcPQProp/HvdcPQPropDiagramPQ.mo", 2)
clamp_trees("Electrical/HVDC/HvdcPQProp/HvdcPQPropDanglingDiagramPQ.mo", 1)
clamp_trees("Electrical/HVDC/HvdcPTanPhi/HvdcPTanPhi.mo", 2)
clamp_trees("Electrical/HVDC/HvdcPTanPhi/HvdcPTanPhiDangling.mo", 1)
clamp_trees("Electrical/HVDC/HvdcPTanPhi/HvdcPTanPhiDiagramPQ.mo", 2)
clamp_trees("Electrical/HVDC/HvdcPTanPhi/HvdcPTanPhiDanglingDiagramPQ.mo", 1)
clamp_trees("Electrical/HVDC/HvdcPV/HvdcPV.mo", 2)
clamp_trees("Electrical/HVDC/HvdcPV/HvdcPVDangling.mo", 1)
clamp_trees("Electrical/HVDC/HvdcPV/HvdcPVDiagramPQ.mo", 2)
clamp_trees("Electrical/HVDC/HvdcPV/HvdcPVDanglingDiagramPQ.mo", 1)

# --- ElectronicLoad: honor the declared "lower bound at Ud2Pu" on UMinPu.
# Stock sets UMinPu = 0 while disconnected; after a reconnection the filter
# freezes it there (0 is not > Ud2Pu), and the recovery expression then
# yields a sustained NEGATIVE connectedShare in-guard (-0.05 with the
# default band: the load injects power). With the floor, a reconnected load
# recovers recoveringShare, matching the declared semantics. This is a
# deliberate behavior change in the switch-off/reconnect regime.
patch("Electrical/Loads/ElectronicLoad.mo", [
    ("terminal.i = Complex(0);\n    connectedShare = 0;\n    UMinPu = 0;",
     "terminal.i = Complex(0);\n    connectedShare = 0;\n    UMinPu = Ud2Pu;", 1),
])

# --- SVarC PVProp family: susceptance capability limit (BVarRawPu is
# algebraic in the bus voltage, so a plain network fault jumps the guard)
for f in ["SVarCPVProp", "SVarCPVPropModeHandling",
          "SVarCPVPropRemote", "SVarCPVPropRemoteModeHandling"]:
    patch(f"Electrical/StaticVarCompensators/{f}.mo", [
        ("BVarPu = if BVarRawPu > BMaxPu then BMaxPu elseif BVarRawPu < BMinPu then BMinPu else BVarRawPu;",
         "BVarPu = min(max(BVarRawPu, BMinPu), BMaxPu);", 1),
    ])

# --- SignalN BaseGenerator: active-power limit
patch("Electrical/Machines/SignalN/BaseClasses/BaseGenerator.mo", [
    ("PGenPu = if PGenRawPu >= PMaxPu then PMaxPu elseif PGenRawPu <= PMinPu then PMinPu else PGenRawPu;",
     "PGenPu = max(min(PGenRawPu, PMaxPu), PMinPu);", 1),
])

# --- Exciter rectifier characteristic: guard the sqrt radicand so an
# out-of-guard evaluation during restoration cannot abort the simulation
patch("Electrical/Controls/Machines/VoltageRegulators/Standard/BaseClasses/RectifierRegulationCharacteristic.mo", [
    ("y = sqrt(UHigh - u ^ 2);",
     "y = sqrt(max(UHigh - u ^ 2, 0));", 1),
    # The linear branches are also unbounded out-of-guard; bound them to the
    # characteristic's documented [0,1] range (inert in-guard: both stay
    # within [0,1] wherever their own guards hold).
    ("y = 1 - A1 * u;",
     "y = min(1, max(0, 1 - A1 * u));", 1),
    ("y = A2 * (1 - u);",
     "y = min(1, max(0, A2 * (1 - u)));", 1),
])

if failures:
    print("FAILED:")
    for f in failures:
        print(" ", f)
    sys.exit(1)
print("All patches applied.")
