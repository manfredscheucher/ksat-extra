#!/usr/bin/env bash
# Coverage report for the cadical-full inprocessing suite (shadow/cnf-full).
#
# For every cnf-full/*.cnf the instrumented upstream reference
# (cadical-full/build/cadical_full_trace) runs with --config=default plus the
# options from cnf-full/OPTIONS ("<file> <options...>", one line per run; a file
# may appear again with other options, it is then reported as <file>[<options>]).
# The trace is streamed (never stored) and counted:
#   S    number of 'START <phase>' lines
#   AD   ADD/DEL lines whose innermost open phase is <phase>
#   AD*  ADD/DEL lines while <phase> is open anywhere on the phase stack
#        (includes nested phases, e.g. the collect inside compact or walk)
#   EV   other lines (not START/END/ADD/DEL) whose innermost phase is <phase>
# plus solver run time (trace to /dev/null), trace size (bytes without the
# 's ...' / 'c ...' lines, as the golden traces store them), verdict and the
# event counters CONFLICT/REDUCE/FLUSH/RESTART/MODE/REPHASE/OTFS.
#
# Note: binary clauses are traced as DEL only at their actual deletion
# (upstream delays it, see clause.cpp), so binary clauses removed by transred
# or deduplicate show up later inside 'collect', not in their own bracket.
#
# Usage: bash ksat-extra/shadow/tools/cnf_full_coverage.sh
#   Builds nothing; run cadical-full/build_and_trace.sh --build-only first.
# Exit status 1 if a phase is not covered.
set -u
export LC_ALL=C

here="$(cd "$(dirname "$0")" && pwd)"
shadow="$(cd "$here/.." && pwd)"
bin="$shadow/cadical-full/build/cadical_full_trace"
dir="$shadow/cnf-full"
manifest="$dir/OPTIONS"

die () { echo "cnf_full_coverage: ERROR: $*" >&2; exit 2; }

[ -x "$bin" ] || die "$bin not found; run: bash ksat-extra/shadow/cadical-full/build_and_trace.sh --build-only"
[ -d "$dir" ] || die "$dir not found; run: python3 ksat-extra/shadow/tools/gen_cnf_full.py"
[ -f "$manifest" ] || die "$manifest not found; run: python3 ksat-extra/shadow/tools/gen_cnf_full.py"

phases="preprocess probe vivify subsume elim block cover condition ternary decompose transred instantiate deduplicate lucky walk rephase compact collect"
events="CONFLICT REDUCE FLUSH RESTART MODE REPHASE OTFS"
# Phases that emit no proof events of their own by design (lucky and walk only
# assign, rephase only resets phases, compact only renumbers variables,
# preprocess only calls probe/elim/condition, which nest inside it): they
# count as covered when they have events (EV) or nested ADD/DEL (AD*).
noproof="lucky walk rephase compact preprocess"
# Phases no CNF file can reach with the shadow driver, with the reason (none now:
# preprocess is reached through the driver option --limit:preprocessing=<n>).

# Manifest and directory must agree exactly.
for f in "$dir"/*.cnf; do
  [ -e "$f" ] || die "no .cnf files in $dir"
  b="$(basename "$f")"
  grep -q "^$b\( \|\$\)" "$manifest" || die "$b is missing from $manifest"
done
while read -r name rest; do
  case "$name" in ''|'#'*) continue ;; esac
  [ -f "$dir/$name" ] || die "$manifest lists $name, but $dir/$name does not exist"
done < "$manifest"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/cnf_full_cov.XXXXXX")" || die "mktemp failed"
trap 'rm -rf "$tmp"' EXIT

results="$tmp/results"
: > "$results"
total_bytes=0
total_time=0

while read -r name opts; do
  case "$name" in ''|'#'*) continue ;; esac
  cnf="$dir/$name"
  key="$name"
  [ -z "$opts" ] || key="$name[${opts// /,}]"
  # shellcheck disable=SC2086
  set -- $opts

  # 1) timing run, trace discarded
  start=$(python3 -c 'import time; print("%.3f" % time.time())')
  rc=0
  LSTRACE=1 "$bin" --config=default "$@" "$cnf" > /dev/null || rc=$?
  end=$(python3 -c 'import time; print("%.3f" % time.time())')
  case "$rc" in 10|20) ;; *) die "$bin --config=default $opts $cnf exited with $rc" ;; esac
  secs=$(echo "$end - $start" | bc)

  # 2) counting run, trace streamed into awk
  LSTRACE=1 "$bin" --config=default "$@" "$cnf" | awk -v name="$key" -v secs="$secs" -v rc="$rc" -v opts="$opts" '
    /^[sc] / { next }
    { bytes += length($0) + 1 }
    /^START / { sp++; stk[sp] = $2; S[$2]++; next }
    /^END /   { if (sp < 1 || stk[sp] != $2) { print "ERROR unbalanced " $0 > "/dev/stderr"; exit 3 }
                sp--; next }
    /^(ADD|DEL) / {
      if (sp > 0) { AD[stk[sp]]++
        delete seen
        for (i = 1; i <= sp; i++) if (!(stk[i] in seen)) { seen[stk[i]] = 1; ADI[stk[i]]++ } }
      next }
    { if (sp > 0) EV[stk[sp]]++; E[$1]++ }
    END {
      if (sp != 0) { print "ERROR unclosed phase " stk[sp] > "/dev/stderr"; exit 3 }
      printf "FILE %s %s %d %d %s\n", name, secs, bytes, rc, (opts == "" ? "-" : opts)
      for (p in S) printf "PH %s %s %d %d %d %d\n", name, p, S[p], AD[p] + 0, ADI[p] + 0, EV[p] + 0
      for (e in E) printf "EVT %s %s %d\n", name, e, E[e]
    }' >> "$results"
  st=("${PIPESTATUS[@]}")
  case "${st[0]}" in 10|20) ;; *) die "$bin --config=default $opts $cnf exited with ${st[0]} (counting run)" ;; esac
  [ "${st[1]}" = 0 ] || die "trace check failed for $name (awk status ${st[1]})"
done < "$manifest"

# ------------------------------------------------------------------ report
awk -v phases="$phases" -v events="$events" -v noproof="$noproof" '
  BEGIN { np = split(phases, P, " "); ne = split(events, EVN, " ")
          nn = split(noproof, NP, " "); for (k = 1; k <= nn; k++) NOPROOF[NP[k]] = 1 }
  $1 == "FILE" { nf++; F[nf] = $2; T[$2] = $3; B[$2] = $4; R[$2] = ($5 == 10 ? "SAT" : "UNSAT"); O[$2] = $6
                 tb += $4; tt += $3; next }
  $1 == "PH"   { S[$2, $3] = $4; A[$2, $3] = $5; AI[$2, $3] = $6; V[$2, $3] = $7; next }
  $1 == "EVT"  { E[$2, $3] = $4; next }
  END {
    w = 27
    print "== files (time = solver run with trace to /dev/null; size = golden trace bytes)"
    printf "%-*s %6s %8s %-6s %s\n", w, "file", "secs", "MB", "result", "options"
    for (i = 1; i <= nf; i++) { f = F[i]
      printf "%-*s %6.2f %8.2f %-6s %s\n", w, f, T[f], B[f] / 1e6, R[f], (O[f] == "-" ? "" : O[f]) }
    printf "%-*s %6.2f %8.2f\n\n", w, "TOTAL", tt, tb / 1e6

    print "== events per file"
    printf "%-*s", w, "file"; for (j = 1; j <= ne; j++) printf " %8s", EVN[j]; printf "\n"
    for (i = 1; i <= nf; i++) { f = F[i]; printf "%-*s", w, f
      for (j = 1; j <= ne; j++) printf " %8d", E[f, EVN[j]] + 0; printf "\n" }
    print ""

    print "== matrix: cell = S/AD (S = START count, AD = ADD/DEL with the phase innermost; . = no START)"
    for (half = 0; half < 2; half++) {
      lo = half * 9 + 1; hi = (half + 1) * 9; if (hi > np) hi = np
      printf "%-*s", w, "file"; for (j = lo; j <= hi; j++) printf " %11s", P[j]; printf "\n"
      for (i = 1; i <= nf; i++) { f = F[i]; printf "%-*s", w, f
        for (j = lo; j <= hi; j++) { p = P[j]
          if ((f, p) in S) printf " %11s", S[f, p] "/" A[f, p]; else printf " %11s", "." }
        printf "\n" }
      print "" }

    print "== per phase: files with START, best AD, best AD* (incl. nested), best EV"
    bad = 0
    for (j = 1; j <= np; j++) { p = P[j]; ns = 0; ba = 0; bai = 0; bev = 0; bf = ""; bfi = ""; bfe = ""
      for (i = 1; i <= nf; i++) { f = F[i]
        if (!((f, p) in S)) continue
        ns++
        if (A[f, p] > ba) { ba = A[f, p]; bf = f }
        if (AI[f, p] > bai) { bai = AI[f, p]; bfi = f }
        if (V[f, p] > bev) { bev = V[f, p]; bfe = f } }
      if (ba > 0) st = "COVERED (AD " ba " in " bf ")"
      else if (ns == 0 && (p in GAP)) st = "NOT COVERABLE (known): " GAP[p]
      else if (ns == 0) { st = "NOT COVERED: no START in any file"; bad = 1 }
      else if ((p in NOPROOF) && (bai > 0 || bev > 0))
        st = "COVERED, no own proof events by design (AD* " bai " in " bfi ", EV " bev " in " bfe ")"
      else if (bai > 0) { st = "NO OWN AD; AD* " bai " in " bfi; bad = 1 }
      else if (bev > 0) { st = "NO AD; events only, EV " bev " in " bfe; bad = 1 }
      else { st = "NO EFFECT: START only"; bad = 1 }
      printf "%-12s starts-in=%-3d %s\n", p, ns, st }
    exit bad
  }' "$results"
status=$?
exit $status
