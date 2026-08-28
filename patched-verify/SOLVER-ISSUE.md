# SolverIDA event-restart failures on a branchless (noEvent) load model

**Status: complete black-box characterization; upstream filing at the
repository owner's discretion. All findings produced and cross-verified by
two independent AI investigation chains with no human review; every number
below was measured on at least one of two containers, and every
cross-container claim on both.**

Environments: (A) this repository's build — official Dynawo v1.7.0 Linux
distribution, Ubuntu 24.04, SolverIDA order 2 (par set committed with each
case); (B) the second chain's pinned v1.7.0 Apptainer container. "Portable"
below means measured identically on A and B.

## The model under test

`patches/models/ElectronicLoadBranchless.mo` — the WECC-style electronic
load with its `connectedShare` piecewise ladder rewritten as a single
continuous `noEvent` expression (min/max clamps, no branch selection).
Proven algebraically identical to the installed clamped-ladder model on the
invariant domain (`test_branchless_identity.py`: 14.5M float points at one
ulp; 200k exact-rational points, zero mismatches). The compiled branchless
model carries **no** share zero-crossing relations; the ladder carries
four. Motivation for the rewrite and why it is *not* this build's default:
`bug128/SWEEP.md`, rounds 5–7.

## Phenomenon

With the branchless model, SolverIDA dies at a discrete voltage-step event
in scenarios the clamped-ladder model (and stock, and SolverSIM on the same
branchless model) completes. Two distinct death signatures:

1. **Reinit kill** — `DYN Error: IDA fails to solve the equations
   (DYNSolverIDA.cpp:500)`, exit 1, with the closing statistics reporting
   `number of residual evaluations = 0`: IDA dies before its first residual
   call after the event restart.
2. **Timestep grind** — `DYN Error: time step <= 1e-06 s for more than 10
   iterations (DYNSolverIDA.cpp:604)`, exit 2: the restart succeeds and the
   integrator then grinds to the floor.

## Measured structure

- **Event-source discriminator (portable).** An
  `InfiniteBusWithVariations` parameter step of |dU| = 0.36 kills the
  branchless model (reinit), while a `NodeFault` application/clearing of
  the same magnitude on the same build completes. Cases:
  `decoupling-probe/` (IBUS 1.0 -> 0.636 dies) vs `../bug128/mre/`
  (NodeFault 1.0 -> 0.636 -> 1.0 completes).
- **Magnitude threshold (build-local — do not port numbers).** From
  u0 = 0.51, environment A survives dU = +0.09 and dies at +0.18;
  environment B survives +0.04 and dies at +0.09. Both directions die at
  |dU| = 0.35 on A. Gate by trajectory/event class, never by a step-size
  band.
- **Death-mode switch (portable).** The mode boundary tracks the
  (trajectory, `tFilter`) pair, not magnitude or direction: on both
  containers the 0.55 -> 1.0 trajectory grinds at `tFilter = 0.01` and
  reinit-kills at `tFilter = 10`, while every other tested trajectory
  reinit-kills at both filter speeds:

  | 0.55 -> 1.0 | tFilter = 0.01 | tFilter = 10 |
  |---|---|---|
  | environment A | GRIND (cpp:604, exit 2) | REINIT (cpp:500, 0 resid) |
  | environment B | GRIND (cpp:604, exit 2) | REINIT (cpp:500, 0 resid) |

- **Refuted hypotheses** (13-point matrix, `decoupling-probe/README.md`):
  kink proximity of the frozen `UMinPu` state (up to 0.31 share-units off
  the `max(0,·)` kink dies identically); zero load draw at the step
  (nonzero-draw legs die); kink-crossing by the step (an in-band step
  crossing no kink of the share law dies).

## Committed reproductions (each runs in seconds)

- `step-into-band/` — the original counterexample (0.2 -> 0.55): clamped
  completes (share 0.075), branchless reinit-kills. Gated in the suite.
- `decoupling-probe/` — the probe model
  (`ElectronicLoadBranchlessProbe.mo`, independent `UMin0Pu` start) plus
  the full matrix; any row reproduces by editing four par values.
- `artifacts/step-into-band-branchless-ida-fail.log`,
  `artifacts/grind-death-055-to-1-tf001.log` — verbatim death logs, one
  per mode.
- `../bug128/mre/` — the NodeFault control that survives on the same
  branchless build.

## The open question

Why does IDA's post-event restart fail before its first residual
evaluation on a model whose only nonsmoothness is value-level
(`noEvent` min/max kinks, no zero-crossing relations) after an
`InfiniteBusWithVariations` parameter step — while the identical algebraic
law expressed as an event-generating ladder restarts cleanly, a
`NodeFault` jump of the same magnitude restarts cleanly, and SolverSIM
handles every case; and why does stiffening the one filter state
(`tFilter` 10 -> 0.01) convert exactly one trajectory's reinit kill into a
timestep grind? The `0 residual evaluations` signature points at
`DYNSolverIDA`'s reinit/IC path before the first corrector residual;
answering it needs an instrumented source build, which neither
investigating chain has — both deployed defaults complete every case in
this dossier, so for the two deployments the question is academic. For
upstream, a maintainer with an instrumented build could likely answer it
in an afternoon with the cases above.
