# Library-wide sweep for the guard-only-bounded pattern

**Produced entirely by AI (Anthropic's Claude) with no human review** — a
multi-agent sweep of all 846 Modelica files (~50k lines) in the Dynawo
v1.7.0 library (`Electrical/` + `NonElectrical/`) for the ElectronicLoad
pattern: a physically bounded quantity computed piecewise, where the bound
is enforced only by if-guard branch selection, which Dynawo's mode-frozen
algebraic restoration bypasses at discontinuities. 28 raw candidates; each
distinct candidate was checked by two adversarial verifier agents (one
tasked to refute, one to trace consequences); several verifiers built and
ran their own MREs on the stock install. Raw structured results, including
full per-finding reasoning, are in [`sweep-results.json`](sweep-results.json).

## Confirmed instances (beyond ElectronicLoad)

**1. HVDC converter reactive-power limits — the whole family.**
`HvdcPQProp`, `HvdcPQPropDangling`, `HvdcPQPropDiagramPQ`,
`HvdcPQPropDanglingDiagramPQ`, `HvdcPTanPhi`, `HvdcPTanPhiDangling`,
`HvdcPTanPhiDiagramPQ`, `HvdcPTanPhiDanglingDiagramPQ`, `HvdcPV`,
`HvdcPVDangling`, `HvdcPVDiagramPQ` (and terminal-2 mirrors) all implement
their reactive capability limit as
`if QRaw >= QMax then QMax elseif QRaw <= QMin then QMin else QRaw` — an
unclamped pass-through whose only bound is the guard. `QInjPu` feeds
`s = V·conj(i)` directly: a stale sample sets the terminal current inside
the network solve. Reproduced on stock v1.7.0 by verifier-built MREs:

| Model | Trigger | Reproduced excursion |
|---|---|---|
| HvdcPQProp (QInj1) | modeU1 flip | 300% of Q1MaxPu, network solved on it |
| HvdcPQProp (QInj2) | node fault via VRRemote NQ feedthrough | 199% of Q2MaxPu |
| HvdcPQPropDiagramPQ | modeU event | 200% of diagram limit; IDA **aborts** at NQ1=5 |
| HvdcPTanPhiDangling | converter reconnection | 15x Q1MinPu |
| HvdcPTanPhiDiagramPQ | trip + reclose | 15x / 33x the diagram limits |
| HvdcPV | setpoint step, SolverSIM | 750% of Q1MaxPu for a full step |
| HvdcPVDangling | setpoint step, SolverSIM | 667% of Q1MaxPu |

Corroboration that this is oversight, not design: the *same models* clamp
active power the immune way (`P1Pu = max(min(PMaxPu, P1RefPu), -PMaxPu)`,
BaseHvdcP.mo:47), and the sibling `GeneratorPQProp.mo` writes
`min(max(QGenRawPu, QMinPu), QMaxPu)` in the identical slot.

**Trigger caveat (both verifier camps were right):** the excursion needs
the raw signal to *jump* in one discrete instant — a mode flip,
switch-off/reconnection, or fault feeding through an unfiltered remote
voltage regulator (VRRemote's proportional `NQ`). A plain network fault
does not trigger the variants whose `QRaw` is setpoint-only, and a smooth
setpoint crossing is root-located by SolverIDA to ~1e-9 (a
verifier MRE measured exactly this, max exceedance ≈1e-9, on
`HvdcPTanPhi`). Under SolverSIM even a plain step produces a full
out-of-bound solver step.

**2. `SignalN/BaseClasses/BaseGenerator.mo` — `PGenPu` limiter (DynaFlow
workhorse).** Same if-tree on `PGenRawPu = -PRefPu + Alpha·N` vs
PMaxPu/PMinPu. Reproduced with stock parameters: at a generator trip the
restoration exports `PGenPu` at **151% of PMaxPu** (the network-wide
SignalN signal jumps), and at a load-shed event a stock generator absorbs
0.353 pu against `PMinPu = 0`. Feeds `SGenPu = -V·conj(i)` directly. Note
the sibling `OmegaRef/.../BaseGeneratorSimplifiedPFBehavior.mo:57` writes
the same limiter selecting on a *discrete* status variable — the
freeze-immune idiom — which BaseGenerator does not use.

**3. `RectifierRegulationCharacteristic.mo` — a different manifestation:
hard abort.** The exciter FEX characteristic's middle branch is
`y = sqrt(UHigh - u^2)`, valid only under its guard `u < sqrt(UHigh)`.
When the exciter input jumps (u = Kc·IrPu/vE, algebraic in terminal
voltage/current), the frozen branch evaluates `sqrt` of a negative number.
This does not produce an excursion — omcDynawo's generated domain guard
**kills the simulation** ("Model error: Argument of sqrt(...) was
-0.249975, should be >= 0"; reproduced end-to-end on stock v1.7.0).
Affects the ST4B/ST6B/ST9C/AC7C/AC8C exciter models that instantiate the
block. A magnitude-focused verifier correctly noted the *excursion* path
is benign (the 1/vE blow-up cancels in consumers); the crash is the bug.

## Refuted candidates — and the immunity patterns they establish

Nine candidate verdicts were refuted; the refutation reasons map out which
library idioms are already safe (full reasoning in the JSON):

- **States are immune.** Branches that assign `der(x)` (anti-windup
  conditional integration: `LoadAlphaBetaRestorativeReset`,
  `IntegratorVariableLimits`): the restoration holds differential states
  fixed and re-solves only algebraics, so a stale rate changes nothing at
  the event instant.
- **`smooth(0, ...)` is immune — and is the library's own vaccine.** The
  `VariableLimiter` refutation compiled the equation both ways: with
  `smooth(0, if ...)` omcDynawo emits **zero** zero-crossings and zero
  stored relations (nothing to freeze); without it, two RELATIONHYSTERESIS
  relations appear. Inline `min/max` clamps compile branchless the same
  way — this is why the clamp fix works and what a library-wide guideline
  could standardize on.
- **Setpoint-only guards + SolverIDA root-finding** produce only ~1e-9
  bracketing overshoot on smooth crossings (not the bug), though the same
  models still fail under discrete-jump triggers (see caveat above).
- **Leaf variables** whose out-of-guard value feeds only a clamped
  integrator input or logs (`OELNordic`) cannot perturb the network solve.

## Corrections from independent review

A second, independent AI review of this repository (running its own
18-agent sweep and A/B measurements) corrected this sweep in four ways,
each verified here afterwards:

1. **Missed family: SVarC PVProp** (`SVarCPVProp`,
   `SVarCPVPropModeHandling`, `SVarCPVPropRemote`,
   `SVarCPVPropRemoteModeHandling`). The susceptance limit is the same
   unclamped if-tree, `BVarRawPu` is algebraic in the bus voltage, and a
   **plain bus fault** triggers it — reproduced here: stock exports
   `BVarPu = 7.94` against `BMaxPu = 0.5` at fault onset (network solved
   with 3.43 pu reactive injection) and the run then dies with "IDA fails
   to solve the equations". The non-Prop siblings use the immune
   discrete-status idiom. This sweep's finder read those files and
   reported nothing — a plain miss.
2. **The "clamp is inert in-guard" claim was conditional.** Stock
   ElectronicLoad sets `UMinPu = 0` while disconnected; after a
   reconnection the filter freezes it there (0 is not `> Ud2Pu`) and the
   recovery expression yields a sustained `connectedShare = -0.05`
   **in-guard** — a load injecting power (reproduced on the shipped
   binary). The clamp changes this regime (to 0), so it is a disclosed
   behavior change there, not a no-op; the build now also floors `UMinPu`
   at its documented `Ud2Pu` bound so a reconnected load recovers
   `recoveringShare`.
3. **The FEX fix was too narrow** (radicand only); the linear branches are
   also unbounded out-of-guard and are now bounded to the characteristic's
   [0,1] range.
4. **The rebuild list was short by 6 exciter models** (`Ac7bPss3b` and the
   five `St6c` variants reach the rectifier through `BaseAc7`/`BaseSt6`,
   which the class-name grep missed); the list is now derived from the
   transitive closure and has 83 models.

Round 2 of the same review added, all re-verified here:

5. **The "non-Prop siblings are immune" note above was wrong.** `SVarCPV`
   and its variants carry the class in a structurally worse form: in
   `Standard` mode the equation is `UPu = URefPu` with the susceptance an
   implicit free unknown — nothing to clamp. Reproduced: a mild fault
   leaves the bus **pinned at its setpoint through the fault** with
   `BVarPu = 0.613 > BMaxPu = 0.5` solved into the network; a severe fault
   kills the restoration outright ("KINSOL fails to solve the problem").
   **Not fixed by this build** (needs a structural upstream change); the
   suite asserts the defect is still present so it is never silently
   claimed fixed.
6. **`recoveringShare > 1` is legal (no assert) and makes the clamp
   non-inert in-guard.** The patched model now asserts
   `0 <= recoveringShare <= 1`, making the inertness contract explicit.
7. **The `UMinPu` floor has disclosed consequences and is coupled to the
   clamp.** A clean breaker cycle at healthy voltage now permanently sheds
   `1 - recoveringShare` of the load (`UMinPu` never rises — whether it
   should track the node voltage while tripped is an open modelling
   question for upstream), and the floor *alone* would enlarge the
   clearing excursion (1.749 for the default band) — the floor and the
   clamps must ship together.

Round 3 of the same review added, re-verified here:

8. **A third entry path into the below-band regime: initialization.** The
   `UMinPu` `start` attribute is the unfloored `|u0Pu|`; a load
   initialized at depressed voltage keeps `UMinPu` below the band forever
   (the filter freezes, it does not floor). Reproduced with a consistent
   0.2 pu init that steps to healthy voltage: stock settles at
   `connectedShare = -0.75` **in-guard**, sustained to end of run; a
   severe parameterization kills initialization in KINSOL. Fixed by
   flooring the start value (`max(|u0Pu|, Ud2Pu)`) in all three fix
   definitions; identity for any healthy initialization. The suite gained
   this case plus hardening from the same review round: trigger-armed
   assertions (each excursion case proves its stress actually occurred),
   a corrected FEX assertion column, mandatory example snapshots, a
   provenance header, and committed excursion artifacts.

## Status and caveats

- Everything here is AI-generated and AI-verified; no human has reviewed
  any of it. Verifier agents disagreed on mirror variables of the same
  models in three cases — the disagreements trace to *trigger reachability*
  (which events make the guard signal jump), not to the mechanism, and are
  reported as found.
- The verifier MREs were built ad hoc during the sweep and are not
  committed; each finding needs a curated MRE (like `mre/` for
  ElectronicLoad) before being reported upstream.
- The scope was the shipped v1.7.0 `ddb/Dynawo` library; upstream master
  was not re-swept (the ElectronicLoad instance is unchanged there).
