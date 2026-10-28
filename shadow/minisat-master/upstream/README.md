# upstream/: verbatim MiniSat master (github.com/meelgroup/minisat, branch master, commit 664490d)

Every file in this directory except this `README.md` is an unmodified export of the local clone
`/Users/manfred/github/meelgroup-minisat`, branch `upstream/master` at

- commit `664490d5c49876a73bfd1a59fe5d5d5d530dd8bb` (2020-07-11, "fixing static build"),

made with `git -C ~/github/meelgroup-minisat archive upstream/master minisat LICENSE | tar -x`
(25 files: `minisat/{core,simp,mtl,utils}` and `LICENSE`). Never edit these files; trace
output is added by `../trace.patch` on a copy in `../build/src-*`.

## Relation to the csb reference (../../minisat-full/upstream, meelgroup 9a0382d)

Both branch off niklasso `37dc6c6`. On master:

- `4565536` (compile fix: `mkLit` default argument) and `a352df4` ("Clang-format"). Compared
  token by token (comments, whitespace, `#include` order and adjacent string-literal splits
  ignored; `scripts/probe/minisat_token_diff.py` in the main repo), a352df4 equals 9a0382d in
  every file except the three compile fixes 9a0382d has and master lacks or has differently:
  `SolverTypes.h` (`friend mkLit` declaration commented out instead of moved), `System.cc`
  (`memUsedPeak()` vs `memUsedPeak(bool)`, does not compile on macOS), `System.h`
  (`__linux__` instead of `__GLIBC__`). So up to a352df4 the solver is the csb solver.
- `1d1940a` Adding DRUP, `9e03655` debugging DRAT (`SimpSolver::parsing`), `333d3ef` Fixing
  DRAT (eliminateVar / substitute: delete the old clauses after adding the resolvents),
  `6b0d7ff` DRUP debug (trimmed clauses in removeSatisfied), `b1f6f7f` show_info reduceDB
  statistics, `a19dbf7` option `rdb-at` (`reduceDB_needed`), `664490d` CMake only.

## Checksums (sha256)

    c75f5063560674728fcfa7b9b291d26a3a8b9436a0d9940eadc81aab7779d62b  ./LICENSE
    5e567824c186cab27218d29bf110ce532fdba0cb45fa93626028c8742fea39f4  ./minisat/core/Dimacs.h
    9d54d96817b251f595448f950a82551732e0fe317117ab2fc721bdc6dab5005c  ./minisat/core/Main.cc
    da9670681848c1e0e8a719e7ea97be4b77961abf60bc702273c71efe8b4aa069  ./minisat/core/Solver.cc
    1e4b697aec1ae87bd18886c09c6198a73e00df608ec67141f572199673ec20ba  ./minisat/core/Solver.h
    00d94ac7fa3cea35c4ddac61b82bafc50b420270d1f86c6ee888a0bd79ce2fbc  ./minisat/core/SolverTypes.h
    f96653f9bd061eed768362a0b366927ff06ac64333373334d90ca6b6cb650877  ./minisat/mtl/Alg.h
    5139f51915150eea0c6993319d8bf47b681798ec2a4e060b7cb9287efa31c6bd  ./minisat/mtl/Alloc.h
    16175d80a8e630677dd9e60a6e99410e08435c0250e32e14aca75dc9f75fbd36  ./minisat/mtl/Heap.h
    093309ea24e46cbb93857668cfa6c26bca46851ad5b7e371dc30fd19b481d082  ./minisat/mtl/IntMap.h
    f09c7aa0daa79d633c2c485e29d395a77a5cd699d3eac1cd80d5ad4f9c79b157  ./minisat/mtl/IntTypes.h
    979e0bd70bddc37917736a749abae694f36dc94ad27bacc391224e4be89cdb2f  ./minisat/mtl/Map.h
    566ebf4e073eeee8f024d161fcffa8e1130849aa909c1a7072def7f2b1db386b  ./minisat/mtl/Queue.h
    93a502520882007baa73a34537f97b59af59bf1c0e3f12d28ea6a08916a08bb5  ./minisat/mtl/Rnd.h
    59cd7e6e4eff5a76282e959db0c63f011be955a4a6574ddfbb859da48d4a52fc  ./minisat/mtl/Sort.h
    d25dbebee5ed111515b8854d58a60d9be4fdd7eb308d1f86d2d4a420e16a45ce  ./minisat/mtl/Vec.h
    c06b4875bcdac90abbcb3fdf05b53cf97b1bc3870102d2fd0c0d1ef3b0695abc  ./minisat/mtl/XAlloc.h
    43a1b3e17f7e5d4080ed358b255de91e586cc47d70472e51c3ca1e80c4729e51  ./minisat/simp/Main.cc
    43db6a97c619c9e883fe08b581862759c45c3890814eb4884449ccfe18b25986  ./minisat/simp/SimpSolver.cc
    a08a13ad4563be77d7527d4ce3b4d06913f6305e267bb705a632eb4993a6cf72  ./minisat/simp/SimpSolver.h
    fd3246870aa865a42cb10696b52d7e354f9b3b90f5ba92833fe7af6f6b4f0854  ./minisat/utils/Options.cc
    46ecfa1527152da5c9f413653ad1ecf30abe9ae2460b5b8ca883e3b4e1d21c91  ./minisat/utils/Options.h
    fbcf651fd75d2305191153f0d05d62c1df7e0b0a5c2a8ef3cb9ed4141fb13e75  ./minisat/utils/ParseUtils.h
    fa604e8160f008de3fb0684e894f375076ed1fdb097278f35f880f4a814199b5  ./minisat/utils/System.cc
    19e1bf124e6022e47aa9e8f5f8876ad672d1448316516b462236789bd40a0dd9  ./minisat/utils/System.h
