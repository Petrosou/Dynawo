# Issue draft for github.com/dynawo/dynawo

Title: ElectronicLoad exports connectedShare outside [0,1] at fault clearing

Suggested label: bug

Attach: ElectronicLoad_MRE.zip (case.jobs / case.dyd / case.par / case.crv)

---

**Disclosure: this issue, the proposed fix, and their verification were
produced entirely by an AI (Anthropic's Claude), with no human review.
Please treat both with corresponding caution.**

At a fault clearing, `ElectronicLoad`'s `connectedShare` (defined on [0,1])
is exported outside its range. Running the attached case on v1.7.0
(`dynawo.sh jobs case.jobs`: infinite bus, one line, one ElectronicLoad with
Ud1Pu=0.7 / Ud2Pu=0.5, node fault t=1.0–1.1 s) gives three samples at
t=1.1 in curves.csv:

```
t=1.100000  U=0.6361  connectedShare=0.6804
t=1.100000  U=0.9996  connectedShare=2.4981   <- = (0.9996 - 0.5)/0.2
t=1.100000  U=0.9999  connectedShare=0.9042
```

The middle sample is the pre-clearing branch of the if-equation evaluated
at the post-jump voltage during the algebraic restoration, where it is
unclamped — the network is genuinely solved with the load at 250% of PRefPu
at that point (the exported bus voltage is consistently lower in that
sample). Reproduces with SolverIDA and SolverSIM, and once per mid-band
clearing in multi-event runs.

A second defect in the same model, reachable without any voltage jump:
`UMinPu` is set to 0 while disconnected and the filter freezes it there on
reconnection (0 is not > Ud2Pu), so the recovery expression yields a
sustained `connectedShare = -0.05` **in-guard** — a load injecting power
(reproduced on the shipped binary).

Proposed fix (PR to follow), three coupled parts: clamp the three
non-constant `connectedShare` expressions to [0,1]; floor the
disconnected-state `UMinPu` at its documented `Ud2Pu` bound (the floor
alone would enlarge the excursion, so it must ship with the clamps); and
assert `0 <= recoveringShare <= 1`, without which the clamp is not inert
in-guard. Under that assertion and away from the reconnection regime, each
expression is within [0,1] under its own guard, so only out-of-guard
evaluations change: in our runs, curves were byte-identical before the
event and at the settled state, with the excursion sample capped; the
generated model's event/mode structure is unchanged for this shape. In the
reconnection regime the fix deliberately changes behavior (recoveringShare
instead of a negative share); how a tripped load's `UMinPu` should track
the node voltage is a design question we defer to you.

---

Note: a broader, independently AI-verified filing text covering the
whole model family (HVDC, SVarC Prop and non-Prop, SignalN, exciter FEX)
exists outside this repository and supersedes these drafts for filing;
these remain the ElectronicLoad-scoped originals, corrected.
