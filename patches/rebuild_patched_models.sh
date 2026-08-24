#!/bin/bash
# Rebuild the precompiled .so of every preassembled model affected by the
# clamp patches, from the (patched) library sources in the install's ddb.
#
# Usage: rebuild_patched_models.sh [DYNAWO_HOME] [MODEL_LIST] [JOBS]
#   DYNAWO_HOME  default $HOME/dynawo-install/dynawo
#   MODEL_LIST   default rebuilt-models.txt next to this script
#   JOBS         default 3 concurrent model builds
#
# Needs the preassembled-model descriptors from the dynawo/dynawo sources;
# set PREASSEMBLED_DIR, or a sparse clone is fetched automatically.
# Shipped .so are kept as <model>.so.stock next to the replacement.
set -euo pipefail

D="${1:-$HOME/dynawo-install/dynawo}"
HERE="$(cd "$(dirname "$0")" && pwd)"
LIST="${2:-$HERE/rebuilt-models.txt}"
JOBS="${3:-3}"
WORK="${REBUILD_WORK:-$(mktemp -d)}"

if [ -z "${PREASSEMBLED_DIR:-}" ]; then
  PREASSEMBLED_DIR="$WORK/upstream/dynawo/sources/Models/Modelica/PreassembledModels"
  if [ ! -d "$PREASSEMBLED_DIR" ]; then
    git clone --depth 1 --branch v1.7.0 --filter=blob:none --sparse https://github.com/dynawo/dynawo.git "$WORK/upstream"
    git -C "$WORK/upstream" sparse-checkout set dynawo/sources/Models/Modelica/PreassembledModels
  fi
fi

export DYNAWO_INSTALL_DIR="$D" DYNAWO_DDB_DIR="$D/ddb/" DYNAWO_SCRIPTS_DIR="$D/sbin/" \
  DYNAWO_RESOURCES_DIR="$D/share/" DYNAWO_XSD_DIR="$D/share/xsd/" \
  DYNAWO_DICTIONARIES=dictionaries_mapping DYNAWO_INSTALL_OPENMODELICA="$D/OpenModelica" \
  OPENMODELICAHOME="$D/OpenModelica" DYNAWO_PYTHON_COMMAND=python3 \
  DYNAWO_ADEPT_INSTALL_DIR="$D" DYNAWO_SUITESPARSE_INSTALL_DIR="$D" \
  DYNAWO_SUNDIALS_INSTALL_DIR="$D" DYNAWO_LIBIIDM_INSTALL_DIR="$D" \
  DYNAWO_XERCESC_INSTALL_DIR="$D" DYNAWO_LIBXML_HOME="$D" DYNAWO_BOOST_HOME="$D" \
  PATH="$D/OpenModelica/bin:$D/sbin:$PATH" \
  LD_LIBRARY_PATH="$D/lib:$D/OpenModelica/lib:${LD_LIBRARY_PATH:-}" PYTHONPATH="$D/sbin"

build_one() {
  local m="$1"
  local dir="$WORK/build/$m"
  mkdir -p "$dir"
  cp "$PREASSEMBLED_DIR/$m.xml" "$dir/"
  if (cd "$dir" && "$D/sbin/generate-preassembled" --model-list "$m.xml" --output-dir . \
        > gen.log 2>&1 && [ -f "$m.so" ]); then
    [ -f "$D/ddb/$m.so.stock" ] || cp "$D/ddb/$m.so" "$D/ddb/$m.so.stock"
    cp "$dir/$m.so" "$D/ddb/$m.so"
    echo "OK   $m"
  else
    echo "FAIL $m (log: $dir/gen.log)"
    return 1
  fi
}
export -f build_one
export D WORK PREASSEMBLED_DIR

fail=0
xargs -a "$LIST" -n1 -P"$JOBS" -I{} bash -c 'build_one "$@"' _ {} || fail=1

echo
if [ "$fail" -eq 0 ]; then
  echo "All models rebuilt. Stock .so kept as *.so.stock in $D/ddb."
else
  echo "Some models FAILED (see above). Their shipped .so are untouched."
  exit 1
fi
