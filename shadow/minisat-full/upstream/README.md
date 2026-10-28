# upstream/: verbatim MiniSat (github.com/meelgroup/minisat, commit 9a0382d)

Every file in this directory except this `README.md` is an unmodified copy of the local
clone `/Users/manfred/github/meelgroup-minisat` (Manfred's fork of meelgroup/minisat, the
maintained fork of `niklasso/minisat`; remote `upstream` = meelgroup), at

- commit `9a0382dcb9e149dbd4d5c7fdf2b5e16ed70bfc8d` (2026-03-14, "skip macos-x86 [release]"),
  working tree clean (`git diff --quiet HEAD`, no untracked files).

Copied (layout kept): `minisat/core`, `minisat/simp`, `minisat/mtl`, `minisat/utils` and
`LICENSE` (25 files). Not copied: the build files (`Makefile`, `CMakeLists.txt`, `cmake/`,
CI, docker, `doc/`, `README`). Never edit these files; trace output is added by
`../trace.patch` on a copy in `../build/src`.

## Relation to niklasso/minisat 37dc6c6

The fork contains niklasso's last commit `37dc6c6` (`git merge-base --is-ancestor 37dc6c6
HEAD`). `git diff 37dc6c6 9a0382d` over the copied directories touches 5 files, 16 lines,
all compile fixes, no behaviour change of the solver:

- `core/SolverTypes.h`: the default argument of `mkLit(Var, bool sign = false)` moved from
  the friend declaration to the definition (clang/gcc reject the old form).
- `core/Solver.cc` (`printStats` only), `utils/Options.h`: `"%"PRIu64"` -> `"%" PRIu64 "`.
- `utils/System.cc`: `memUsedPeak(bool)` definitions match the declaration in `System.h`.
- `utils/System.cc`, `utils/System.h`: FPU-control guard `__linux__` -> `__GLIBC__`.

So the algorithm is identical to niklasso 37dc6c6 (the "2.2.0 GitHub final").

## Verification (2026-10-22)

`find . -type f | sort | xargs shasum -a 256` here equals the same listing of the clone
(byte-identical). sha256 per file:

```
c75f5063560674728fcfa7b9b291d26a3a8b9436a0d9940eadc81aab7779d62b  ./LICENSE
1dd0eabe5d30d348608a125f8399247e7ceb657cdb42d86c70485c01b380d378  ./README.md.new
90255d76a70a156c9d6013e9dc21dcf9f470cf0180edbd55c59e9cf0e9e8f4db  ./minisat/core/Dimacs.h
b9c7b9aeea8121e8da83677ae570e8e879911fa5d101c9d5e94326ca876b250a  ./minisat/core/Main.cc
8e3661235e80d2905f2f1e7d5eecfec82157bd424e59f4382ad22a7602e12ae8  ./minisat/core/Solver.cc
47f0330cf08eea66852015be00c53c92b1454eee9d549e53f09feaa25c8f03b2  ./minisat/core/Solver.h
dab7ac54ed77052677599e874e1e6e47130bb64fef0322f393eb0f26c8b5b09b  ./minisat/core/SolverTypes.h
c91b497f7e96b4892cc9ed4ab85e67b6c91123f15d57a3bf74c40a1e121985bb  ./minisat/mtl/Alg.h
bced853d985d4e2740f9b8868987400dc2b225a741c4aea5b75a5f8126688e42  ./minisat/mtl/Alloc.h
25fab50c849e42da50b9d4b70e6e33519003e19c4731914c3350144cd6e32fa8  ./minisat/mtl/Heap.h
333cffcfefc88ffc4f42c628b2bd59129d333de16f75c65b92e4b0ee1dec72a9  ./minisat/mtl/IntMap.h
77d5cc50cbbaeccc85db25cf3e4a652158e1decbf79ebf92283371ddfb0152df  ./minisat/mtl/IntTypes.h
98e035eb6fb0d6200a46e5de8662b0c62d2abb8800172af6888eea4cd3f6c2ae  ./minisat/mtl/Map.h
f6eaf0beda57c79e805e5819f3c1f60f2a6bd9c0b765720e95e8204ce6de8c0f  ./minisat/mtl/Queue.h
352fe4e6dc663d4854296727ee9bd71708a984ecb2774236fad3f24c4fe6ec81  ./minisat/mtl/Rnd.h
69677457dec510ca14bdff4f3a7c8a4e8271bab830bfc3bfa2e6ac8653bc4f34  ./minisat/mtl/Sort.h
eb998a7171f76699da43ac9b4492783cf8ec344a07010c3773fc683b3f6746bc  ./minisat/mtl/Vec.h
190209abdab80a3562125525890254048bb732cfeb5017603c52cc2b00ca62cf  ./minisat/mtl/XAlloc.h
84a535303523c7567b0037728d46d8b65a6aad89769bfb53f61f41d024a5e802  ./minisat/simp/Main.cc
d037bcdb295ec043fd2cd86afaa65996f62ada465b65b80343462803be2a9e43  ./minisat/simp/SimpSolver.cc
d893fff1c8c390a4f8b445aa7c01c2e955eabf9378f4eb4b2875df913847d7da  ./minisat/simp/SimpSolver.h
d965e519d1f02e1f97e301c8eb96dc916d5d9bb17576ace48d5e36d08615daa3  ./minisat/utils/Options.cc
fd0cbe0f5a172963e34e9ab1cde72432b90cc7378f05fa9b04cf23895844b9d6  ./minisat/utils/Options.h
29803190f79e47c31a444a90fcf2ec65349a70c1bc4ea2fb3713a4b2ce09f0b1  ./minisat/utils/ParseUtils.h
dafb9910bedf085d349e7d702e2fcb355db119718ddc2057caf4ed6168e57537  ./minisat/utils/System.cc
e7209f4c91b4646e71699c62385cf9a1544ffbd6653240c7ba6d3b5ed1fe713f  ./minisat/utils/System.h
```
