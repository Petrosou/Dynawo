#!/bin/bash
# Install Dynawo 1.7.0 (official pre-built Linux release) and verify it works.
#
# Dynawo is RTE's hybrid C++/Modelica open-source time-domain simulation tool
# for power systems: https://dynawo.github.io
#
# Usage: ./install_dynawo_1.7.0.sh [INSTALL_DIR]
#   INSTALL_DIR defaults to $HOME/dynawo-install
set -euo pipefail

VERSION="1.7.0"
INSTALL_DIR="${1:-$HOME/dynawo-install}"
ARCHIVE="Dynawo_Linux_v${VERSION}.zip"
URL="https://github.com/dynawo/dynawo/releases/download/v${VERSION}/${ARCHIVE}"

echo "== 1/4 Installing system prerequisites =="
# unzip/curl to fetch and unpack the release; g++ and make are needed by the
# bundled OpenModelica toolchain when a job compiles Modelica models on the fly.
if command -v apt-get >/dev/null; then
  SUDO=""
  [ "$(id -u)" -ne 0 ] && SUDO="sudo"
  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq curl unzip g++ make
fi

echo "== 2/4 Downloading Dynawo v${VERSION} (~157 MB) =="
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
if [ ! -f "$ARCHIVE" ]; then
  curl -sSL -o "$ARCHIVE" "$URL"
fi

echo "== 3/4 Unpacking =="
if [ ! -d dynawo ]; then
  unzip -q "$ARCHIVE"
fi

echo "== 4/4 Smoke test =="
cd dynawo
./dynawo.sh version

echo
echo "Dynawo installed in: $INSTALL_DIR/dynawo"
echo "Run a simulation with, e.g.:"
echo "  cd $INSTALL_DIR/dynawo"
echo "  ./dynawo.sh jobs examples/DynaSwing/IEEE14/IEEE14_Fault/IEEE14.jobs"
