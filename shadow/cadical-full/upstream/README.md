# upstream/ (verbatim CaDiCaL 2.1.3)

Verbatim copy of upstream CaDiCaL 2.1.3: every `src/*.cpp` and `src/*.hpp`, plus
`LICENSE` and `VERSION`, from github.com/arminbiere/cadical at commit
`f13d74439a5b5c963ac5b02d05ce93a8098018b8` (short `f13d744`, "merged with development
before release", VERSION 2.1.3). Copied from the local checkout `~/github/cadical`.

Never edit these files. All trace output lives in `../trace.patch`, which
`../build_and_trace.sh` applies to a copy in `../build/src`.

Not copied (not needed for the reference): `src/README.md`, `src/configure`,
`src/makefile`, `src/ccadical.h`, `src/ipasir.h`, `contrib/`, `test/`, `scripts/`.

To check that this directory is still verbatim:

    for f in *.cpp *.hpp; do cmp -s "$f" ~/github/cadical/src/"$f" || echo "DIFF $f"; done
