#!/usr/bin/env bash
# Maintainer script: build Icarus Verilog 13.0 for packages/ (Ubuntu 24.04 x86-64).
# Trainees do NOT run this; install.py unpacks the finished package.
#
# Usage (from the repository folder, as a normal user):
#   bash packages/scripts/build_iverilog.sh
#   bash packages/scripts/build_iverilog.sh --pack-only
#        (Icarus is already installed in /opt by an earlier run of this script:
#         only check it and make the package; nothing is downloaded or rebuilt)
#
# What it does:
#   1. installs the build tools with apt (asks for your sudo password)
#   2. downloads the v13_0 source from GitHub into a new folder under ~/repo_tmp and checks its SHA-256
#   3. builds it with prefix /opt/eda/open_ver_flow/iverilog-13.0 (the path install.py uses;
#      Icarus has this path built in, so it must be built for the final folder)
#   4. installs it there, checks it, and packs it as packages/iverilog-13.0-ubuntu24.04-x86_64.tar.gz
# It deletes nothing (no rm). If the target folder or package already exists it stops and tells you
# what to do. The build folder in ~/repo_tmp is kept.
set -euo pipefail

VER=13.0
TAG=v13_0
DEST=/opt/eda/open_ver_flow
PREFIX=$DEST/iverilog-$VER
REPO=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$REPO/packages/iverilog-$VER-ubuntu24.04-x86_64.tar.gz
URL=https://github.com/steveicarus/iverilog/archive/refs/tags/$TAG.tar.gz
# same archive as the 24 Nov 2026 Ubuntu build test
SRC_SHA256=c897bbfa9848688982c6d5c30529fc29d68df0b9ff22ffa73bad89db73a7ce49

say() { printf '\n== %s\n' "$*"; }
# first output line of a command; never stops the script (a "| head" would, under pipefail)
first_line() { local out; out=$("$@" 2>&1 || true); printf '%s\n' "${out%%$'\n'*}"; }

PACK_ONLY=0
[ "${1:-}" = --pack-only ] && PACK_ONLY=1

. /etc/os-release
[ "$ID" = ubuntu ] && [ "${VERSION_ID%%.*}" = 24 ] || { echo "FAIL: needs Ubuntu 24.04 (found $PRETTY_NAME)"; exit 1; }
[ "$(uname -m)" = x86_64 ] || { echo "FAIL: needs x86_64"; exit 1; }
[ "$(id -u)" != 0 ] || { echo "FAIL: run as your normal user, not with sudo"; exit 1; }
[ ! -e "$OUT" ] || { echo "FAIL: $OUT already exists. Move it away first, for example: mv $OUT ~/repo_tmp/"; exit 1; }
if [ $PACK_ONLY = 1 ]; then
  [ -x "$PREFIX/bin/iverilog" ] || { echo "FAIL: --pack-only needs an installed $PREFIX (run without --pack-only)"; exit 1; }
  WORK="(none: --pack-only)"
elif [ -e "$PREFIX" ]; then
  echo "FAIL: $PREFIX already exists. If an earlier run of this script built it, make only the package:"
  echo "  bash packages/scripts/build_iverilog.sh --pack-only"
  echo "To build again instead, rename it first:  mv -T $PREFIX $PREFIX.old"
  exit 1
fi

if [ $PACK_ONLY = 0 ]; then
  say "1. build tools (apt)"
  sudo apt-get update
  sudo apt-get install -y build-essential autoconf gperf flex bison zlib1g-dev libbz2-dev libreadline-dev curl

  mkdir -p "$HOME/repo_tmp"
  WORK=$(mktemp -d "$HOME/repo_tmp/iverilog_build_XXXX")
  say "2. source into $WORK"
  curl -fL --retry 3 -o "$WORK/src.tar.gz" "$URL"
  got=$(sha256sum "$WORK/src.tar.gz" | cut -d' ' -f1)
  if [ "$got" != "$SRC_SHA256" ]; then echo "FAIL: source SHA-256 is $got, expected $SRC_SHA256"; exit 1; fi
  echo "PASS: source SHA-256 $got"
  tar -xzf "$WORK/src.tar.gz" -C "$WORK" --no-same-owner
  SRC=$(find "$WORK" -mindepth 1 -maxdepth 1 -type d -name 'iverilog-*')

  say "3. configure + build ($(nproc) cores)"
  cd "$SRC"
  sh autoconf.sh
  ./configure --prefix="$PREFIX" > "$WORK/configure.txt" 2>&1 || { tail -n 20 "$WORK/configure.txt"; echo "FAIL: configure"; exit 1; }
  make -j"$(nproc)" > "$WORK/make.txt" 2>&1 || { tail -n 20 "$WORK/make.txt"; echo "FAIL: make"; exit 1; }
  echo "PASS: make"
  make check > "$WORK/check.txt" 2>&1 || { tail -n 20 "$WORK/check.txt"; echo "FAIL: make check"; exit 1; }
  tail -n 5 "$WORK/check.txt"
  echo "PASS: make check"

  say "4. install into $PREFIX"
  sudo install -d -o "$(id -un)" -g "$(id -gn)" "$DEST"
  make install > "$WORK/install.txt" 2>&1 || { tail -n 20 "$WORK/install.txt"; echo "FAIL: make install"; exit 1; }
  echo "PASS: make install"
fi

say "check $PREFIX"
v=$(first_line "$PREFIX/bin/iverilog" -V); echo "$v"
first_line "$PREFIX/bin/vvp" -V
case "$v" in *"version $VER"*) ;; *) echo "FAIL: $PREFIX is not Icarus $VER"; exit 1 ;; esac
echo "-- libraries vvp needs:"
ldd "$PREFIX/bin/vvp" | awk '{print "   " $1}'
missing=$(ldd "$PREFIX/bin/vvp" "$PREFIX/bin/iverilog" | grep -c 'not found' || true)
[ "$missing" = 0 ] || { echo "FAIL: $missing library(ies) not found, see the list above"; exit 1; }
echo "PASS: Icarus $VER runs, all libraries found"

say "5. pack $OUT"
tar -C "$DEST" --owner=0 --group=0 --numeric-owner -czf "$OUT" "iverilog-$VER"
ls -l "$OUT"
echo "package SHA-256: $(sha256sum "$OUT")"
echo
echo "DONE. Build folder: $WORK"
echo "Next: bash packages/scripts/test_new_tools.sh"
