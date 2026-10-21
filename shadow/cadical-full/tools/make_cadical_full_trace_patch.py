#!/usr/bin/env python3
"""Throwaway helper: insert the LSTRACE prints into a COPY of upstream CaDiCaL.

Usage: make_cadical_full_trace_patch.py <dir-with-copy-of-upstream-src>
Each edit is an exact anchor that must occur exactly once; the inserted text is
placed AFTER the anchor (or BEFORE it for kind 'before'). The resulting dir is
then diffed against upstream/ to produce shadow/cadical-full/trace.patch.
"""
import os
import sys

d = sys.argv[1]

PRINT_CLAUSE = None  # documentation only

EDITS = [
    # ---- include the trace helpers everywhere Internal is visible
    ("internal.hpp", "after", '#include "watch.hpp"\n', '#include "lstrace.hpp" // LSTRACE\n'),
    # ---- ASSIGN (every search assignment, incl. units and driving literals)
    ("propagate.cpp", "after",
     "  const bool from_external = reason == external_reason;\n",
     "  const Clause *const lstrace_reason = reason; // LSTRACE\n"),
    ("propagate.cpp", "before",
     "#ifdef LOGGING\n  if (!lit_level)\n    LOG (\"root-level unit assign %d @ 0\", lit);\n",
     "  if (lstrace_on ()) { // LSTRACE\n"
     "    printf (\"ASSIGN %d level=%d reason=\", externalize (lit), lit_level);\n"
     "    if (lstrace_reason == decision_reason)\n"
     "      printf (\"D\\n\");\n"
     "    else if (!lit_level)\n"
     "      printf (\"U\\n\");\n"
     "    else if (from_external)\n"
     "      printf (\"E\\n\");\n"
     "    else {\n"
     "      printf (\"C %\" PRIu64 \" :\", reason->id);\n"
     "      lstrace_lits (this, *reason);\n"
     "      printf (\"\\n\");\n"
     "    }\n"
     "  }\n"),
    # ---- DECIDE (search, assumption and constraint decisions; lucky too)
    ("propagate.cpp", "after",
     "  LOG (\"search decide %d\", lit);\n",
     "  LSTRACE (\"DECIDE %d\\n\", externalize (lit)); // LSTRACE\n"),
    # ---- DECIDE 0: pseudo decision level (assumption/constraint already true)
    ("decide.cpp", "after",
     "void Internal::new_trail_level (int lit) {\n  level++;\n",
     "  if (!lit) // LSTRACE\n    LSTRACE (\"DECIDE 0\\n\");\n"),
    # ---- CONFLICT
    ("analyze.cpp", "after",
     "  START (analyze);\n\n  assert (conflict);\n",
     "  if (lstrace_on ()) { // LSTRACE\n"
     "    printf (\"CONFLICT level=%d %\" PRIu64 \" :\", level, conflict->id);\n"
     "    lstrace_lits (this, *conflict);\n"
     "    printf (\"\\n\");\n"
     "  }\n"),
    # ---- LEARN (1st-UIP clause after minimize/shrink, in stored order)
    ("analyze.cpp", "before",
     "  LOG (\"jump level %d\", jump);\n",
     "  if (lstrace_on ()) { // LSTRACE\n"
     "    printf (\"LEARN id=%\" PRIu64 \" glue=%d jump=%d :\", res ? res->id : (uint64_t) 0,\n"
     "            glue, jump);\n"
     "    lstrace_lits (this, clause);\n"
     "    printf (\"\\n\");\n"
     "  }\n"),
    # ---- OTFS (on-the-fly strengthened reason becomes the new conflict)
    ("analyze.cpp", "after",
     "      reason = on_the_fly_strengthen (reason, uip);\n",
     "      if (lstrace_on ()) { // LSTRACE\n"
     "        if (reason) {\n"
     "          printf (\"OTFS %\" PRIu64 \" :\", reason->id);\n"
     "          lstrace_lits (this, *reason);\n"
     "          printf (\"\\n\");\n"
     "        } else\n"
     "          printf (\"OTFS 0 : 0\\n\");\n"
     "      }\n"),
    # ---- BACKTRACK
    ("backtrack.cpp", "after",
     "void Internal::backtrack (int new_level) {\n\n  assert (new_level <= level);\n"
     "  if (new_level == level)\n    return;\n",
     "  LSTRACE (\"BACKTRACK %d\\n\", new_level); // LSTRACE\n"),
    # ---- RESTART / MODE
    ("restart.cpp", "after",
     "void Internal::restart () {\n  START (restart);\n",
     "  LSTRACE (\"RESTART\\n\"); // LSTRACE\n"),
    ("restart.cpp", "after",
     "    stable = !stable;\n",
     "    LSTRACE (\"MODE %s\\n\", stable ? \"stable\" : \"focused\"); // LSTRACE\n"),
    # ---- REDUCE / FLUSH
    ("reduce.cpp", "after",
     "  bool flush = flushing ();\n",
     "  LSTRACE (\"%s\\n\", flush ? \"FLUSH\" : \"REDUCE\"); // LSTRACE\n"),
    # ---- REPHASE <type>
    ("rephase.cpp", "after",
     "  assert (type);\n\n",
     "  LSTRACE (\"REPHASE %c\\n\", type); // LSTRACE\n"),
]

PHASES = [
    ("internal.cpp", "bool Internal::preprocess_round (int round) {\n", "preprocess"),
    ("probe.cpp", "void CaDiCaL::Internal::probe (bool update_limits) {\n", "probe"),
    ("vivify.cpp", "void Internal::vivify () {\n", "vivify"),
    ("subsume.cpp", "void Internal::subsume (bool update_limits) {\n", "subsume"),
    ("elim.cpp", "void Internal::elim (bool update_limits) {\n", "elim"),
    ("block.cpp", "bool Internal::block () {\n", "block"),
    ("cover.cpp", "bool Internal::cover () {\n", "cover"),
    ("condition.cpp", "void Internal::condition (bool update_limits) {\n", "condition"),
    ("ternary.cpp", "bool Internal::ternary () {\n", "ternary"),
    ("decompose.cpp", "void Internal::decompose () {\n", "decompose"),
    ("transred.cpp", "void Internal::transred () {\n", "transred"),
    ("instantiate.cpp", "void Internal::instantiate (Instantiator &instantiator) {\n", "instantiate"),
    ("deduplicate.cpp", "void Internal::mark_duplicated_binary_clauses_as_garbage () {\n", "deduplicate"),
    ("lucky.cpp", "int Internal::lucky_phases () {\n", "lucky"),
    ("walk.cpp", "int Internal::walk_round (int64_t limit, bool prev) {\n", "walk"),
    ("rephase.cpp", "void Internal::rephase () {\n", "rephase"),
    ("compact.cpp", "void Internal::compact () {\n", "compact"),
    ("collect.cpp", "void Internal::garbage_collection () {\n", "collect"),
]
for f, anchor, name in PHASES:
    EDITS.append((f, "after", anchor, '  LSTRACE_PHASE ("%s"); // LSTRACE\n' % name))

for f, kind, anchor, text in EDITS:
    p = os.path.join(d, f)
    with open(p) as fh:
        src = fh.read()
    n = src.count(anchor)
    if n != 1:
        sys.exit("FATAL: anchor occurs %d times in %s: %r" % (n, f, anchor))
    i = src.index(anchor)
    if kind == "after":
        src = src[: i + len(anchor)] + text + src[i + len(anchor):]
    else:
        src = src[:i] + text + src[i:]
    with open(p, "w") as fh:
        fh.write(src)
print("applied %d edits" % len(EDITS))
