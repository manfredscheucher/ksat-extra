#!/usr/bin/env bash
# Reproduce the four meelgroup/minisat master bugs on a stock build and check that each
# NN-*/fix.patch makes its repro go away. Local only: reads the existing checkout with
# 'git archive' (no fetch, nothing written to the checkout), builds in a temp dir that is
# deleted at the end.
#
#   reproduce.sh            all four bugs
#   reproduce.sh 1 3        only bugs 1 and 3
#
# Env: MINISAT_REPO (default ~/github/minisat-meelgroup), REF (default origin/master).
# Build: upstream CMake. Extra settings, none of them touch the solver logic:
#   -DCMAKE_POLICY_VERSION_MINIMUM=3.5   CMake >= 4 refuses the old cmake_minimum_required
#   macOS only: macos-build.patch (memUsedPeak definitions match the header),
#               -Dfwrite_unlocked=fwrite (glibc-only function), -DSTATIC_BINARIES=OFF
# bash 3.2 compatible. Fails loudly.
set -euo pipefail

die () { echo "reproduce.sh: error: $*" 1>&2; exit 1; }

here="$(cd "$(dirname "$0")" && pwd)"
repo="${MINISAT_REPO:-$HOME/github/minisat-meelgroup}"
ref="${REF:-origin/master}"
bugs="${*:-1 2 3 4}"

command -v cmake >/dev/null 2>&1 || die "cmake not found"
command -v python3 >/dev/null 2>&1 || die "python3 not found"
git -C "$repo" rev-parse --verify -q "$ref^{commit}" >/dev/null || die "$ref not found in $repo"

work="$(mktemp -d "${TMPDIR:-/tmp}/minisat-repro.XXXXXX")"
trap 'rm -rf "$work"' EXIT
trap 'echo "reproduce.sh: error: command failed at line $LINENO" 1>&2' ERR

cxxflags=""
cmake_extra="-DCMAKE_POLICY_VERSION_MINIMUM=3.5"
darwin=0
if [ "$(uname -s)" = Darwin ]; then
  darwin=1
  cxxflags="-Dfwrite_unlocked=fwrite"
  cmake_extra="$cmake_extra -DSTATIC_BINARIES=OFF"
fi

# build <name> [patch]: export $ref to $work/<name>, apply the patch, build minisat_core and
# minisat (simp) into $work/<name>/b.
build () {
  local name="$1" patch="${2:-}" src="$work/$1"
  mkdir -p "$src"
  git -C "$repo" archive "$ref" | tar -x -C "$src"
  if [ "$darwin" = 1 ]; then
    ( cd "$src" && git apply "$here/macos-build.patch" ) || die "macos-build.patch does not apply"
  fi
  if [ -n "$patch" ]; then
    ( cd "$src" && git apply --check "$patch" && git apply "$patch" ) \
      || die "$(basename "$(dirname "$patch")")/fix.patch does not apply to $ref"
  fi
  ( cd "$src" && mkdir b && cd b \
    && cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="$cxxflags" $cmake_extra >cmake.log 2>&1 \
    && make -j8 minisat_core minisat_simp >make.log 2>&1 ) \
    || { tail -20 "$src/b/make.log" "$src/b/cmake.log" 2>/dev/null; die "build $name failed"; }
  echo "[build] $name ok" 1>&2
}

# has <text> <word>: 1 if text contains word, else 0
has () {
  case "$1" in
    *"$2"*) echo 1 ;;
    *) echo 0 ;;
  esac
}

# rc_of cmd...: exit code of cmd (output dropped)
rc_of () { set +e; "$@" >/dev/null 2>&1; echo $?; set -e; }

dir_of () {
  case "$1" in
    1) echo 01-trim-proof-crash ;; 2) echo 02-rdb-at-show-info ;;
    3) echo 03-binary-proof-not-flushed ;; 4) echo 04-rcheck-elim-unsound ;;
    *) die "unknown bug '$1' (1..4)" ;;
  esac
}

build stock
fail=0
check () { # check <label> <ok 0|1>
  if [ "$2" = 1 ]; then echo "  OK    $1"; else echo "  FAIL  $1"; fail=1; fi
}

for n in $bugs; do
  d="$(dir_of "$n")"
  build "fix$n" "$here/$d/fix.patch"
  s="$work/stock/b" f="$work/fix$n/b"
  echo "[bug $n] $d"
  case "$n" in
    1)
      python3 -c "
print('p cnf 30000 10001')
for i in range(10000): print(-1, *[10000 + (40*i + j) % 20000 for j in range(40)], 0)
print('1 0')" > "$work/trim.cnf"
      a="$(rc_of "$s/minisat_core" -verb=0 "$work/trim.cnf")"
      b="$(rc_of "$f/minisat_core" -verb=0 "$work/trim.cnf")"
      echo "  minisat_core trim.cnf: stock exit $a, fixed exit $b"
      check "stock crashes (139)" "$([ "$a" = 139 ] && echo 1 || echo 0)"
      check "fixed answers SAT (10)" "$([ "$b" = 10 ] && echo 1 || echo 0)"
      ;;
    2)
      conf () { { "$1/minisat" -rdb-at=2000 -show-info="$2" "$here/$d/repro.cnf" || true; } | awk '/^conflicts/ {print $3}'; }
      a0="$(conf "$s" 0)"; a1="$(conf "$s" 1)"; b0="$(conf "$f" 0)"; b1="$(conf "$f" 1)"
      echo "  conflicts with -rdb-at=2000, show-info 0/1: stock $a0/$a1, fixed $b0/$b1"
      check "stock: show-info changes the search" "$([ "$a0" != "$a1" ] && echo 1 || echo 0)"
      check "fixed: same search, equal to stock with show-info=1" \
        "$([ "$b0" = "$b1" ] && [ "$b1" = "$a1" ] && echo 1 || echo 0)"
      ;;
    3)
      "$s/minisat" -verb=0 -drup-file="$work/p_stock.drup" "$here/$d/repro.cnf" >/dev/null || true
      "$f/minisat" -verb=0 -drup-file="$work/p_fix.drup" "$here/$d/repro.cnf" >/dev/null || true
      a="$(wc -c < "$work/p_stock.drup" | tr -d ' ')"; b="$(wc -c < "$work/p_fix.drup" | tr -d ' ')"
      ca="$(python3 "$here/drup_check.py" "$here/$d/repro.cnf" "$work/p_stock.drup" || true)"
      cb="$(python3 "$here/drup_check.py" "$here/$d/repro.cnf" "$work/p_fix.drup" || true)"
      echo "  proof bytes: stock $a ($ca), fixed $b ($cb)"
      check "stock proof is invalid" "$(has "$ca" "proof INVALID")"
      check "fixed proof checks" "$(has "$cb" "proof OK")"
      ;;
    4)
      a="$(rc_of "$s/minisat" -verb=0 -rcheck "$here/$d/repro.cnf")"
      b="$(rc_of "$f/minisat" -verb=0 -rcheck "$here/$d/repro.cnf")"
      echo "  minisat -rcheck repro.cnf (UNSAT): stock exit $a, fixed exit $b"
      check "stock answers SAT (10)" "$([ "$a" = 10 ] && echo 1 || echo 0)"
      check "fixed answers UNSAT (20)" "$([ "$b" = 20 ] && echo 1 || echo 0)"
      ;;
  esac
done

[ "$fail" = 0 ] || die "some checks failed (see FAIL lines)"
echo "[done] all checks passed"
