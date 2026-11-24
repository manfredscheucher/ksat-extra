package org.bytefred.ksat.playground.ui

import org.bytefred.ksat.facade.Solver
import org.bytefred.ksat.playground.core.Mode

/** Tests only: store the default settings, so a new view model starts like a first visit. */
fun resetPlaygroundPrefs() {
    savePref(SOLVER_PREF, Solver.MINISAT.name)
    savePref(MODE_PREF, Mode.ONE.name)
    for (solver in Solver.entries) savePref(optionsPref(solver.name), "")
}
