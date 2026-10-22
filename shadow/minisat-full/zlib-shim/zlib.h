/* zlib.h shim for the minisat-full shadow reference (NOT zlib).
 *
 * Upstream minisat/utils/ParseUtils.h includes <zlib.h> and its StreamBuffer reads through
 * gzread(gzFile, buf, len); minisat/core/Dimacs.h's parse_DIMACS takes a gzFile. Those are
 * the only zlib names the compiled sources use (gzopen/gzdopen/gzclose appear only in the
 * Main.cc apps, which are not compiled). This shim maps gzFile to a plain stdio FILE*, so
 * the verbatim parser reads uncompressed DIMACS without linking zlib. build_and_trace.sh
 * puts this directory first on the include path.
 */
#ifndef LSTRACE_ZLIB_SHIM_H
#define LSTRACE_ZLIB_SHIM_H

#include <stdio.h>

typedef FILE* gzFile;

/* zlib: number of bytes read, 0 at end of file, -1 on error. */
static inline int gzread(gzFile file, void* buf, unsigned len) {
    size_t n = fread(buf, 1, len, file);
    if (n == 0 && ferror(file)) return -1;
    return (int)n;
}

#endif
