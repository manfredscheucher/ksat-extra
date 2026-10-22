#!/usr/bin/env bash
# Build the instrumented upstream MiniSat (github.com/meelgroup/minisat 9a0382d) reference
# and print traces. Writes nothing outside build/ (no golden files; compare live).
#
#   build_and_trace.sh --build-only            build build/minisat_full_trace
#   build_and_trace.sh --trace [args...]       print ONE trace to stdout: runs the binary
#                                              with LSTRACE=1 and the given driver args
#                                              (e.g. --simp=1 x.cnf [x.assume]); drops the
#                                              's ...' verdict line. Rebuilds if stale.
#   build_and_trace.sh                         build, then for every ../cnf/*.cnf and
#                                              --simp=0 / --simp=1: run twice, require the
#                                              same checksum (determinism), print a summary
#                                              (verdict, line count, events that fired)
#                                              php_10_9 only with BIG=1.
#
# Steps: copy upstream/minisat (verbatim, never edited) to build/src/minisat, apply
# trace.patch there, compile core/Solver.cc simp/SimpSolver.cc utils/Options.cc
# utils/System.cc + driver.cpp (not the Main.cc apps), link. Compiler: clang++ (like
# ../cadical-full). bash 3.2 compatible. Fails loudly.
set -euo pipefail

die () { echo "build_and_trace.sh: error: $*" 1>&2; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"
shadow="$(cd "$here/.." && pwd)"
upstream="$here/upstream"
patchfile="$here/trace.patch"
shim="$here/zlib-shim"
build="$here/build"
src="$build/src"
bin="$build/minisat_full_trace"
cnfdir="$shadow/cnf"

CXX="${CXX:-clang++}"
# upstream Makefile release flags (MINISAT_REL = -O3 -D NDEBUG, MINISAT_CXXFLAGS =
# -D __STDC_LIMIT_MACROS -D __STDC_FORMAT_MACROS), with -O2 instead of -O3; -std=c++98
# (the code's dialect), -ffp-contract=off (no fused multiply-add, so double arithmetic
# rounds like the JVM).
CXXFLAGS="-O2 -std=c++98 -ffp-contract=off -DNDEBUG -D__STDC_LIMIT_MACROS -D__STDC_FORMAT_MACROS"

build_it () {
  command -v "$CXX" >/dev/null 2>&1 || die "compiler '$CXX' not found (set CXX=...; see README.md)"
  command -v patch >/dev/null 2>&1 || die "'patch' not found"
  [ -f "$upstream/minisat/core/Solver.cc" ] || die "missing $upstream/minisat/core/Solver.cc"
  [ -f "$patchfile" ] || die "missing $patchfile"
  [ -f "$shim/zlib.h" ] || die "missing $shim/zlib.h"

  echo "[build] copying upstream/minisat -> build/src and applying trace.patch" 1>&2
  rm -rf "$src"
  mkdir -p "$src"
  cp -R "$upstream/minisat" "$src/minisat"
  ( cd "$src" && patch -p1 --quiet --forward < "$patchfile" ) \
    || die "trace.patch does not apply cleanly to upstream/"

  local objdir="$build/obj" pids="" failed=0 f o p
  rm -rf "$objdir"
  mkdir -p "$objdir"
  echo "[build] $CXX $CXXFLAGS" 1>&2
  for f in "$src/minisat/core/Solver.cc" "$src/minisat/simp/SimpSolver.cc" \
           "$src/minisat/utils/Options.cc" "$src/minisat/utils/System.cc" "$here/driver.cpp"; do
    o="$objdir/$(basename "$f" | sed 's/\.[a-z]*$//').o"
    # -w hides upstream's warnings (all from upstream; drop -w to see them).
    "$CXX" $CXXFLAGS -w -I"$shim" -I"$src" -c "$f" -o "$o" &
    pids="$pids $!"
  done
  for p in $pids; do wait "$p" || failed=1; done
  [ "$failed" = 0 ] || die "compilation failed (see compiler output above)"
  "$CXX" $CXXFLAGS -o "$bin" "$objdir"/*.o || die "linking failed"
  echo "[build] built $bin" 1>&2
}

is_stale () {
  [ -x "$bin" ] || return 0
  local f
  for f in "$patchfile" "$here/driver.cpp" "$shim/zlib.h" "$0"; do
    [ "$f" -nt "$bin" ] && return 0
  done
  return 1
}

# run_trace <args...>: the trace on stdout without the 's ...' verdict line; the binary's
# exit code 10/20/0 is a verdict, anything else fails the pipeline (and so the script).
run_trace () {
  local rc
  set +e
  LSTRACE=1 "$bin" "$@" | grep -v '^s '
  rc=${PIPESTATUS[0]}
  set -e
  case "$rc" in
    0|10|20) ;;
    *) echo "build_and_trace.sh: error: $bin $* exited with $rc" 1>&2; return 1 ;;
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

[ $# -eq 0 ] || die "unknown argument '$1' (use --build-only or --trace ...)"
[ -d "$cnfdir" ] || die "missing CNF directory $cnfdir"
build_it

# Summary: no files written; every run is piped into shasum / awk.
for simp in 0 1; do
  echo "[trace] --simp=$simp"
  for cnf in "$cnfdir"/*.cnf; do
    name="$(basename "$cnf" .cnf)"
    if [ "$name" = php_10_9 ] && [ "${BIG:-0}" != 1 ]; then
      echo "  skip $name (set BIG=1)"
      continue
    fi
    t0=$(date +%s)
    a="$(run_trace --simp=$simp "$cnf" | shasum -a 256 | cut -c1-16)"
    b="$(run_trace --simp=$simp "$cnf" | shasum -a 256 | cut -c1-16)"
    [ "$a" = "$b" ] || die "NOT deterministic: $name --simp=$simp ($a vs $b)"
    stats="$(run_trace --simp=$simp "$cnf" | awk '
      { n++; c[$1]++ }
      /^RESULT / { r = $2 }
      /^START / { p[$2]++ }
      END {
        printf "lines=%d result=%s", n, r
        split("DECIDE CONFLICT RESTART REDUCE SIMPLIFY ADD DEL TRIM GC SUBSUME STRENGTHEN ELIM", k, " ")
        for (i = 1; i in k; i++) if (c[k[i]] > 0) printf " %s=%d", k[i], c[k[i]]
        for (q in p) printf " START:%s=%d", q, p[q]
        printf "\n"
      }')"
    t1=$(date +%s)
    printf '  %-22s %s sha=%s secs=%s\n' "$name" "$stats" "$a" "$((t1 - t0))"
  done
done
echo "[done] deterministic (each trace run twice, same sha256)"
