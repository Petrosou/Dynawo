#!/bin/bash
# Verify the patched Dynawo build (see ../patches/) against its known bugs.
# Every check gates the exit status: patched models must stay in-bounds at
# every exported sample, the kept stock models (<model>.so.stock,
# <source>.mo.stock) must reproduce each excursion/abort on this same
# install, and stock-vs-patched trajectories must be byte-identical before
# the first event of each case.
#
# Usage: verify_patched_dynawo.sh [DYNAWO_HOME] [STOCK_EXAMPLE_CSV_DIR]
set -uo pipefail

D="${1:-$HOME/dynawo-install/dynawo}"
SNAP="${2:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$HERE")"
fail=0
eps=1e-9

echo "== Provenance =="
echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "dynawo: $("$D/dynawo.sh" version 2>/dev/null)"
echo "repo state: parent commit $(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo unknown), $(git -C "$REPO" status --porcelain 2>/dev/null | wc -l) uncommitted change(s) at run time"
echo "  (RESULTS.txt is written by this run and committed afterwards; its own commit necessarily postdates this stamp)"
echo "suite md5: $(md5sum "$HERE/verify_patched_dynawo.sh" | cut -d" " -f1)  patcher md5: $(md5sum "$REPO/patches/apply_model_patches.py" | cut -d" " -f1)"
echo "host: $(uname -sr)"
for m in ElectronicLoad HvdcPQProp HvdcPV HvdcPQPropDiagramPQ StaticVarCompensatorPVProp; do
  echo "md5 $m.so: $(md5sum "$D/ddb/$m.so" 2>/dev/null | cut -d" " -f1)"
done
echo

# If the suite is interrupted inside any stock/patched swap, restore the
# patched artifacts on exit (covers every *.patchedtmp swap region at once).
trap 'for f in "$D"/ddb/*.patchedtmp "$D"/ddb/Dynawo/Electrical/Controls/Machines/VoltageRegulators/Standard/BaseClasses/*.patchedtmp; do [ -e "$f" ] && mv -f "$f" "${f%.patchedtmp}"; done' EXIT

pass() { echo "PASS  $1"; }
flunk() { echo "FAIL  $1"; fail=1; }

run() { (cd "$1" && rm -rf outputs && "$D/dynawo.sh" jobs "$2" > run.log 2>&1); }

oob() { # oob <csv> <col> <lo> <hi>
  awk -F';' -v c="$2" -v lo="$3" -v hi="$4" -v e="$eps" \
    'NR>1 && ($(c)<lo-e || $(c)>hi+e) {n++} END{print n+0}' "$1"
}

# Full A/B on one precompiled model:
#  patched: runs, 0 samples of col outside [lo,hi]
#  stock:   >=1 sample outside (or the run itself fails, if allow_crash=yes)
#  identity: rows with t < t_event byte-identical between the two runs
ab_so() { # ab_so <Model> <dir> <col> <lo> <hi> <t_event> <allow_stock_crash>
  local m="$1" dir="$2" col="$3" lo="$4" hi="$5" tev="$6" crashok="${7:-no}"
  local csv="$dir/outputs/curves/curves.csv" keep="$dir/patched-curves.csv"
  if ! run "$dir" case.jobs; then flunk "$m patched run crashed (see $dir/run.log)"; return; fi
  cp "$csv" "$keep"
  [ "$(oob "$keep" "$col" "$lo" "$hi")" -eq 0 ] \
    && pass "$m patched: all samples in [$lo,$hi]" \
    || flunk "$m patched: sample(s) outside [$lo,$hi]"
  if [ ! -f "$D/ddb/$m.so.stock" ]; then flunk "$m: no .so.stock kept, cannot A/B"; return; fi
  mv "$D/ddb/$m.so" "$D/ddb/$m.so.patchedtmp"; cp "$D/ddb/$m.so.stock" "$D/ddb/$m.so"
  if run "$dir" case.jobs; then
    local n; n="$(oob "$csv" "$col" "$lo" "$hi")"
    [ "$n" -ge 1 ] && pass "$m stock: excursion present ($n sample(s))" \
                   || flunk "$m stock: expected excursion did not reproduce"
    diff <(awk -F';' -v t="$tev" '$1<t' "$keep") <(awk -F';' -v t="$tev" '$1<t' "$csv") > /dev/null \
      && pass "$m stock/patched byte-identical before t=$tev" \
      || flunk "$m stock/patched differ before the first event"
  else
    if [ "$crashok" = "yes" ] && grep -Eq "IDA fails to solve|KINSOL fails to solve" "$dir/run.log"; then
      pass "$m stock: run fails with the mechanism's solver signature"
    else
      flunk "$m stock run failed without the expected solver signature (see $dir/run.log)"
    fi
  fi
  mv "$D/ddb/$m.so.patchedtmp" "$D/ddb/$m.so"
  run "$dir" case.jobs   # leave patched outputs in place
}

echo "=== ElectronicLoad: fault MRE (share must stay in [0,1]) ==="
ab_so ElectronicLoad "$REPO/bug128/mre" 3 0 1 1.0
umin=$(awk -F';' 'NR>1 && $1>=1.0 && $1<=1.1 {if(min==""||$2<min)min=$2} END{print min}' "$REPO/bug128/mre/patched-curves.csv")
awk -v v="$umin" 'BEGIN{exit !(v>0.5 && v<0.7)}' \
  && pass "ElectronicLoad trigger armed: fault dips bus into the band (min U=$umin)" \
  || flunk "ElectronicLoad trigger NOT armed: min fault U=$umin outside (0.5,0.7)"
awk -F';' 'NR>1{print $1";"$3}' "$REPO/bug128/mre/patched-curves.csv" > "$HERE/artifacts/electronicload-fault-patched-share.csv"

echo
echo "=== ElectronicLoad: switch-off/reconnect (stock injects power; patched recovers recoveringShare) ==="
dir="$HERE/reconnect"
if run "$dir" case.jobs; then
  fin=$(tail -1 "$dir/outputs/curves/curves.csv" | cut -d';' -f3)
  awk -v v="$fin" 'BEGIN{exit !(v>0.7-1e-6 && v<0.7+1e-6)}' \
    && pass "reconnect patched: final share = recoveringShare (0.7)" \
    || flunk "reconnect patched: final share $fin != 0.7"
  if [ -f "$D/ddb/ElectronicLoad.so.stock" ]; then
    mv "$D/ddb/ElectronicLoad.so" "$D/ddb/ElectronicLoad.so.patchedtmp"
    cp "$D/ddb/ElectronicLoad.so.stock" "$D/ddb/ElectronicLoad.so"
    run "$dir" case.jobs
    fin=$(tail -1 "$dir/outputs/curves/curves.csv" | cut -d';' -f3)
    mv "$D/ddb/ElectronicLoad.so.patchedtmp" "$D/ddb/ElectronicLoad.so"
    awk -v v="$fin" 'BEGIN{exit !(v<-1e-6)}' \
      && pass "reconnect stock: sustained negative share ($fin) — load injecting power" \
      || flunk "reconnect stock: expected negative share, got $fin"
    run "$dir" case.jobs
  else flunk "reconnect: no ElectronicLoad.so.stock"; fi
else flunk "reconnect patched run crashed"; fi

echo
echo "=== ElectronicLoad: depressed-voltage initialization (third entry path, review round 3) ==="
dir="$HERE/depressed-init"
if run "$dir" case.jobs; then
  fin=$(tail -1 "$dir/outputs/curves/curves.csv" | cut -d';' -f3)
  awk -v v="$fin" 'BEGIN{exit !(v>0.3-1e-6 && v<0.3+1e-6)}' \
    && pass "depressed-init patched: final share = recoveringShare (0.3), UMinPu floored" \
    || flunk "depressed-init patched: final share $fin != 0.3"
  if [ -f "$D/ddb/ElectronicLoad.so.stock" ]; then
    mv "$D/ddb/ElectronicLoad.so" "$D/ddb/ElectronicLoad.so.patchedtmp"
    cp "$D/ddb/ElectronicLoad.so.stock" "$D/ddb/ElectronicLoad.so"
    run "$dir" case.jobs
    fin=$(tail -1 "$dir/outputs/curves/curves.csv" | cut -d';' -f3)
    mv "$D/ddb/ElectronicLoad.so.patchedtmp" "$D/ddb/ElectronicLoad.so"
    awk -v v="$fin" 'BEGIN{exit !(v<-0.5)}' \
      && pass "depressed-init stock: sustained share $fin in-guard at healthy voltage" \
      || flunk "depressed-init stock: expected strongly negative share, got $fin"
    tail -3 "$dir/outputs/curves/curves.csv" > "$HERE/artifacts/depressed-init-stock-tail.csv"
    run "$dir" case.jobs
  else flunk "depressed-init: no ElectronicLoad.so.stock"; fi
else flunk "depressed-init patched run crashed"; fi

echo
echo "=== HvdcPQProp (modeU flip at t=1) ==="
ab_so HvdcPQProp "$HERE/hvdcpqprop" 3 -0.3 0.2 1.0

echo
echo "=== HvdcPV (reactive setpoint step, SolverSIM) ==="
ab_so HvdcPV "$HERE/hvdcpv" 2 -0.3 0.2 1.0

echo
echo "=== HvdcPQPropDiagramPQ (live PQ-diagram limit) ==="
dir="$HERE/hvdcpqprop-diagrampq"; m=HvdcPQPropDiagramPQ
if run "$dir" case.jobs; then
  cp "$dir/outputs/curves/curves.csv" "$dir/patched-curves.csv"
  n=$(awk -F';' -v e="$eps" 'NR>1 && $3 > $4+e {n++} END{print n+0}' "$dir/patched-curves.csv")
  [ "$n" -eq 0 ] && pass "$m patched: QInj1Pu <= QInj1MaxPu everywhere" \
                 || flunk "$m patched: QInj1Pu exceeds its live limit"
  mv "$D/ddb/$m.so" "$D/ddb/$m.so.patchedtmp"; cp "$D/ddb/$m.so.stock" "$D/ddb/$m.so"
  run "$dir" case.jobs
  n=$(awk -F';' -v e="$eps" 'NR>1 && $3 > $4+e {n++} END{print n+0}' "$dir/outputs/curves/curves.csv")
  [ "$n" -ge 1 ] && pass "$m stock: excursion present ($n sample(s))" \
                 || flunk "$m stock: expected excursion did not reproduce"
  diff <(awk -F';' '$1<1.0' "$dir/patched-curves.csv") <(awk -F';' '$1<1.0' "$dir/outputs/curves/curves.csv") > /dev/null \
    && pass "$m stock/patched byte-identical before t=1.0" \
    || flunk "$m stock/patched differ before the first event"
  mv "$D/ddb/$m.so.patchedtmp" "$D/ddb/$m.so"; run "$dir" case.jobs
else flunk "$m patched run crashed"; fi

echo
echo "=== SVarCPVProp (plain bus fault; stock IDA aborts) ==="
ab_so StaticVarCompensatorPVProp "$HERE/svarcpvprop" 4 -0.5 0.5 1.0 yes
rawmax=$(awk -F';' 'NR>1 {if(max==""||$3>max)max=$3} END{print max}' "$HERE/svarcpvprop/patched-curves.csv")
awk -v v="$rawmax" 'BEGIN{exit !(v>0.5)}' \
  && pass "SVarCPVProp trigger armed: raw susceptance crossed the limit (max=$rawmax)" \
  || flunk "SVarCPVProp trigger NOT armed: raw never crossed BMaxPu (max=$rawmax)"

echo
echo "=== SVarCPV non-Prop (KNOWN LIMITATION — asserts the defect is STILL PRESENT, see its README) ==="
dir="$HERE/svarcpv-unfixed"
if run "$dir" case.jobs; then
  n=$(oob "$dir/outputs/curves/curves.csv" 3 -0.5 0.5)
  [ "$n" -ge 1 ] && pass "SVarCPV (unpatched by design): defect still present ($n out-of-bound sample(s)) — as documented" \
                 || flunk "SVarCPV: documented defect no longer reproduces — update the known-limitation docs"
else
  grep -Eq "IDA fails to solve|KINSOL fails to solve" "$dir/run.log" \
    && pass "SVarCPV (unpatched by design): run fails with the mechanism's solver signature — as documented" \
    || flunk "SVarCPV: run failed without the expected solver signature (see $dir/run.log)"
fi

echo
echo "=== RectifierRegulationCharacteristic (same probe, stock vs patched library source) ==="
dir="$HERE/fexprobe"
FEXMO="$D/ddb/Dynawo/Electrical/Controls/Machines/VoltageRegulators/Standard/BaseClasses/RectifierRegulationCharacteristic.mo"
if [ -f "$FEXMO.stock" ]; then
  cp "$FEXMO" "$FEXMO.patchedtmp"
  trap 'cp "$FEXMO.patchedtmp" "$FEXMO" 2>/dev/null' EXIT
  cp "$FEXMO.stock" "$FEXMO"
  if (cd "$dir" && rm -rf outputs && "$D/dynawo.sh" jobs case.jobs > run_stock.log 2>&1); then
    flunk "FEX stock source: expected sqrt abort, run completed"
  else
    grep -qi "sqrt" "$dir/outputs/logs/dynawo.log" "$dir/run_stock.log" 2>/dev/null \
      && pass "FEX stock source: simulation aborts on sqrt domain error" \
      || flunk "FEX stock source: failed for another reason (see $dir/run_stock.log)"
  fi
  cp "$FEXMO.patchedtmp" "$FEXMO"; rm -f "$FEXMO.patchedtmp"; trap - EXIT
else flunk "FEX: no .mo.stock kept, cannot A/B"; fi
if run "$dir" case.jobs; then
  [ "$(oob "$dir/outputs/curves/curves.csv" 4 0 1)" -eq 0 ] \
    && pass "FEX patched source: run completes, y in [0,1]" \
    || flunk "FEX patched source: y left [0,1]"
  ufault=$(awk -F';' 'NR>1 && $1>=1.0 && $1<1.1 {if(min==""||$3<min)min=$3} END{print min}' "$dir/outputs/curves/curves.csv")
  upost=$(awk -F';' 'NR>1 && $1>=1.1 {if(max==""||$3>max)max=$3} END{print max}' "$dir/outputs/curves/curves.csv")
  awk -v a="$ufault" 'BEGIN{exit !(a>0.4330127 && a<0.75)}' \
    && pass "FEX witness 1: fault holds u inside the sqrt branch guard (min=$ufault in (ULow,UHigh)) — branch armed" \
    || flunk "FEX witness 1 NOT met: fault-window u=$ufault outside the sqrt branch guard"
  awk -v b="$upost" 'BEGIN{exit !(b>0.8660254)}' \
    && pass "FEX witness 2: post-clearing u crosses sqrt(UHigh) (max=$upost) — the value fatal to the frozen branch" \
    || flunk "FEX witness 2 NOT met: post-clearing u=$upost never crossed sqrt(UHigh)"
  awk -F';' 'NR>1{print $1";"$3";"$4}' "$dir/outputs/curves/curves.csv" > "$HERE/artifacts/fexprobe-patched-u-y.csv"
else flunk "FEX patched source: probe crashed (see $dir/run.log)"; fi

echo
echo "=== IEEE14 examples (regression vs stock snapshots; DynaFlow leg exercises rebuilt GeneratorPVSignalN) ==="
declare -A EX=( [IEEE14_Fault]="DynaSwing/IEEE14/IEEE14_Fault" [IEEE14_DisconnectLine]="DynaFlow/IEEE14/IEEE14_DisconnectLine" [IEEE14_GeneratorDisconnections]="DynaWaltz/IEEE14/IEEE14_GeneratorDisconnections" )
for n in IEEE14_Fault IEEE14_DisconnectLine IEEE14_GeneratorDisconnections; do
  j="${EX[$n]}"
  rm -rf "$D/examples/$j/outputs"
  if "$D/dynawo.sh" jobs "$D/examples/$j/IEEE14.jobs" > /dev/null 2>&1; then
    if [ -n "$SNAP" ] && [ -f "$SNAP/$n.csv" ]; then
      cmp -s "$SNAP/$n.csv" "$D/examples/$j/outputs/curves/curves.csv" \
        && pass "$n: byte-identical to stock install" \
        || flunk "$n: differs from stock snapshot"
    else flunk "$n: no stock snapshot provided — identity not checkable"; fi
  else flunk "$n did not run"; fi
done

echo
if [ "$fail" -eq 0 ]; then echo "VERIFICATION PASSED (every listed check gates)"; else echo "VERIFICATION FAILED"; exit 1; fi
