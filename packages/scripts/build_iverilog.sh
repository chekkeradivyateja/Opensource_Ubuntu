#!/usr/bin/env bash
# Maintainer script: build Icarus Verilog 13.0 for packages/ (Ubuntu 24.04 x86-64).
# Trainees do NOT run this; install.py unpacks the finished package.
#
# Usage (from the repository folder, as a normal user):
#   bash packages/scripts/build_iverilog.sh
#
# What it does:
#   1. installs the build tools with apt (asks for your sudo password)
#   2. downloads the v13_0 source from GitHub into a new folder under /tmp and prints its SHA-256
#   3. builds it with prefix /opt/eda/open_ver_flow/iverilog-13.0 (the path install.py uses;
#      Icarus has this path built in, so it must be built for the final folder)
#   4. installs it there and packs it as packages/iverilog-13.0-ubuntu24.04-x86_64.tar.gz
# It does not delete anything outside its own /tmp build folder. If the target folder already
# exists it stops and tells you what to do.
set -euo pipefail

VER=13.0
TAG=v13_0
DEST=/opt/eda/open_ver_flow
PREFIX=$DEST/iverilog-$VER
REPO=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$REPO/packages/iverilog-$VER-ubuntu24.04-x86_64.tar.gz
URL=https://github.com/steveicarus/iverilog/archive/refs/tags/$TAG.tar.gz

say() { printf '\n== %s\n' "$*"; }

. /etc/os-release
[ "$ID" = ubuntu ] && [ "${VERSION_ID%%.*}" = 24 ] || { echo "FAIL: needs Ubuntu 24.04 (found $PRETTY_NAME)"; exit 1; }
[ "$(uname -m)" = x86_64 ] || { echo "FAIL: needs x86_64"; exit 1; }
[ "$(id -u)" != 0 ] || { echo "FAIL: run as your normal user, not with sudo"; exit 1; }
if [ -e "$PREFIX" ]; then
  echo "FAIL: $PREFIX already exists. Rename it first, for example:"
  echo "  mv $PREFIX $PREFIX.old"
  exit 1
fi
[ ! -e "$OUT" ] || { echo "FAIL: $OUT already exists. Rename it first."; exit 1; }

say "1. build tools (apt)"
sudo apt-get update
sudo apt-get install -y build-essential autoconf gperf flex bison zlib1g-dev libbz2-dev libreadline-dev curl

WORK=$(mktemp -d /tmp/iverilog_build_XXXXXX)
say "2. source into $WORK"
curl -fL --retry 3 -o "$WORK/src.tar.gz" "$URL"
echo "source SHA-256: $(sha256sum "$WORK/src.tar.gz" | cut -d' ' -f1)"
tar -xzf "$WORK/src.tar.gz" -C "$WORK"
SRC=$(find "$WORK" -mindepth 1 -maxdepth 1 -type d -name 'iverilog-*')

say "3. configure + build ($(nproc) cores)"
cd "$SRC"
sh autoconf.sh
./configure --prefix="$PREFIX" 2>&1 | tail -n 5
make -j"$(nproc)" 2>&1 | tail -n 5
echo "-- make check"
make check 2>&1 | tail -n 15

say "4. install into $PREFIX"
sudo install -d -o "$(id -un)" -g "$(id -gn)" "$DEST"
make install 2>&1 | tail -n 3
"$PREFIX/bin/iverilog" -V 2>&1 | head -n 1
"$PREFIX/bin/vvp" -V 2>&1 | head -n 1
echo "-- libraries vvp needs:"
ldd "$PREFIX/bin/vvp" | awk '{print "   " $1}'
if ldd "$PREFIX/bin/vvp" "$PREFIX/bin/iverilog" | grep -q 'not found'; then echo "FAIL: missing library"; exit 1; fi

say "5. pack $OUT"
tar -C "$DEST" --owner=0 --group=0 --numeric-owner -czf "$OUT" "iverilog-$VER"
ls -l "$OUT"
echo "package SHA-256: $(sha256sum "$OUT")"
echo
echo "DONE. Build folder kept for inspection: $WORK (delete it yourself when finished)."
echo "Next: bash packages/scripts/test_new_tools.sh"
