#!/usr/bin/env bash
# Build the instrumented upstream MiniSat master reference (github.com/meelgroup/minisat
# master 664490d: DRUP/DRAT proof output, rdb-at, show_info) and print traces / proofs.
# The default binaries are the FIXED master (fixes.patch + -DMASTER_FIXES in driver.cpp: the
# Kotlin port's default target); the *_raw binaries are master as is (bug repros).
# Writes nothing outside build/ (no golden files, no proof files; compare live).
#
#   build_and_trace.sh --build-only            build build/minisat_master_trace (binary DRUP,
#                                              master's default), build/minisat_master_trace_ascii,
#                                              and the raw ones build/minisat_master_raw_trace(_ascii)
#   build_and_trace.sh --trace [args...]       ONE trace to stdout: LSTRACE=1, given driver
#                                              args; drops the 's ...' verdict line and the
#                                              "c [reduceDB]" lines of --show-info=1. Rebuilds if stale.
#   build_and_trace.sh --proof bin|ascii [args...]
#                                              the DRUP proof bytes on stdout (--drup=1);
#                                              verdict on stderr. Rebuilds if stale.
#   build_and_trace.sh                         build, then for every ../cnf/*.cnf (php_10_9
#                                              only with BIG=1) and --simp=0/1: trace twice
#                                              and binary + ASCII proof twice, require the
#                                              same checksum (determinism), print a summary.
#
# Steps per variant: copy upstream/minisat (verbatim, never edited) to build/src-<v>/minisat,
# apply trace.patch, for the fixed variants fixes.patch, for ascii also ascii.patch (drops
# master's '#define BIN_DRUP' so the upstream #else branches, the ASCII proof, are compiled), compile core/Solver.cc
# simp/SimpSolver.cc utils/Options.cc + driver.cpp (not the Main.cc apps, not utils/System.cc:
# master's System.cc does not compile on macOS; driver.cpp stubs the one symbol the linked code
# references, memUsedPeak(bool), used only by the never-called Solver::printStats), link.
# Compiler: clang++ (like ../minisat-full). bash 3.2 compatible. Fails loudly.
set -euo pipefail

die () { echo "build_and_trace.sh: error: $*" 1>&2; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"
shadow="$(cd "$here/.." && pwd)"
upstream="$here/upstream"
patchfile="$here/trace.patch"
asciipatch="$here/ascii.patch"
fixespatch="$here/fixes.patch"
shim="$shadow/minisat-full/zlib-shim"
build="$here/build"
bin="$build/minisat_master_trace"
bin_ascii="$build/minisat_master_trace_ascii"
bin_raw="$build/minisat_master_raw_trace"
bin_raw_ascii="$build/minisat_master_raw_trace_ascii"
cnfdir="$shadow/cnf"

CXX="${CXX:-clang++}"
# Same flags as ../minisat-full (upstream release flags with -O2, -std=c++98,
# -ffp-contract=off), plus -Dfwrite_unlocked=fwrite: master's binDRUP_flush calls the
# glibc-only fwrite_unlocked, which macOS does not have; fwrite has the same signature and
# writes the same bytes (single-threaded).
CXXFLAGS="-O2 -std=c++98 -ffp-contract=off -DNDEBUG -D__STDC_LIMIT_MACROS -D__STDC_FORMAT_MACROS -Dfwrite_unlocked=fwrite"

# build_variant <name> <output binary> <extra define or empty> <extra patches...>
build_variant () {
  local name="$1" out="$2" def="$3"
  shift 3
  local src="$build/src-$name" objdir="$build/obj-$name" pids="" failed=0 f o p x
  echo "[build] $name: copying upstream/minisat -> build/src-$name, applying trace.patch $*" 1>&2
  rm -rf "$src" "$objdir"
  mkdir -p "$src" "$objdir"
  cp -R "$upstream/minisat" "$src/minisat"
  ( cd "$src" && patch -p1 --quiet --forward < "$patchfile" ) \
    || die "trace.patch does not apply cleanly to upstream/"
  for x in "$@"; do
    ( cd "$src" && patch -p1 --quiet --forward < "$x" ) \
      || die "$(basename "$x") does not apply cleanly"
  done
  echo "[build] $name: $CXX $CXXFLAGS $def" 1>&2
  for f in "$src/minisat/core/Solver.cc" "$src/minisat/simp/SimpSolver.cc" \
           "$src/minisat/utils/Options.cc" "$here/driver.cpp"; do
    o="$objdir/$(basename "$f" | sed 's/\.[a-z]*$//').o"
    # -w hides upstream's warnings (all from upstream; drop -w to see them).
    "$CXX" $CXXFLAGS $def -w -I"$shim" -I"$src" -c "$f" -o "$o" &
    pids="$pids $!"
  done
  for p in $pids; do wait "$p" || failed=1; done
  [ "$failed" = 0 ] || die "compilation failed (see compiler output above)"
  "$CXX" $CXXFLAGS -o "$out" "$objdir"/*.o || die "linking failed"
  rm -rf "$objdir"
  echo "[build] built $out" 1>&2
}

build_it () {
  command -v "$CXX" >/dev/null 2>&1 || die "compiler '$CXX' not found (set CXX=...; see README.md)"
  command -v patch >/dev/null 2>&1 || die "'patch' not found"
  [ -f "$upstream/minisat/core/Solver.cc" ] || die "missing $upstream/minisat/core/Solver.cc"
  [ -f "$patchfile" ] || die "missing $patchfile"
  [ -f "$asciipatch" ] || die "missing $asciipatch"
  [ -f "$fixespatch" ] || die "missing $fixespatch"
  [ -f "$shim/zlib.h" ] || die "missing $shim/zlib.h"
  mkdir -p "$build"
  build_variant bin "$bin" -DMASTER_FIXES "$fixespatch"
  build_variant ascii "$bin_ascii" -DMASTER_FIXES "$fixespatch" "$asciipatch"
  build_variant raw "$bin_raw" ""
  build_variant raw-ascii "$bin_raw_ascii" "" "$asciipatch"
  rm -rf "$build"/src-*
}

is_stale () {
  local f b
  for b in "$bin" "$bin_ascii" "$bin_raw" "$bin_raw_ascii"; do
    [ -x "$b" ] || return 0
    for f in "$patchfile" "$asciipatch" "$fixespatch" "$here/driver.cpp" "$shim/zlib.h" "$0"; do
      [ "$f" -nt "$b" ] && return 0
    done
  done
  return 1
}

# run_trace <args...>: the trace on stdout without the 's ...' verdict line and without
# show_info's "c [reduceDB]" lines; exit code 10/20/0 is a verdict, anything else fails.
run_trace () {
  local rc
  set +e
  LSTRACE=1 "$bin" "$@" | grep -v '^s \|^c \[reduceDB\]'
  rc=${PIPESTATUS[0]}
  set -e
  case "$rc" in
    0|10|20) ;;
    *) echo "build_and_trace.sh: error: $bin $* exited with $rc" 1>&2; return 1 ;;
  esac
}

# run_proof bin|ascii <args...>: the proof bytes on stdout (verdict on stderr, dropped).
run_proof () {
  local b rc
  case "$1" in
    bin) b="$bin" ;;
    ascii) b="$bin_ascii" ;;
    *) die "--proof needs bin or ascii, got '$1'" ;;
  esac
  shift
  set +e
  env -u LSTRACE "$b" --drup=1 "$@" 2>/dev/null
  rc=$?
  set -e
  case "$rc" in
    0|10|20) ;;
    *) echo "build_and_trace.sh: error: $b --drup=1 $* exited with $rc" 1>&2; return 1 ;;
  esac
}

if [ "${1:-}" = "--build-only" ]; then
  [ $# -eq 1 ] || die "--build-only takes no further arguments"
  build_it
  exit 0
fi

if [ "${1:-}" = "--trace" ]; then
  shift
  [ $# -ge 1 ] || die "--trace needs driver arguments (e.g. --simp=1 file.cnf)"
  if is_stale; then build_it; fi
  run_trace "$@" || exit 1
  exit 0
fi

if [ "${1:-}" = "--proof" ]; then
  shift
  [ $# -ge 2 ] || die "--proof needs bin|ascii and driver arguments"
  if is_stale; then build_it; fi
  run_proof "$@" || exit 1
  exit 0
fi

[ $# -eq 0 ] || die "unknown argument '$1' (use --build-only, --trace ... or --proof ...)"
[ -d "$cnfdir" ] || die "missing CNF directory $cnfdir"
build_it

sha () { shasum -a 256 | cut -c1-16; }

for simp in 0 1; do
  echo "[run] --simp=$simp"
  for cnf in "$cnfdir"/*.cnf; do
    name="$(basename "$cnf" .cnf)"
    if [ "$name" = php_10_9 ] && [ "${BIG:-0}" != 1 ]; then
      echo "  skip $name (set BIG=1)"
      continue
    fi
    t1="$(run_trace --simp=$simp "$cnf" | sha)"; t2="$(run_trace --simp=$simp "$cnf" | sha)"
    [ "$t1" = "$t2" ] || die "trace NOT deterministic: $name --simp=$simp"
    p1="$(run_proof bin --simp=$simp "$cnf" | sha)"; p2="$(run_proof bin --simp=$simp "$cnf" | sha)"
    [ "$p1" = "$p2" ] || die "binary proof NOT deterministic: $name --simp=$simp"
    a1="$(run_proof ascii --simp=$simp "$cnf" | sha)"; a2="$(run_proof ascii --simp=$simp "$cnf" | sha)"
    [ "$a1" = "$a2" ] || die "ASCII proof NOT deterministic: $name --simp=$simp"
    lines="$(run_trace --simp=$simp "$cnf" | wc -l | tr -d ' ')"
    pbytes="$(run_proof bin --simp=$simp "$cnf" | wc -c | tr -d ' ')"
    alines="$(run_proof ascii --simp=$simp "$cnf" | wc -l | tr -d ' ')"
    printf '  %-22s trace=%s lines sha=%s  bin=%s bytes sha=%s  ascii=%s lines sha=%s\n' \
      "$name" "$lines" "$t1" "$pbytes" "$p1" "$alines" "$a1"
  done
done
echo "[done] deterministic (each trace / proof run twice, same sha256)"
