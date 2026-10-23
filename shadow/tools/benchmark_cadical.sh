#!/usr/bin/env bash
# Runtime benchmark: Kotlin CaDiCaL port vs upstream CaDiCaL 2.1.3 (the cadical-full
# reference build), on the same shadow CNFs, both with upstream default options.
#
# What it does (durable, kept in repo):
#   1. generate the CNF suite                    (gen_cnf.py)
#   2. build the upstream reference              (cadical-full/build_and_trace.sh --build-only;
#                                                  timed without LSTRACE, so it prints no trace)
#   3. time the C binary on each CNF             (median of N runs, whole process)
#   4. run the Kotlin CaDiCaL benchmark          (:cadical:runBenchmark, solve-only)
#   5. print a side-by-side table
#
# Note on what's timed: C number = wall time of the whole process (parse+solve+exit);
# Kotlin numbers = solve() only, median over warmed-up runs. For these instances
# parse/IO is negligible vs solve, so they are order-of-magnitude comparable.
#
# Run:  bash shadow/tools/benchmark_cadical.sh
# Env:  RUNS=<n> (default 5); CXX=<compiler> (passed on to build_and_trace.sh)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
shadow="$(cd "$here/.." && pwd)"
root="$(cd "$shadow/.." && pwd)"
cnfdir="$shadow/cnf"
cbin="$shadow/cadical-full/build/cadical_full_trace"
RUNS="${RUNS:-5}"

echo "[1/5] generating CNF suite"
python3 "$here/gen_cnf.py" >/dev/null

echo "[2/5] building the upstream CaDiCaL reference (cadical-full)"
bash "$shadow/cadical-full/build_and_trace.sh" --build-only

time_c () {
  local cnf="$1"; local -a ms=()
  local i start end
  for ((i = 0; i < RUNS; i++)); do
    start=${EPOCHREALTIME//[.,]/}
    "$cbin" "$cnf" >/dev/null 2>&1 || true
    end=${EPOCHREALTIME//[.,]/}
    ms+=( $(awk -v s="$start" -v e="$end" 'BEGIN{printf "%.3f", (e-s)/1000.0}') )
  done
  printf '%s\n' "${ms[@]}" | sort -n | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}'
}

echo "[3/5] timing upstream CaDiCaL on each CNF (median of $RUNS runs)"
declare -a names=() ctimes=()
for cnf in "$cnfdir"/*.cnf; do
  name="$(basename "$cnf" .cnf)"
  t=$(time_c "$cnf")
  names+=("$name"); ctimes+=("$t")
  printf '  %-26s C=%8.3f ms\n' "$name" "$t"
done

gradle_cmd="$root/gradlew"
[ -x "$gradle_cmd" ] || gradle_cmd="gradle"

echo "[4/5] running Kotlin CaDiCaL benchmark via Gradle"
cad_out="$shadow/cadical-full/build/kotlin_cadical_bench.txt"
( cd "$root" && "$gradle_cmd" :cadical:runBenchmark -q ) | tee "$cad_out"

echo
echo "[5/5] side-by-side (all median ms; C = whole process, Kotlin = solve-only)"
printf '%-26s %12s %14s\n' "cnf" "C_CaDiCaL" "Kt_CaDiCaL"
for i in "${!names[@]}"; do
  n="${names[$i]}"
  kt=$(awk -v k="$n" '$1==k{print $3}' "$cad_out"); [ -z "$kt" ] && kt="-"
  printf '%-26s %12s %14s\n' "$n" "${ctimes[$i]}" "$kt"
done
echo
echo "Note: numbers above are MEASURED on this machine when you run this script."
