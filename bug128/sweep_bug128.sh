#!/bin/bash
# Scenario sweep for the ElectronicLoad connectedShare clamp fix.
#
# Runs the stock (control/) and clamped (fix/) models, both compiled from
# source, across a matrix of scenarios and asserts for every pair:
#   - the clamped run never exports connectedShare outside [0,1];
#   - pre-event trajectories (t < 1.0) are byte-identical;
#   - the final state row is byte-identical;
#   - in scenarios where the stock model shows no excursion either
#     (voltage never enters the disconnection band mid-jump), the ENTIRE
#     curve files are byte-identical — the clamp is exactly inert in-guard.
#
# Scenario axes: fault depth (shallow: dip stays above Ud1Pu; mid-band;
# deep: dip below Ud2Pu), recoveringShare (0 / 0.7 / 1), a double-dip event
# sequence (second fault at t=1.5..1.6 hitting the recovery branch), and
# both solvers (SolverIDA, SolverSIM).
#
# Usage: ./sweep_bug128.sh [DYNAWO_HOME]
set -euo pipefail

DYNAWO_HOME="${1:-$HOME/dynawo-install/dynawo}"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# name:faultR:recoveringShare:doubledip:solver
SCENARIOS="
midband:0.009:0.7:no:IDA
shallow:0.016:0.7:no:IDA
deep:0.005:0.7:no:IDA
rshare0:0.009:0.0:no:IDA
rshare1:0.009:1.0:no:IDA
doubledip:0.009:0.7:yes:IDA
midband-sim:0.009:0.7:no:SIM
doubledip-sim:0.009:0.7:yes:SIM
"

count_oob() { awk -F';' 'NR>1 && ($3<0 || $3>1) {n++} END{print n+0}' "$1"; }

prepare() {  # prepare <variant> <dir> <faultR> <rshare> <doubledip> <solver>
  local variant="$1" dir="$2" faultR="$3" rshare="$4" doubledip="$5" solver="$6"
  cp -r "$HERE/$variant" "$dir"
  rm -rf "$dir/outputs"
  sed -i "s|\(name=\"fault_RPu\" value=\"\)[^\"]*|\1$faultR|" "$dir/case.par"
  sed -i "s|\(name=\"recoveringShare\" value=\"\)[^\"]*|\1$rshare|" "$dir/case.par"
  if [ "$doubledip" = "yes" ]; then
    sed -i 's|</parametersSet>|  <set id="FAULT2">\n    <par type="DOUBLE" name="fault_RPu" value="0.009"/>\n    <par type="DOUBLE" name="fault_XPu" value="0"/>\n    <par type="DOUBLE" name="fault_tBegin" value="1.5"/>\n    <par type="DOUBLE" name="fault_tEnd" value="1.6"/>\n  </set>\n</parametersSet>|' "$dir/case.par"
    sed -i 's|<dyn:blackBoxModel id="FAULT" lib="NodeFault" parFile="case.par" parId="FAULT"/>|<dyn:blackBoxModel id="FAULT" lib="NodeFault" parFile="case.par" parId="FAULT"/>\n  <dyn:blackBoxModel id="FAULT2" lib="NodeFault" parFile="case.par" parId="FAULT2"/>|' "$dir/case.dyd"
    sed -i 's|<dyn:connect id1="FAULT" var1="fault_terminal" id2="B1" var2="bus_terminal"/>|<dyn:connect id1="FAULT" var1="fault_terminal" id2="B1" var2="bus_terminal"/>\n  <dyn:connect id1="FAULT2" var1="fault_terminal" id2="B1" var2="bus_terminal"/>|' "$dir/case.dyd"
  fi
  if [ "$solver" = "SIM" ]; then
    sed -i 's|lib="dynawo_SolverIDA" parFile="case.par" parId="IDA"|lib="dynawo_SolverSIM" parFile="case.par" parId="SIM"|' "$dir/case.jobs"
    sed -i 's|</parametersSet>|  <set id="SIM">\n    <par type="DOUBLE" name="hMin" value="0.000001"/>\n    <par type="DOUBLE" name="hMax" value="0.01"/>\n    <par type="DOUBLE" name="kReduceStep" value="0.5"/>\n    <par type="INT" name="maxNewtonTry" value="10"/>\n    <par type="DOUBLE" name="minimalAcceptableStep" value="1e-8"/>\n    <par type="DOUBLE" name="fnormtolAlg" value="1e-10"/>\n    <par type="DOUBLE" name="fnormtolAlgJ" value="1e-10"/>\n    <par type="DOUBLE" name="fnormtolAlgInit" value="1e-10"/>\n    <par type="STRING" name="minimumModeChangeTypeForAlgebraicRestoration" value="ALGEBRAIC_J_UPDATE"/>\n  </set>\n</parametersSet>|' "$dir/case.par"
  fi
}

overall=0
printf '%-14s %10s %10s  %s\n' "scenario" "stock-OOB" "fix-OOB" "checks"
for entry in $SCENARIOS; do
  IFS=: read -r name faultR rshare doubledip solver <<< "$entry"
  for variant in control fix; do
    dir="$WORK/$name-$variant"
    prepare "$variant" "$dir" "$faultR" "$rshare" "$doubledip" "$solver"
    (cd "$dir" && "$DYNAWO_HOME/dynawo.sh" jobs case.jobs > run.log 2>&1) \
      || { echo "$name/$variant: RUN FAILED"; tail -3 "$dir/run.log"; overall=1; continue 2; }
  done
  ctrl="$WORK/$name-control/outputs/curves/curves.csv"
  fixc="$WORK/$name-fix/outputs/curves/curves.csv"
  oob_ctrl="$(count_oob "$ctrl")"; oob_fix="$(count_oob "$fixc")"
  checks=""
  [ "$oob_fix" -eq 0 ] || { checks="$checks FIX-OOB!"; overall=1; }
  diff -q <(awk -F';' '$1<1.0' "$ctrl") <(awk -F';' '$1<1.0' "$fixc") >/dev/null \
    || { checks="$checks PRE-EVENT-DIFF!"; overall=1; }
  [ "$(tail -1 "$ctrl")" = "$(tail -1 "$fixc")" ] \
    || { checks="$checks FINAL-DIFF!"; overall=1; }
  if [ "$oob_ctrl" -eq 0 ]; then
    if cmp -s "$ctrl" "$fixc"; then checks="$checks full-csv-identical"
    else checks="$checks FULL-CSV-DIFF!"; overall=1; fi
  fi
  [ -n "$checks" ] || checks=" ok"
  printf '%-14s %10s %10s %s\n' "$name" "$oob_ctrl" "$oob_fix" "$checks"
done

echo
if [ "$overall" -eq 0 ]; then
  echo "PASS: all scenarios — clamp removes every excursion and is inert in-guard."
else
  echo "FAIL: at least one check failed (see markers above)."
fi
exit "$overall"
