#!/bin/bash
# Build a personal Dynawo v1.7.0 with the guard-only-bounded clamp fixes.
#
# !! This produces a MODIFIED Dynawo. All patches were authored and verified
# !! by AI (Anthropic's Claude) with no human review — see bug128/ and
# !! patches/ for the evidence trail. Results from this build must not be
# !! attributed to stock Dynawo.
#
# Steps: install the official 1.7.0 release, patch the Modelica library
# sources (patches/apply_model_patches.py), rebuild every affected
# precompiled model (patches/rebuild_patched_models.sh, ~1-2 h), then run
# the A/B verification suite (patched-verify/verify_patched_dynawo.sh).
# Stock .so are kept as *.so.stock; sources as *.mo.stock.
#
# Usage: ./build_patched_dynawo.sh [INSTALL_DIR]   (default ~/dynawo-install)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="${1:-$HOME/dynawo-install}"
D="$INSTALL_DIR/dynawo"

"$HERE/install_dynawo_1.7.0.sh" "$INSTALL_DIR"

echo "== Snapshotting stock example outputs for the identity check =="
SNAP="$INSTALL_DIR/stock-example-outputs"
mkdir -p "$SNAP"
for j in DynaSwing/IEEE14/IEEE14_Fault DynaFlow/IEEE14/IEEE14_DisconnectLine DynaWaltz/IEEE14/IEEE14_GeneratorDisconnections; do
  n="$(basename "$j")"
  if [ ! -f "$SNAP/$n.csv" ]; then
    rm -rf "$D/examples/$j/outputs"
    "$D/dynawo.sh" jobs "$D/examples/$j/IEEE14.jobs" > /dev/null
    cp "$D/examples/$j/outputs/curves/curves.csv" "$SNAP/$n.csv"
  fi
done

echo "== Backing up and patching library sources =="
while read -r f; do
  [ -f "$D/ddb/Dynawo/$f.stock" ] || cp "$D/ddb/Dynawo/$f" "$D/ddb/Dynawo/$f.stock"
done <<'EOF'
Electrical/Loads/ElectronicLoad.mo
Electrical/HVDC/HvdcPQProp/HvdcPQProp.mo
Electrical/HVDC/HvdcPQProp/HvdcPQPropDangling.mo
Electrical/HVDC/HvdcPQProp/HvdcPQPropDiagramPQ.mo
Electrical/HVDC/HvdcPQProp/HvdcPQPropDanglingDiagramPQ.mo
Electrical/HVDC/HvdcPTanPhi/HvdcPTanPhi.mo
Electrical/HVDC/HvdcPTanPhi/HvdcPTanPhiDangling.mo
Electrical/HVDC/HvdcPTanPhi/HvdcPTanPhiDiagramPQ.mo
Electrical/HVDC/HvdcPTanPhi/HvdcPTanPhiDanglingDiagramPQ.mo
Electrical/HVDC/HvdcPV/HvdcPV.mo
Electrical/HVDC/HvdcPV/HvdcPVDangling.mo
Electrical/HVDC/HvdcPV/HvdcPVDiagramPQ.mo
Electrical/HVDC/HvdcPV/HvdcPVDanglingDiagramPQ.mo
Electrical/Machines/SignalN/BaseClasses/BaseGenerator.mo
Electrical/Controls/Machines/VoltageRegulators/Standard/BaseClasses/RectifierRegulationCharacteristic.mo
EOF
python3 "$HERE/patches/apply_model_patches.py" "$D/ddb/Dynawo"

echo "== Rebuilding affected precompiled models (this takes a while) =="
"$HERE/patches/rebuild_patched_models.sh" "$D" "$HERE/patches/rebuilt-models.txt" 3

echo "== Verifying =="
"$HERE/patched-verify/verify_patched_dynawo.sh" "$D" "$SNAP"

echo
echo "Patched Dynawo ready in: $D"
echo "Stock models kept as *.so.stock / *.mo.stock for A/B comparison."
