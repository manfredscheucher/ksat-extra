package org.bytefred.ksat.playground.core

/** The CNF the text field starts with: exactly one of x1, x2, x3 (SAT, 3 solutions). */
const val STARTER_EXAMPLE: String = """c exactly one of x1, x2, x3 (3 solutions)
p cnf 3 4
1 2 3 0
-1 -2 0
-1 -3 0
-2 -3 0
"""

/** The pigeonhole sizes the Examples dialog offers (larger ones only bloat the text field). */
val PIGEONHOLE_K_RANGE: IntRange = 1..30

/**
 * The pigeonhole formula PHP(k) as DIMACS: k+1 pigeons into k holes, UNSAT for every k >= 1.
 * Variable `p(i, j) = i*k + j + 1` says pigeon i (0..k) sits in hole j (0..k-1). Every pigeon sits
 * in some hole (one clause per pigeon), and no hole holds two pigeons (one binary clause per hole
 * and pair of pigeons).
 */
fun pigeonholeDimacs(k: Int): String {
    require(k >= 1) { "PHP(k) needs k >= 1, got $k" }
    fun p(i: Int, j: Int) = i * k + j + 1
    val pigeons = k + 1
    val clauses = ArrayList<String>()
    for (i in 0 until pigeons) {
        clauses += (0 until k).joinToString(" ", postfix = " 0") { j -> p(i, j).toString() }
    }
    for (j in 0 until k) {
        for (a in 0 until pigeons) for (b in a + 1 until pigeons) {
            clauses += "-${p(a, j)} -${p(b, j)} 0"
        }
    }
    return buildString {
        append("c pigeonhole PHP($k): $pigeons pigeons, $k holes (UNSAT)\n")
        append("p cnf ${pigeons * k} ${clauses.size}\n")
        for (c in clauses) append(c).append('\n')
    }
}
