#!/bin/bash
# A/B verification for the ElectronicLoad connectedShare clamp fix.
#
# control/ runs a verbatim copy of the Dynawo v1.7.0 ElectronicLoad model,
# compiled from source; fix/ runs the same model with the piecewise
# connectedShare expressions clamped to [0,1]. Both simulate the same case:
# an InfiniteBus feeding one electronic load through a line, with a node
# fault from t=1.0 to t=1.1 s that sags the voltage into the load's
# disconnection band [Ud2Pu=0.5, Ud1Pu=0.7].
#
# Expected: the control reproduces the bug (a connectedShare sample of ~2.5
# exported at the fault-clearing instant), the fix produces no sample outside
# [0,1], and the two runs are identical everywhere except that instant.
#
# Usage: ./verify_bug128_fix.sh [DYNAWO_HOME]
#   DYNAWO_HOME defaults to $HOME/dynawo-install/dynawo
set -euo pipefail

DYNAWO_HOME="${1:-$HOME/dynawo-install/dynawo}"
HERE="$(cd "$(dirname "$0")" && pwd)"

count_out_of_range() {
  awk -F';' 'NR>1 && ($3<0 || $3>1) {n++} END{print n+0}' "$1"
}

for variant in control fix; do
  echo "== Running $variant case (compiles the Modelica model on the fly) =="
  rm -rf "$HERE/$variant/outputs"
  (cd "$HERE/$variant" && "$DYNAWO_HOME/dynawo.sh" jobs case.jobs)
done

CTRL="$HERE/control/outputs/curves/curves.csv"
FIX="$HERE/fix/outputs/curves/curves.csv"

oob_ctrl="$(count_out_of_range "$CTRL")"
oob_fix="$(count_out_of_range "$FIX")"
echo
echo "control: $oob_ctrl exported sample(s) with connectedShare outside [0,1]"
awk -F';' 'NR>1 && ($3<0 || $3>1) {print "         t=" $1 "  U=" $2 "  share=" $3}' "$CTRL"
echo "fix:     $oob_fix exported sample(s) with connectedShare outside [0,1]"

fail=0
if [ "$oob_ctrl" -lt 1 ]; then
  echo "FAIL: control did not reproduce the out-of-range connectedShare"; fail=1
fi
if [ "$oob_fix" -ne 0 ]; then
  echo "FAIL: fix still exports connectedShare outside [0,1]"; fail=1
fi
if ! diff <(awk -F';' '$1<1.1' "$CTRL") <(awk -F';' '$1<1.1' "$FIX") > /dev/null; then
  echo "FAIL: pre-event trajectories differ (clamp changed in-guard behavior)"; fail=1
fi
if [ "$(tail -1 "$CTRL")" != "$(tail -1 "$FIX")" ]; then
  echo "FAIL: final states differ (clamp changed the equilibrium)"; fail=1
fi
[ "$fail" -eq 0 ] || exit 1

echo
echo "PASS: bug reproduced in control, absent with the clamp, and the clamp"
echo "      left pre-event trajectories and the final state byte-identical."
