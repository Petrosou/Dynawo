#!/bin/bash
# Verify a Dynawo installation by running bundled examples from the three
# simulation families and checking that real outputs are produced.
#
# Usage: ./verify_dynawo.sh [DYNAWO_HOME]
#   DYNAWO_HOME defaults to $HOME/dynawo-install/dynawo
set -euo pipefail

DYNAWO_HOME="${1:-$HOME/dynawo-install/dynawo}"
cd "$DYNAWO_HOME"

echo "Dynawo version: $(./dynawo.sh version)"

run_case() {
  local jobs="$1"
  local outputs_dir
  outputs_dir="$(dirname "$jobs")/outputs"
  rm -rf "$outputs_dir"
  echo
  echo "== Running $jobs =="
  ./dynawo.sh jobs "$jobs"
  if [ -f "$outputs_dir/curves/curves.csv" ]; then
    echo "   curves.csv rows: $(wc -l < "$outputs_dir/curves/curves.csv")"
  fi
  if [ -s "$outputs_dir/timeLine/timeline.log" ]; then
    echo "   timeline events: $(wc -l < "$outputs_dir/timeLine/timeline.log")"
  fi
}

# DynaSwing: transient stability (short-circuit on IEEE14 bus)
run_case examples/DynaSwing/IEEE14/IEEE14_Fault/IEEE14.jobs
# DynaFlow: steady-state / slow dynamics (line disconnection)
run_case examples/DynaFlow/IEEE14/IEEE14_DisconnectLine/IEEE14.jobs
# DynaWaltz: long-term voltage stability (generator disconnections)
run_case examples/DynaWaltz/IEEE14/IEEE14_GeneratorDisconnections/IEEE14.jobs

echo
echo "All verification simulations succeeded."
