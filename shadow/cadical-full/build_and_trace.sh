#!/usr/bin/env bash
# Build the instrumented FULL upstream CaDiCaL 2.1.3 reference and write golden traces.
#
#   build_and_trace.sh                 build, then trace every shadow/cnf/*.cnf for the
#                                      configs 'plain' and 'default' (php_10_9 skipped)
#   BIG=1 build_and_trace.sh           ... including php_10_9 (huge)
#   CONFIGS="plain" build_and_trace.sh only the given configs (plain|default|sat|unsat)
#   build_and_trace.sh --build-only    only build build/cadical_full_trace
#   CHECK=1 build_and_trace.sh         also run every trace a second time (determinism)
#                                      and once without the proof tracer (LSPROOF=0),
#                                      and fail if the search events differ
#
# Steps: copy upstream/ (verbatim, never edited) to build/src, apply trace.patch there,
# generate build/src/build.hpp (what upstream's scripts/make-build-header.sh produces),
# compile all solver sources + driver.cpp, then trace into
# shadow/golden-cadical-full-<config>/<name>.trace (+ manifest.txt).
# bash 3.2 compatible (macOS). Fails loudly on every error.
set -euo pipefail

die () { echo "build_and_trace.sh: error: $*" 1>&2; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"
shadow="$(cd "$here/.." && pwd)"
upstream="$here/upstream"
patchfile="$here/trace.patch"
build="$here/build"
src="$build/src"
bin="$build/cadical_full_trace"
cnfdir="$shadow/cnf"

CXX="${CXX:-clang++}"
CXXFLAGS="-O2 -std=c++11 -DNDEBUG -DNCLOSEFROM -DNCONTRIB"

command -v "$CXX" >/dev/null 2>&1 || die "compiler '$CXX' not found"
command -v patch >/dev/null 2>&1 || die "'patch' not found"
[ -f "$upstream/VERSION" ] || die "missing $upstream/VERSION"
[ -f "$patchfile" ] || die "missing $patchfile"
[ -d "$cnfdir" ] || die "missing CNF directory $cnfdir"

# ---------------------------------------------------------------- build
echo "[build] copying upstream/ -> build/src and applying trace.patch"
rm -rf "$src"
mkdir -p "$src"
# VERSION is NOT copied: on case-insensitive macOS file systems it would shadow
# the C++ standard header <version> (the include path contains build/src).
cp "$upstream"/*.cpp "$upstream"/*.hpp "$src"/
( cd "$src" && patch -p1 --quiet --forward < "$patchfile" ) \
  || die "trace.patch does not apply cleanly to upstream/"

version="$(cat "$upstream/VERSION")"
[ -n "$version" ] || die "empty VERSION"
{
  echo "#define VERSION \"$version\""
  echo "#define IDENTIFIER \"f13d74439a5b5c963ac5b02d05ce93a8098018b8\""
  echo "#define SHORTID \"f13d744\""
  echo "#define COMPILER \"$("$CXX" --version 2>/dev/null | head -1)\""
  echo "#define FLAGS \"$CXXFLAGS\""
  echo "#define DATE \"shadow-reference build\""
} > "$src/build.hpp"

# All solver sources except the apps (cadical.cpp, mobical.cpp) and the C/IPASIR
# interfaces (ccadical.cpp, ipasir.cpp). contrib/ is not copied (-DNCONTRIB).
sources=""
for f in "$src"/*.cpp; do
  case "$(basename "$f")" in
    cadical.cpp|mobical.cpp|ccadical.cpp|ipasir.cpp) ;;
    *) sources="$sources $f" ;;
  esac
done
[ -n "$sources" ] || die "no sources found in $src"

echo "[build] $CXX $CXXFLAGS (all solver sources + driver.cpp)"
objdir="$build/obj"
rm -rf "$objdir"
mkdir -p "$objdir"
pids=""
for f in $sources "$here/driver.cpp"; do
  o="$objdir/$(basename "$f" .cpp).o"
  "$CXX" $CXXFLAGS -I"$src" -c "$f" -o "$o" &
  pids="$pids $!"
done
failed=0
for p in $pids; do wait "$p" || failed=1; done
[ "$failed" = 0 ] || die "compilation failed (see compiler output above)"
"$CXX" $CXXFLAGS -o "$bin" "$objdir"/*.o || die "linking failed"
echo "[build] built $bin"

if [ "${1:-}" = "--build-only" ]; then exit 0; fi
[ $# -eq 0 ] || die "unknown argument '$1'"

# ---------------------------------------------------------------- trace
configs="${CONFIGS:-plain default}"
check="${CHECK:-0}"

# Strip the verdict line 's ...' and upstream's 'c ...' messages (the DIMACS parser
# prints them; one contains the parse time, so they are not deterministic). Neither
# is part of the event trace. Exit codes 10/20 are the verdict, anything else fails.
run_trace () { # <out> <proof:1|0> <config> <cnf>
  local out="$1" proofflag="$2" cfg="$3" cnf="$4" rc=0
  LSTRACE=1 LSPROOF="$proofflag" "$bin" --config="$cfg" "$cnf" > "$out.raw" || rc=$?
  if [ "$rc" != 10 ] && [ "$rc" != 20 ]; then
    die "$bin --config=$cfg $cnf exited with $rc"
  fi
  grep -vE '^(s|c) ' "$out.raw" > "$out" || die "empty trace for $cnf"
  rm -f "$out.raw"
}

# Search events without the tracer lines and with clause ids blanked: connecting the
# proof tracer makes upstream allocate extra clause ids (e.g. Proof::otfs_strengthen_clause
# gives the strengthened clause a fresh id), so ids differ with LSPROOF=0, but nothing else
# may differ.
search_events () {
  { grep -vE '^(ADD|DEL|WEAKEN|STRENGTHEN) ' "$1" || true; } | sed -E \
    -e 's/reason=C [0-9]+ :/reason=C # :/' \
    -e 's/^(CONFLICT level=[0-9]+) [0-9]+ :/\1 # :/' \
    -e 's/^LEARN id=[0-9]+/LEARN id=#/' \
    -e 's/^OTFS [0-9]+ :/OTFS # :/'
}

tmp="$build/check"
mkdir -p "$tmp"
for cfg in $configs; do
  gold="$shadow/golden-cadical-full-$cfg"
  mkdir -p "$gold"
  manifest="$gold/manifest.txt"
  : > "$manifest"
  echo "[trace] config=$cfg -> $gold"
  for cnf in "$cnfdir"/*.cnf; do
    name="$(basename "$cnf" .cnf)"
    if [ "$name" = php_10_9 ] && [ "${BIG:-0}" != 1 ]; then
      echo "  skip $name (set BIG=1)"
      continue
    fi
    out="$gold/$name.trace"
    t0=$(date +%s)
    run_trace "$out" 1 "$cfg" "$cnf"
    t1=$(date +%s)
    lines=$(wc -l < "$out" | tr -d ' ')
    result=$(grep '^RESULT ' "$out" | head -1 | cut -d' ' -f2)
    status=""
    if [ "$check" = 1 ]; then
      run_trace "$tmp/again.trace" 1 "$cfg" "$cnf"
      cmp -s "$out" "$tmp/again.trace" || die "NOT deterministic: $name ($cfg)"
      run_trace "$tmp/noproof.trace" 0 "$cfg" "$cnf"
      search_events "$out" > "$tmp/a.ev"
      search_events "$tmp/noproof.trace" > "$tmp/b.ev"
      cmp -s "$tmp/a.ev" "$tmp/b.ev" \
        || die "proof tracer changes search events (beyond clause ids): $name ($cfg)"
      status=" deterministic proof-neutral(ids-aside)"
    fi
    printf '%-22s %-6s lines=%-9s secs=%s%s\n' "$name" "$result" "$lines" \
      "$((t1 - t0))" "$status" | tee -a "$manifest"
  done
done
echo "[done]"
