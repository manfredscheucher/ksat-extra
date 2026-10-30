package org.bytefred.ksat.playground.core

/** The CNF the text field starts with: exactly one of x1, x2, x3 (SAT, 3 solutions). */
const val STARTER_EXAMPLE: String = """c exactly one of x1, x2, x3 (3 solutions)
p cnf 3 4
1 2 3 0
-1 -2 0
-1 -3 0
-2 -3 0
"""

/** A parameter of an [Example]: its name, what it means, and its default value. */
class ExampleParam(val name: String, val meaning: String, val default: Int)

/**
 * The generated examples of the Examples dialog, each with its parameters and a short description
 * (doc/playground.md, Revision 1). No parameter bounds: every non-negative value generates a CNF.
 */
enum class Example(val title: String, val params: List<ExampleParam>, val description: String) {
    XOR(
        "Example 0 (XOR): (x1 ∨ x2) ∧ (¬x1 ∨ ¬x2) (2 solutions)",
        emptyList(),
        "",
    ),
    EXACTLY_K_OF_N(
        "Example 1: choose exactly k of n objects (n choose k solutions)",
        listOf(ExampleParam("k", "sample size", 2), ExampleParam("n", "number of objects", 4)),
        "Every (k+1)-subset contains a false object: C(n,k+1) clauses. For every (k-1)-subset T, " +
            "some object outside T is true: C(n,k-1) clauses.",
    ),
    PIGEONHOLE(
        "Example 2 (Pigeonhole Principle): pack n+1 pigeons into n holes (UNSAT)",
        listOf(ExampleParam("n", "number of holes", 5)),
        "Every pigeon sits in a hole: n+1 clauses. No hole holds two pigeons: n·C(n+1,2) clauses.",
    ),
    RAMSEY(
        "Example 3 (Ramsey Numbers on Graphs): construct n-vertex graph with no k-clique or independent set of size l",
        listOf(
            ExampleParam("n", "number of vertices", 6),
            ExampleParam("k", "clique size", 3),
            ExampleParam("l", "independent set size", 3),
        ),
        "C(n,2) edge variables. Every k-subset of vertices has a missing edge: C(n,k) clauses. " +
            "Every l-subset has an edge: C(n,l) clauses.",
    );

    /**
     * The DIMACS text for [values] (one per [params], each >= 0), with `c` comment lines naming the
     * example and its parameters. [checkCancelled] is called once per clause, so a long generation
     * can be cancelled by throwing from it.
     */
    fun dimacs(values: List<Int>, checkCancelled: () -> Unit = {}): String {
        require(values.size == params.size) { "$name takes ${params.size} parameters, got ${values.size}" }
        for ((p, v) in params.zip(values)) require(v >= 0) { "${p.name} must not be negative, got $v" }
        val comment = if (params.isEmpty()) title
        else "$title\nc " + params.zip(values).joinToString(", ") { (p, v) -> "${p.name}=$v" }
        return when (this) {
            XOR -> cnf(comment, 2, checkCancelled) { add(1, 2); add(-1, -2) }
            EXACTLY_K_OF_N -> exactlyKOfN(comment, values[0], values[1], checkCancelled)
            PIGEONHOLE -> pigeonhole(comment, values[0], checkCancelled)
            RAMSEY -> ramsey(comment, values[0], values[1], values[2], checkCancelled)
        }
    }
}

/**
 * Whether [text] is a valid example parameter: a non-negative integer (optional sign, any size;
 * `-0` counts as 0). Anything else disables Generate.
 */
fun isParamText(text: String): Boolean {
    val t = text.trim()
    return Regex("[+-]?[0-9]+").matches(t) && !(t.startsWith('-') && t.any { it in '1'..'9' })
}

/** The pigeonhole formula for n holes, as the PIGEONHOLE example generates it. */
fun pigeonholeDimacs(n: Int): String = Example.PIGEONHOLE.dimacs(listOf(n))

/** Collects clause lines and counts them; [add] calls checkCancelled. */
private class ClauseWriter(private val checkCancelled: () -> Unit) {
    val lines = StringBuilder()
    var count = 0L

    fun add(vararg literals: Int) = add(literals.asList())

    fun add(literals: List<Int>) {
        checkCancelled()
        for (l in literals) lines.append(l).append(' ')
        lines.append("0\n")
        count++
    }
}

private fun cnf(comment: String, numVars: Long, checkCancelled: () -> Unit, clauses: ClauseWriter.() -> Unit): String {
    require(numVars <= Int.MAX_VALUE) { "$numVars variables do not fit a DIMACS variable (Int)" }
    val w = ClauseWriter(checkCancelled).apply(clauses)
    return "c $comment\np cnf $numVars ${w.count}\n${w.lines}"
}

/** Every [size]-subset of 0 until [n] (as a sorted index array, reused between calls), in lexicographic order. */
private inline fun forEachSubset(n: Int, size: Int, visit: (IntArray) -> Unit) {
    if (size > n) return
    val s = IntArray(size) { it }
    while (true) {
        visit(s)
        var i = size - 1
        while (i >= 0 && s[i] == n - size + i) i--
        if (i < 0) return
        s[i]++
        for (j in i + 1 until size) s[j] = s[j - 1] + 1
    }
}

/**
 * Exactly k of n objects (variables 1..n) true: every (k+1)-subset contains a false, and for every
 * (k-1)-subset T some object outside T is true (for k = 0 there is no such T). k > n: only the
 * empty clause (UNSAT).
 */
private fun exactlyKOfN(comment: String, k: Int, n: Int, checkCancelled: () -> Unit): String =
    cnf(comment, n.toLong(), checkCancelled) {
        if (k > n) {
            add()
        } else {
            if (k < n) forEachSubset(n, k + 1) { s -> add(s.map { -(it + 1) }) }
            if (k >= 1) forEachSubset(n, k - 1) { t ->
                val outside = ArrayList<Int>(n - t.size)
                var next = 0
                for (v in 0 until n) if (next < t.size && t[next] == v) next++ else outside += v + 1
                add(outside)
            }
        }
    }

/**
 * n+1 pigeons into n holes: variable `p(i, j) = i*n + j + 1` says pigeon i (0..n) sits in hole j
 * (0..n-1). Every pigeon sits in a hole (one clause per pigeon, empty for n = 0), and no hole holds
 * two pigeons (one binary clause per hole and pair of pigeons).
 */
private fun pigeonhole(comment: String, n: Int, checkCancelled: () -> Unit): String {
    val pigeons = n.toLong() + 1
    return cnf(comment, pigeons * n, checkCancelled) {
        fun p(i: Int, j: Int) = i * n + j + 1
        for (i in 0..n) add((0 until n).map { j -> p(i, j) })
        for (j in 0 until n) forEachSubset(n + 1, 2) { (a, b) -> add(-p(a, j), -p(b, j)) }
    }
}

/**
 * A graph on n vertices without a k-clique and without an independent set of size l: one variable
 * per edge {i, j} (true = edge present), every k-subset of vertices has a missing edge, every
 * l-subset has an edge. A subset with fewer than two vertices has no edges, so its clause is empty.
 */
private fun ramsey(comment: String, n: Int, k: Int, l: Int, checkCancelled: () -> Unit): String {
    // edge {i, j}, i < j: numbered row by row, 1-based
    fun e(i: Int, j: Int) = (i.toLong() * (2L * n - i - 1) / 2 + (j - i)).toInt()
    fun edges(s: IntArray, sign: Int): List<Int> {
        val lits = ArrayList<Int>(s.size * (s.size - 1) / 2)
        for (a in s.indices) for (b in a + 1 until s.size) lits += sign * e(s[a], s[b])
        return lits
    }
    return cnf(comment, n.toLong() * (n - 1) / 2, checkCancelled) {
        forEachSubset(n, k) { s -> add(edges(s, -1)) }
        forEachSubset(n, l) { s -> add(edges(s, 1)) }
    }
}
