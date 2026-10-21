# Verification scripts for the SAT techniques tutorial

Every worked example in `../*.typ` was checked mechanically. These scripts (python3, stdlib only)
re-derive the examples by brute force or with a tiny CDCL/unit-propagation simulator and exit
non-zero on any mismatch.

| Script | Checks |
|---|---|
| `probe_cdcl_chapter.py`, `probe_review_fixes_ch1_3.py` | ch1: trail, conflict, 1-UIP, minimization, shrinking, backjump, OTFS, watches; ch2/ch3 review fixes |
| `probe_heuristics_examples.py` | ch2: EVSIDS, VMTF, Luby/EMA restarts, rephase intervals, lucky, walk, lookahead, warmup |
| `probe_ch03_clause_db.py` | ch3: LBD, tiers, reduce rounds, MiniSat reduceDB, promotion, arena and variable compaction |
| `probe_elimination_chapter.py` | ch4: resolution, subsumption, BVE/fastel bounds, gates, BCE/CCE/conditioning, instantiation, factorization, reconstruction, frozen vars |
| `verify_ch05_examples.py`, `verify_ch05_sweep_classes.py` | ch5: probing, HBR, vivify, SCC substitution, transitive reduction, ternary, backbone, congruence, sweeping |
| `probe_ch06_incremental.py`, `verify_ch06_frozen_ref.py` | ch6: assumptions, failed cores, enumeration, frozen vars, IPASIR-UP walkthrough, DRAT/LRAT |
| `review_ch123/`, `review_ch4_6_bruteforce.py` | independent re-derivations by the fresh reviewers |
| `ProbeCh06.kt` | runs the ch6 Kotlin snippets against the real ports (compile with kotlinc against the built `*/build/classes/kotlin/jvm/main` + kotlin-stdlib) |

Run all Python checks:

```bash
cd ksat-extra/doc/sat-techniques/verify
for f in *.py review_ch123/*.py; do python3 -I "$f" > /dev/null && echo "ok   $f" || echo "FAIL $f"; done
```
