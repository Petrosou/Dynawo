# Round-6 decoupling probe: what kills branchless + SolverIDA at a voltage step

A standalone branchless ElectronicLoad with an independent `UMin0Pu` start
parameter (compiled on the fly), run on the step-into-band case shape.
One flaw in the probe as originally proposed had to be fixed first: with
`tFilter = 0.01` and a 0.2 pu pre-step voltage, the UMinPu filter decays
any off-floor start to the Ud2Pu floor within ~100 time constants — the
intended off-kink state never survives to the step. `tFilter = 10`
preserves it (values below measured at the step instant).

All runs: branchless law, SolverIDA, InfiniteBusWithVariations step at
t=1, band [0.5, 0.7], r=0.3, P0=0.001.

| u0 | UMinPu at step | step target | dU | draw at step | outcome |
|---|---|---|---|---|---|
| 0.2 | 0.500 | 0.55 | +0.35 | zero | DIES |
| 0.2 | 0.517 | 0.55 | +0.35 | zero | DIES |
| 0.2 | 0.562 | 0.55 | +0.35 | zero | DIES |
| 0.2 | any | 0.21 | +0.01 | zero | survives |
| 0.51 | 0.51 | 0.55 | +0.04 | >0 | survives |
| 0.51 | 0.50 | 0.55 | +0.04 | >0 | survives |
| 0.51 | 0.50 | 0.57 | +0.06 | >0 | survives |
| 0.51 | 0.50 | 0.60 | +0.09 | >0 | survives |
| 0.51 | 0.50 | 0.69 | +0.18 | >0 | DIES |
| 0.51 | 0.50 | 0.75 | +0.24 | >0 | DIES |
| 0.55 | 0.50 | 1.00 | +0.45 | >0 | DIES |
| 0.72 | 0.50 | 0.69 | -0.03 | >0 | survives |
| 0.9  | 0.50 | 0.55 | -0.35 | >0 | DIES |

Conclusions (each refutes a prior hypothesis):
1. **Kink proximity refuted**: UMinPu up to 0.31 share-units off the
   `max(0, .)` kink dies identically to exactly-at-kink.
2. **Zero-draw-at-step refuted**: nonzero-draw legs die (0.55->1.0,
   0.51->0.69, 0.9->0.55).
3. **Kink-crossing refuted**: 0.51->0.69 crosses no kink of down(U) and
   dies.
4. What remains: **step magnitude** (from u0=0.51 the kill threshold sits
   between dU=+0.09 and +0.18; both directions die at |dU|=0.35) — and an
   **event-source dependence** still unexplained: the NodeFault MRE's
   comparable jumps (1.0->0.636 at application, 0.636->1.0 at clearing)
   SURVIVE on the same branchless build. The "0 residual evaluations"
   signature (IDA dies before its first residual call after reinit) makes
   DYNSolverIDA's reinit/IC path the right place to instrument next —
   black-box probing has reached its limit here.

The installed clamped-ladder build completes every row of this table.
