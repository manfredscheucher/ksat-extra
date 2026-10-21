// Throwaway probe: runs the Kotlin snippets of sat-techniques/06-incremental.typ against the real ports.
import org.bytefred.ksat.ExternalPropagator
import org.bytefred.ksat.FixedAssignmentListener
import org.bytefred.ksat.OutBoolean
import org.bytefred.ksat.SatResult
import org.bytefred.ksat.facade.Ksat
import org.bytefred.ksat.facade.Solver
import org.bytefred.ksat.facade.enumerateModels
import kotlin.math.abs

val log = ArrayList<String>()

/** At most one of [vars] is true. Eager propagation, lazy reasons. */
class AtMostOne(private val vars: IntArray, firstDecision: Int = 0) :
    ExternalPropagator {
    private val trail = mutableListOf(mutableListOf<Int>()) // lits per level
    private val value = HashMap<Int, Int>()          // var -> assigned literal
    private val reasons = HashMap<Int, IntArray>()   // propagated lit -> reason
    private var pending: ArrayDeque<Int>? = null    // reason being handed out
    private val toAdd = ArrayDeque<IntArray>()       // clauses for the solver
    private var addPos = 0
    private var suggestion = firstDecision

    override fun notifyAssignment(lits: IntArray) {
        for (lit in lits) { value[abs(lit)] = lit; trail.last().add(lit) }
    }

    override fun notifyNewDecisionLevel() { trail.add(mutableListOf()) }

    override fun notifyBacktrack(newLevel: Int) {
        while (trail.size - 1 > newLevel)
            for (lit in trail.removeAt(trail.lastIndex)) value.remove(abs(lit))
    }

    override fun cbDecide(): Int = suggestion.also { suggestion = 0 }

    override fun cbPropagate(): Int {
        val t = vars.firstOrNull { value[it] == it } ?: return 0 // a true var?
        val u = vars.firstOrNull { it != t && value[it] != -it } ?: return 0
        reasons[-u] = intArrayOf(-t, -u)        // keep the reason, do not send
        return -u
    }

    override fun cbAddReasonClauseLit(propagatedLit: Int): Int {
        val q = pending ?: ArrayDeque(reasons.getValue(propagatedLit).toList())
        pending = q
        if (q.isEmpty()) { pending = null; return 0 }
        return q.removeFirst()
    }

    override fun cbCheckFoundModel(model: IntArray): Boolean {
        val trueVars = model.filter { it > 0 && it in vars }
        if (trueVars.size <= 1) return true
        toAdd.addLast(intArrayOf(-trueVars[0], -trueVars[1])) // reject, explain
        return false
    }

    override fun cbHasExternalClause(isForgettable: OutBoolean) =
        toAdd.isNotEmpty()

    override fun cbAddExternalClauseLit(): Int {
        val c = toAdd.first()
        if (addPos < c.size) return c[addPos++]
        toAdd.removeFirst(); addPos = 0
        return 0
    }
}

/** Logging decorator so the probe can print the callback sequence. */
class Logged(private val p: ExternalPropagator) : ExternalPropagator {
    override fun notifyAssignment(lits: IntArray) { log += "notifyAssignment(${lits.toList()})"; p.notifyAssignment(lits) }
    override fun notifyNewDecisionLevel() { log += "notifyNewDecisionLevel"; p.notifyNewDecisionLevel() }
    override fun notifyBacktrack(newLevel: Int) { log += "notifyBacktrack($newLevel)"; p.notifyBacktrack(newLevel) }
    override fun cbDecide(): Int = p.cbDecide().also { log += "cbDecide -> $it" }
    override fun cbPropagate(): Int = p.cbPropagate().also { log += "cbPropagate -> $it" }
    override fun cbAddReasonClauseLit(propagatedLit: Int): Int = p.cbAddReasonClauseLit(propagatedLit).also { log += "cbAddReasonClauseLit($propagatedLit) -> $it" }
    override fun cbCheckFoundModel(model: IntArray): Boolean = p.cbCheckFoundModel(model).also { log += "cbCheckFoundModel(${model.toList()}) -> $it" }
    override fun cbHasExternalClause(isForgettable: OutBoolean): Boolean = p.cbHasExternalClause(isForgettable).also { log += "cbHasExternalClause -> $it" }
    override fun cbAddExternalClauseLit(): Int = p.cbAddExternalClauseLit().also { log += "cbAddExternalClauseLit -> $it" }
}

fun main() {
    // A: tie/shirt
    for (s in listOf(Solver.CADICAL, Solver.MINISAT)) {
        val k = Ksat(s, numVars = 2)
        k.addClause(intArrayOf(-1, 2)); k.addClause(intArrayOf(1, 2)); k.addClause(intArrayOf(-1, -2))
        check(k.solve() == SatResult.SAT); check(!k.valueOf(1) && k.valueOf(2))
        check(k.solve(assumptions = intArrayOf(1)) == SatResult.UNSAT); check(k.failed(1))
        check(k.solve(assumptions = intArrayOf(-2)) == SatResult.UNSAT); check(k.failed(-2))
        println("A ok $s")
    }
    // B: core
    for (s in listOf(Solver.CADICAL, Solver.MINISAT)) {
        val k = Ksat(s, numVars = 4)
        k.addClause(intArrayOf(-1, -2, 3)); k.addClause(intArrayOf(-1, 4, 3)); k.addClause(intArrayOf(-1, -4, 3))
        val assumptions = intArrayOf(1, 2, -3)
        check(k.solve(assumptions) == SatResult.UNSAT)
        println("B $s core = ${assumptions.filter { k.failed(it) }}")
        val a2 = intArrayOf(1, -3)
        println("B $s smaller: ${k.solve(a2)} core = ${a2.filter { k.failed(it) }}")
        println("B $s re-solve original: ${k.solve(assumptions)} core = ${assumptions.filter { k.failed(it) }}")
    }
    // C: add after solve
    for (s in listOf(Solver.CADICAL, Solver.MINISAT, Solver.KISSAT)) {
        val k = Ksat(s, numVars = 2)
        k.addClause(intArrayOf(1, 2))
        val r1 = k.solve(); val m1 = listOf(k.valueOf(1), k.valueOf(2))
        k.addClause(intArrayOf(-1))
        val r2 = k.solve()
        println("C $s $r1 $m1 then $r2 ${listOf(k.valueOf(1), k.valueOf(2))}")
    }
    // D: enumerate
    val xor = listOf(intArrayOf(1, 2), intArrayOf(-1, -2))
    for (s in listOf(Solver.CADICAL, Solver.MINISAT, Solver.KISSAT))
        println("D $s ${enumerateModels(s, numVars = 2, cnf = xor, incremental = true).toList()}")
    println("D count (a b) over 3: ${enumerateModels(Solver.CADICAL, numVars = 3, cnf = listOf(intArrayOf(1, 2)), incremental = true).count()}")
    // E: propagator
    for (decide in listOf(false, true)) {
        log.clear()
        val k = Ksat(Solver.CADICAL, numVars = 4)
        k.addClause(intArrayOf(1, 2, 3)); k.addClause(intArrayOf(2, 4)); k.addClause(intArrayOf(2, -4))
        k.connectExternalPropagator(Logged(AtMostOne(intArrayOf(1, 2, 3), firstDecision = if (decide) 1 else 0)))
        for (v in 1..3) k.addObservedVar(v)
        val r = k.solve()
        println("E decide=$decide $r ${(1..4).map { k.valueOf(it) }}")
        log.forEach { println("   $it") }
    }
    // E2: model check path: AMO over (a,b) but solver forces a and b true via units -> UNSAT
    run {
        log.clear()
        val k = Ksat(Solver.CADICAL, numVars = 2)
        k.connectExternalPropagator(Logged(AtMostOne(intArrayOf(1, 2))))
        for (v in 1..2) k.addObservedVar(v)
        k.addClause(intArrayOf(1)); k.addClause(intArrayOf(2))
        println("E2 ${k.solve()}"); log.forEach { println("   $it") }
    }
    // E3: rejection path only (propagation switched off)
    run {
        log.clear()
        val k = Ksat(Solver.CADICAL, numVars = 4)
        k.addClause(intArrayOf(1, 2, 3)); k.addClause(intArrayOf(2, 4)); k.addClause(intArrayOf(2, -4))
        val amo = AtMostOne(intArrayOf(1, 2, 3), firstDecision = 1)
        k.connectExternalPropagator(Logged(object : ExternalPropagator by amo { override fun cbPropagate() = 0 }))
        for (v in 1..3) k.addObservedVar(v)
        println("E3 ${k.solve()} ${(1..4).map { k.valueOf(it) }}"); log.forEach { println("   $it") }
    }
    // E2: AMO with no other constraint except at-least-two? exercise check_found_model: lazy-only path
    // F: phase
    for (p in listOf(intArrayOf(1, 2), intArrayOf(-1, 2), intArrayOf(1, -2))) {
        val k = Ksat(Solver.CADICAL, numVars = 2)
        k.addClause(intArrayOf(-1, -2)); for (l in p) k.phase(l)
        println("F phases ${p.toList()}: ${k.solve()} ${listOf(k.valueOf(1), k.valueOf(2))}")
    }
    // G: fixed listener
    val k = Ksat(Solver.CADICAL, numVars = 4)
    k.connectFixedListener(object : FixedAssignmentListener {
        override fun notifyFixedAssignment(lit: Int) = println("G fixed $lit")
    })
    k.addClause(intArrayOf(1, 2)); k.addClause(intArrayOf(-2, -3)); k.addClause(intArrayOf(3, 4))
    println("G adding unit"); k.addClause(intArrayOf(-1)); println("G solving")
    println("G ${k.solve()}")
}
