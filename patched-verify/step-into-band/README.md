# Voltage step landing inside the share band (branchless-law counterexample)

Consistent 0.2 pu initialization, then the infinite bus steps to 0.55 —
inside the ElectronicLoad disconnection band — at t=1. On the installed
(clamped-ladder) build with SolverIDA this completes with
connectedShare = 0.075 (= ((Ud2-Ud2) + r*(0.55-Ud2))/(Ud1-Ud2), r=0.3,
UMinPu floored at Ud2Pu).

The proposed branchless share law (../..​/patches/models/
ElectronicLoadBranchless.mo) FAILS this case: "IDA fails to solve the
equations" at the step, dying at reinitialization (0 residual
evaluations). Localization: SolverSIM completes it on the branchless
build (0.075), a tiny step not entering the band (0.2 -> 0.21) completes
on IDA, and the clamped build completes it on IDA — so the failure is
specifically branchless + SolverIDA + a step landing in the band, a
standard FRT test pattern. This is why the branchless law (which fixes a
fault-application restoration kill at high electronic share that the
clamped ladder cannot) is NOT the installed default: neither law
solver-dominates the other. See SWEEP.md round 5.
