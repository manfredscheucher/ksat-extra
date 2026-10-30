# ksat playground (interactive second example)

## What was asked (Manfred, 2026-10-29)

Keep the current demo (`demo/`, XOR enumeration). Add a second, interactive example, similar to
ktoy (~/github/ktoy):

- paste a CNF directly as text (DIMACS); start with an example in the text field
- an "Examples" button that generates the pigeonhole formula PHP for a given k; a "Load file" button
- a dropdown to choose the solver
- radio buttons: "one solution" / "all solutions"
- the result first only says SAT / UNSAT (with SAT: 1 or n solutions); the solutions themselves
  are shown only after a click ("show solutions"), then one solution per line
  - one-solution mode: e.g. "SAT: stopped after one solution (click to show)"
  - all-solutions mode: e.g. "SAT: n solutions in total (click to show)"
- show how long the solver has been running (timer)
- layout: Claude's choice, checked with a reviewer
- then (same day): "schreib vlt wirklich wie ne konsole raus": a console-like log with time stamps,
  e.g.
      12:03:41  start solving
      12:03:42  found solution #1
      12:03:42  stop.
- then (same day), all-solutions mode:
      <time>  solution #1 found (click to show)
      <time>  solution #2 found (click to show)
      ...
      <time>  no more solutions. stop.
  i.e. each solution is its own log line, clickable to show that assignment. (The message
  started with "bei 1 solution search" without text; interpreted as the same line format:
  `solution #1 found (click to show)`, then `stop.`)

Answers to Claude's questions (same day):

- UI technology: Compose Multiplatform like ktoy
- targets: like ktoy, incl. Android ("schau dass du es wie ktoy hältst"): web (JS), JVM desktop,
  Android
- long solves: solve in a Web Worker on the web, with a Stop button; the page stays responsive

## Decisions and interpretations (Claude)

- New module `playground/` (shared Compose UI, like ktoy's `composeApp`) plus
  `playground/androidApp/` (AGP 9 does not allow an Android application inside a KMP module; same
  split as `demo/androidApp/`) and `playground/worker/` (Kotlin/JS Web Worker bundle, as in
  sat-chess-kotlin).
- Dev server port 8609 (registered in ~/github/.dev-ports.md).
- GitHub Pages: the playground at the site root, the existing XOR demo under `xor-demo/`, linked from
  each other.
- "PHP for k": k+1 pigeons into k holes (UNSAT), the standard pigeonhole formula.
- All-solutions mode: enumerate by blocking clauses (ksat `enumerateModels`), counting as it goes;
  Stop keeps the count found so far and says the enumeration was stopped.
- Output = a console log (monospace, one line per event, full local date-time with milliseconds `yyyy-MM-dd HH:mm:ss.SSS`, as Manfred asked): start line
  (solver, mode, variables/clauses); each solution as `solution #i found (click to show)`, a click
  expands that line to show the assignment (DIMACS literals, e.g. `1 -2 3`); the end as
  `stop.` (one-solution mode), `no more solutions. stop.` (all solutions, enumeration finished),
  `UNSAT. stop.` (no solution), `stopped by user.` or a parse error. While the solver runs, a live
  elapsed-time counter is shown. (This replaces the earlier summary + "show solutions" idea.)

### Made while building (Claude)

- Start line: `start solving: <SOLVER>, <mode>, <n> variables, <m> clauses`. It is logged after the
  CNF is parsed (inside the solver run), so it carries the counts; a parse error instead logs
  `error: DIMACS parse error at line N: <reason>`. "Stop keeps the count found so far" is realized
  as: the `solution #i found` lines stay, then `stopped by user.`.
- Time stamps are taken where the event happens (in the Web Worker / on the solver thread), not when
  the UI receives the message.
- An expanded solution line reads `solution #i found (click to hide)`, the assignment below it.
- The console keeps earlier runs (like a console); a "Clear" button empties it.
- Starter example in the text field: "exactly one of x1, x2, x3" (SAT, 3 solutions), so both modes
  show something. Defaults: solver MINISAT, mode "one solution".
- Examples dialog: the starter CNF, and PHP(k) with k typed in (default 5, allowed 1..30; larger
  texts make the text field sluggish and are far beyond what solves in reasonable time).
- All-solutions mode: incremental enumeration (one warm solver) for CADICAL, KISSAT; a fresh
  solver per round for MICROSAT and MINISAT (facade rule; MiniSat runs with its default option
  pre=1). Zero solutions logs `UNSAT. stop.`.
- Elapsed timer next to the buttons: `running m:ss.t` while solving, `time m:ss.t` afterwards.
- Layout: header (title; on the web a link to the XOR demo), one row of controls (wraps on narrow
  screens), then the editor and the console: side by side from 840 dp width, stacked below.
- Stop on JVM/Android: the ksat facade has no interrupt, so Stop ends the run in the UI at once
  (`stopped by user.`) and the enumeration does not start another solve, but a solve call that is
  already running keeps going on its own background thread until it returns (its result is dropped;
  it keeps a CPU core busy until then). Each run gets its own thread (cached pool), so such leftovers
  never hold up the next run. On the web Stop terminates the worker, which ends it at once.
- Load file errors (unreadable file) are logged as `error: cannot read <file>: <reason>`.
- Known limit: an all-solutions run over a CNF with very many cheap solutions (e.g. many free
  variables) adds one console line per solution as fast as the solver finds them, until Stop; the
  console is not capped.
- The "XOR demo" link (web only) points to `xor-demo/`, which exists on the built site
  (`scripts/buildWeb.sh`), not on the dev server.
- Load file: .cnf/.dimacs/.txt filter on web and JVM; any file on Android (Storage Access Framework).
- compileSdk: ktoy's Compose MP 1.12.1 / lifecycle 2.11.0 require compileSdk 37, while ksat-extra's
  `android-compileSdk` (36) must match the main repo. The playground modules therefore use their own
  catalog entry `android-playgroundCompileSdk = "37"` (also the app's targetSdk).
- Monospace font: DejaVu Sans Mono bundled as in ktoy (license: `licenses/dejavu-LICENSE.txt`).
- Worker protocol: plain text (`SolveRequest.encode` / `SolveEvent.encode`), no serialization library.
  The worker module reuses the solver logic from `:playground` and is always built as the production
  bundle (also for the dev server): only its dead-code elimination drops the Compose UI from the
  worker. (Alternative if that ever bites: a fourth, Compose-free `playground/core` module.)
- XOR demo back link: `scripts/buildWeb.sh` adds it to the deployed copy of the demo's index.html,
  after the demo's script (which replaces the page body), so `demo/` stays unchanged.
- Tests: commonTest unit tests (PHP generator, solver run incl. every solver, worker protocol,
  formatting, the ViewModel state machine with a fake solver service). No Compose UI test, as ktoy
  has none.

## Revision 1 (Manfred, 2026-10-30)

- "click to show" toggles all solutions at once (show all / hide all); per-solution toggling makes no
  sense.
- Do not call the output a "console" (it is interactive show/hide, not a console).
- No timer at the top. Instead the end of a run gets its own line, the same in one- and
  all-solutions mode: `terminated after X` (not `stop.`). Duration format: Claude to look at what
  is standard (e.g. ms / s / a days-hours-minutes-seconds-ms breakdown); Manfred has no fixed format.
- All-solutions mode: an extra line `no more solutions.` before the `terminated after` line.
- No "Clear" button: clicking Solve clears the output automatically.
- Examples: add Ramsey numbers; no parameter bounds (PHP neither).
- Examples dialog: radio buttons, one per example; selecting one shows its parameters; a
  "Generate" button next to Cancel creates the instance.
- Example texts (Manfred's draft, terminology open for review):
  - Example 1: choose exactly k of n objects (n choose k solutions). Params k (sample size),
    n (number of objects), default k=2, n=4. Description: every (k+1)-subset must contain a false
    (if k<n), C(n,k+1) constraints; "every (k-1)-subset must contain a true (if k>1), C(n,k-1)
    constraints".
  - Example 2 (Pigeonhole Principle): pack n+1 pigeons into n holes (UNSAT). Param n (number of
    holes). Description in the same style, with constraint counts.
  - Example 3 (Ramsey Numbers on Graphs): construct an n-vertex graph with no k-clique and no
    l-anticlique. Params n, k, l ("by default 3,3"). Description: C(n,2) edge variables; every
    k-subset of vertices (C(k,2) edges) has a false edge (no clique); every l-subset has a true
    edge (no anticlique).

Answers to Claude's questions (same day):

- Example 1 at-least part: for every (k-1)-subset T, some object outside T is true
  (C(n,k-1) clauses, also for k=1, where T is empty: one clause over all n objects). So there are
  always C(n,k) solutions; k>n is UNSAT (empty clause).
- Ramsey: default n=6, k=3, l=3 (UNSAT, R(3,3)=6); term "independent set" (not "anticlique").
- Duration: Kotlin `Duration.toString()` style, rounded to ms (`412ms`, `3.412s`, `1m 3.412s`).
- Show/hide all solutions: a toggle button next to Solve.
- PHP default n: not specified, keeps the earlier 5 (Claude).
- Solver dropdown: only one MiniSat. Solver features are chosen by options instead (see
  `solver-options.md`): an "Options" button shows the options of the selected solver.
- (later, same day) "xor-demo kannst rauswerfen, die demo braucht nicht auf die website; also nicht
  in der form. kannst ja example 0: XOR machn ohne parameter": the XOR demo is no longer deployed
  to GitHub Pages (the `demo/` module itself stays in the repo; the playground's "XOR demo" link
  goes). New Example 0: XOR, no parameters, as in the demo: XOR(x1, x2) = (x1 ∨ x2) ∧ (¬x1 ∨ ¬x2),
  2 variables, 2 clauses, 2 solutions. The starter text in the editor stays as it is.
- Example 0 description: just note "2 solutions"; it is trivial. In general: keep the example texts
  uniform and short; nothing simple gets extra text just so that there is text (check with a
  reviewer).

### Revision 1: made while building (Claude)

- Output lines: the start line (`start solving: <SOLVER>, <mode>, <n> variables, <m> clauses`) is
  unchanged and does not list the options. The end lines carry the time of the end event (worker /
  solver thread; Stop: when Stop was clicked); X = end time minus the time Solve was clicked.
- Duration: `Duration.toString()` of whole milliseconds, so trailing zeros are dropped as Kotlin does
  (`2.55s`, `1s`) and zero is `0s`.
- An error ends a run with the error line only (parse error, and also an option ksat rejects, which
  comes after the start line), no `terminated after` line.
- Show / Hide solutions: right after Solve (then Stop), always enabled, and its state stays across
  runs (Solve does not reset it).
- Examples dialog: the radio label is the example's title, in Manfred's draft form
  "Example i (Name): what it does (solution info)" (after a reviewer found the first titles
  non-uniform): `Example 0 (XOR): (x1 ∨ x2) ∧ (¬x1 ∨ ¬x2) (2 solutions)` (no description),
  `Example 1: choose exactly k of n objects (n choose k solutions)`, `Example 2 (Pigeonhole
  Principle): pack n+1 pigeons into n holes (UNSAT)`, `Example 3 (Ramsey Numbers on Graphs):
  construct n-vertex graph with no k-clique or independent set of size l`. Descriptions hold only
  the clause families with counts. The selected one shows its parameter fields
  (`name (meaning)`) and the description below its radio button. The dialog starts at XOR with the
  default values each time it opens. Generated CNF: `c <title>`, then `c n=6, k=3, l=3` (no second
  line for XOR).
- Parameters: valid = an integer >= 0 (optional sign, `-0` counts as 0). A valid value above
  2147483647 (Int) is not rejected by the dialog: Generate logs
  `error: cannot generate the example: n = ... is larger than 2147483647`. An instance with more than
  2147483647 variables fails the same way (DIMACS variables are Int).
- Generation runs in a Web Worker on the web (same worker script, a `generate` request) and on a
  background thread on JVM/Android, checking for cancellation once per clause. While it runs the
  dialog shows `generating ...` and Generate is disabled; Cancel (or a click outside) stops it and
  closes the dialog. A failure (incl. out of memory) is logged as an error line and closes the
  dialog. Known limit: no size cap, so a huge but finite instance makes the editor slow.
- Exactly k of n, k > n: only the empty clause (`p cnf n 1`). k = 0: the (k-1)-family is empty.
- Ramsey edge variable numbering: edges {i, j}, i < j, row by row from 1.
- Options dialog: title `<SOLVER> options`; per option the name (bold, monospace) with a checkbox
  (BOOL) or a text field (INT / DOUBLE) next to it, below it the upstream help text and
  `(default: X)`. Buttons `Reset to defaults` and `Close`; edits apply at once (no OK / Cancel).
  A field that is not a number is marked red; Solve then logs
  `error: <SOLVER> option '<name>': '<text>' is not a number` and does not start. Range and
  integrality are left to ksat (its error is logged as the run's error line).
- "Changed" = differs from the upstream default by value: an edit back to the default value is not
  passed. Values are sent as Int when the text is an Int, else as Double.
- Worker protocol: `solve <SOLVER> <MODE> name=value ...` + newline + DIMACS;
  `generate <EXAMPLE> <values...>` -> `generated` + newline + DIMACS, or `failed <message>`.
- The "XOR demo" link is gone, so the web/JVM/Android `xorDemoLink` platform value is gone too;
  README, `scripts/README.md` and `deployPages.sh` no longer mention `xor-demo/`.

## Revision 2 (Manfred, 2026-10-30): About

- Large example parameters without a cap or warning: fine as is.
- "ich hätt aber auch gern noch nen link auf das repo ksat bzw ksat-extra, vlt ähnlich wie das
  info menü wie bei ktoy anzeigen; im wesentlichen verweise auf ksat-extra, weil der code halt dort
  liegt mit den demos bzw der website, und ksat eigentlich das interface ist mit solvern (musst
  hier aber keine weiteren repos linken, nur die beiden)".
- Claude: an "About" button in the header opens a dialog like ktoy's About: commit (with
  "(modified)" when dirty), commit date, build date (no version, as in ktoy/PoCoView), one line on
  what the playground is, then the links: ksat-extra (https://github.com/manfredscheucher/ksat-extra,
  the playground, demos and website) first, ksat (https://github.com/manfredscheucher/ksat,
  the interface with the solvers) second; license line as in ktoy (MIT, link to LICENSE; DejaVu Sans
  Mono font note). No other repos.

Made while building (Claude):

- The About button is an `OutlinedButton` next to the title; the dialog is titled
  "About ksat playground". The one line: "Solve DIMACS CNF formulas with the ksat SAT solvers."
- Each repo link is followed by its role as plain text: "ksat-extra on GitHub (playground, demos,
  website)", "ksat on GitHub (the interface with the solvers)".
- `generateBuildInfo` is PoCoView's task, with one change: ksat-extra is a submodule, so its `.git`
  is a file (`gitdir: ...`); the task resolves it to the real git dir and runs git in the
  ksat-extra root (new `workDir` property). The commit shown is ksat-extra's.
- ktoy swallows a failing link (no browser); here the failure is written to the output as an
  `error:` line instead, so it is not silent.

## Revision 3 (Manfred, 2026-10-30): new example while a run is going

- "wenn ma example ändern möchte, aber berechnung noch läuft, sollte dialog aufgehen dass grad noch
  berechnung läuft - diese berechnung abbrechen um neues zu laden? weil beim laden eines neuen
  beispiels sollte output cleared sein."
- Claude: Generate while a run is going opens "A computation is still running. Stop it and load the
  new example?" with "Stop and load" (stops the run, then generates) and "Cancel" (back to the
  Examples dialog). A generated example always clears the output. Load file is unchanged (not asked).

## Revision 4 (Manfred, 2026-10-30): title, about text, repo renamed

- Main repo renamed on GitHub: https://github.com/manfredscheucher/ksat (was sat-solvers-kotlin); all
  links updated.
- Title (option B of Claude's/reviewer's proposals): header stays "ksat playground"; on the web only
  a subtitle "SAT solvers ported to Kotlin, running in your browser" (the app also runs on JVM and
  Android, where "in your browser" would be wrong). Browser tab: "ksat playground: SAT solvers in
  your browser".
- About text (Manfred: "Kotlin Multiplatform ports of state-of-the-art SAT solvers (list). Runs on
  JVM, Android, iOS, ...", short): "Kotlin Multiplatform ports of state-of-the-art SAT solvers
  (MiniSat, CaDiCaL, kissat, MicroSAT). Runs on JVM, Android, iOS, native and in the browser." It
  replaces the About dialog's line "Solve DIMACS CNF formulas with the ksat SAT solvers." and is
  also the GitHub About text for the ksat repo.
- Subtitle moved into the top row (Manfred: "subtitle in die top zeile"): title, subtitle, About
  button; the subtitle wraps on narrow screens.
