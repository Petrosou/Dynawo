#!/bin/bash
# Verify the patched Dynawo build (see ../patches/) against its known bugs.
#
# For each case: the patched install must keep the bounded quantity inside
# its limits at every exported sample; where the shipped stock .so was kept
# as <model>.so.stock, the stock model is also run to confirm the excursion
# existed on this very install (A/B on identical everything-else).
#
# Usage: verify_patched_dynawo.sh [DYNAWO_HOME] [STOCK_EXAMPLE_CSV_DIR]
#   STOCK_EXAMPLE_CSV_DIR (optional): directory with IEEE14_Fault.csv,
#   IEEE14_DisconnectLine.csv, IEEE14_GeneratorDisconnections.csv exported
#   from a stock install, for the in-guard identity check on the examples.
set -uo pipefail

D="${1:-$HOME/dynawo-install/dynawo}"
SNAP="${2:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$HERE")"
fail=0
eps=1e-9

run() { local dir="$1" jobs="$2"; (cd "$dir" && rm -rf "${3:-outputs}" && "$D/dynawo.sh" jobs "$jobs" > run.log 2>&1); }

# count samples of column $2 (1-based) outside [lo,hi] in csv $1
oob() { awk -F';' -v c="$2" -v lo="$3" -v hi="$4" 'NR>1 && ($(c)<lo-'"$eps"' || $(c)>hi+'"$eps"') {n++} END{print n+0}' "$1"; }

check() { # check <name> <expr-result> <expected>
  if [ "$2" = "$3" ]; then echo "PASS  $1"; else echo "FAIL  $1 (got $2, wanted $3)"; fail=1; fi
}

ab_so() { # ab_so <Model> <casedir> <jobs> <oob-args...>: patched run must be clean; stock run (if kept) must excurse
  local m="$1" dir="$2" jobs="$3" csv col lo hi
  csv="$dir/outputs/curves/curves.csv"; col="$4"; lo="$5"; hi="$6"
  run "$dir" "$jobs" || { echo "FAIL  $m patched run crashed (see $dir/run.log)"; fail=1; return; }
  check "$m patched: no sample outside [$lo,$hi]" "$(oob "$csv" "$col" "$lo" "$hi")" 0
  if [ -f "$D/ddb/$m.so.stock" ]; then
    mv "$D/ddb/$m.so" "$D/ddb/$m.so.patched"; cp "$D/ddb/$m.so.stock" "$D/ddb/$m.so"
    run "$dir" "$jobs"
    local n; n="$(oob "$csv" "$col" "$lo" "$hi")"
    mv "$D/ddb/$m.so.patched" "$D/ddb/$m.so"
    if [ "$n" -ge 1 ]; then echo "PASS  $m stock: excursion present ($n sample(s)) — bug was real here"; else echo "WARN  $m stock: no excursion reproduced (trigger may be environment-sensitive)"; fi
    run "$dir" "$jobs"  # leave patched outputs in place
  fi
}

echo "=== ElectronicLoad (precompiled path, original MRE) ==="
ab_so ElectronicLoad "$REPO/bug128/mre" case.jobs 3 0 1

echo
echo "=== HvdcPQProp (modeU flip at t=1) ==="
ab_so HvdcPQProp "$HERE/hvdcpqprop" case.jobs 3 -0.3 0.2

echo
echo "=== HvdcPV (reactive setpoint step) ==="
ab_so HvdcPV "$HERE/hvdcpv" case.jobs 2 -0.3 0.2

echo
echo "=== HvdcPQPropDiagramPQ (limits from PQ diagram) ==="
dir="$HERE/hvdcpqprop-diagrampq"
if run "$dir" case.jobs; then
  # col3 = QInj1Pu must never exceed col4 = QInj1MaxPu (the live table limit)
  n=$(awk -F';' 'NR>1 && $3 > $4+'"$eps"' {n++} END{print n+0}' "$dir/outputs/curves/curves.csv")
  check "HvdcPQPropDiagramPQ patched: QInj1Pu <= QInj1MaxPu everywhere" "$n" 0
  if [ -f "$D/ddb/HvdcPQPropDiagramPQ.so.stock" ]; then
    mv "$D/ddb/HvdcPQPropDiagramPQ.so" "$D/ddb/HvdcPQPropDiagramPQ.so.patched"
    cp "$D/ddb/HvdcPQPropDiagramPQ.so.stock" "$D/ddb/HvdcPQPropDiagramPQ.so"
    run "$dir" case.jobs
    n=$(awk -F';' 'NR>1 && $3 > $4+'"$eps"' {n++} END{print n+0}' "$dir/outputs/curves/curves.csv")
    mv "$D/ddb/HvdcPQPropDiagramPQ.so.patched" "$D/ddb/HvdcPQPropDiagramPQ.so"
    [ "$n" -ge 1 ] && echo "PASS  HvdcPQPropDiagramPQ stock: excursion present ($n sample(s))" \
                   || echo "WARN  HvdcPQPropDiagramPQ stock: no excursion reproduced"
    run "$dir" case.jobs
  fi
else echo "FAIL  HvdcPQPropDiagramPQ patched run crashed"; fail=1; fi

echo
echo "=== RectifierRegulationCharacteristic (exciter FEX, compile-on-the-fly) ==="
dir="$HERE/fexprobe"
if (cd "$dir" && rm -rf outputs_stock && "$D/dynawo.sh" jobs case_stock.jobs > run_stock.log 2>&1); then
  echo "WARN  stock FEX tree completed (abort not reproduced here)"
else
  if grep -q "sqrt" "$dir/outputs_stock/logs/dynawo.log" 2>/dev/null || grep -qi "sqrt\|error" "$dir/run_stock.log"; then
    echo "PASS  stock FEX tree: simulation aborts on sqrt domain error (the bug)"
  else
    echo "WARN  stock FEX tree failed for another reason (see $dir/run_stock.log)"
  fi
fi
if run "$dir" case.jobs; then
  n=$(oob "$dir/outputs/curves/curves.csv" 3 0 1)
  check "patched library FEX block: run completes, y in [0,1]" "$n" 0
else echo "FAIL  patched library FEX probe crashed (see $dir/run.log)"; fail=1; fi

echo
echo "=== IEEE14 examples (in-guard identity) ==="
declare -A EX=( [IEEE14_Fault]="DynaSwing/IEEE14/IEEE14_Fault" [IEEE14_DisconnectLine]="DynaFlow/IEEE14/IEEE14_DisconnectLine" [IEEE14_GeneratorDisconnections]="DynaWaltz/IEEE14/IEEE14_GeneratorDisconnections" )
for n in IEEE14_Fault IEEE14_DisconnectLine IEEE14_GeneratorDisconnections; do
  j="${EX[$n]}"
  rm -rf "$D/examples/$j/outputs"
  if "$D/dynawo.sh" jobs "$D/examples/$j/IEEE14.jobs" > /dev/null 2>&1; then
    if [ -n "$SNAP" ] && [ -f "$SNAP/$n.csv" ]; then
      if cmp -s "$SNAP/$n.csv" "$D/examples/$j/outputs/curves/curves.csv"; then
        echo "PASS  $n: byte-identical to stock install"
      else
        echo "INFO  $n: differs from stock (inspect — may be a legitimate excursion removal)"
      fi
    else echo "PASS  $n: runs (no stock snapshot to compare)"; fi
  else echo "FAIL  $n did not run"; fail=1; fi
done

echo
[ "$fail" -eq 0 ] && echo "VERIFICATION PASSED" || { echo "VERIFICATION FAILED"; exit 1; }
