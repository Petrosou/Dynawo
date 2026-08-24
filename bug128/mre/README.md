# ElectronicLoad connectedShare leaves [0,1] at an algebraic voltage jump

Standalone, self-contained Dynawo v1.7.0 case: one InfiniteBus, one Line
(R=0.001, X=0.01 pu), one BusWithInit, ONE ElectronicLoad (P0=0.05, Q0=0.01 pu; Ud1Pu=0.7,
Ud2Pu=0.5, recoveringShare=0.7, tFilter=0.01), one NodeFault (RPu=0.009, t=1.0..1.1 s), SolverIDA,
3 s. Four files: case.jobs / case.dyd / case.par / case.crv.

Run (any Dynawo v1.7.0 install; we used the pinned distribution in an Apptainer container):

    dynawo.sh jobs case.jobs

## Observed (curves-excerpt.csv here = Dynawo's own CSV export, t in [0.99, 1.15])

The fault sags U_B1 to 0.6361 pu (mid-band); the UMinPu filter tracks down to 0.6361 by t~1.07.
At the clearing instant t=1.100000, three consecutive exported samples:

    t=1.100000  share=0.6804  U=0.6361   (pre-clearing, falling branch)
    t=1.100000  share=2.4981  U=0.9996   <-- STALE BRANCH x NEW VOLTAGE, unclamped
    t=1.100000  share=0.9042  U=0.9999   (post-mode-processing, correct recovery value)

The excursion's arithmetic is exact: the frozen falling-branch expression
(UPu - Ud2Pu)/(Ud1Pu - Ud2Pu) = (0.9996 - 0.5)/0.2 = 2.498. A "share of the load that is
currently connected" of 249.8% is exported by the tool itself. Heavier-load variant (P0=0.45):
same instant, share=2.4755 = (0.9951-0.5)/0.2 — the arithmetic tracks the post-jump voltage
exactly, confirming the mechanism.

## Mechanism (from ddb/Dynawo/Electrical/Loads/ElectronicLoad.mo, v1.7.0)

Each piecewise share expression is bounded ONLY under its guard. During the mode-frozen
algebraic evaluation at a discontinuity, the previous branch is evaluated with the post-jump
voltage — outside its guard — and is unclamped there. Both mid-band expressions can exceed
[0,1] this way (falling: (UPu-Ud2Pu)/(Ud1Pu-Ud2Pu) with UPu > Ud1Pu; recovery:
((UMinPu-Ud2Pu) + r*(UPu-UMinPu))/(Ud1Pu-Ud2Pu) likewise).

## Suggested fix (one line per expression)

Clamp the piecewise share expressions (min/max to [0,1]) so out-of-guard evaluations stay
bounded; equilibria and in-guard behavior are unchanged.
