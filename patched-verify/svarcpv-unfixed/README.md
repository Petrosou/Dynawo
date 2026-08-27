# KNOWN LIMITATION — NOT fixed by this build

The non-Prop SVarC family (`SVarCPV` and its Remote/ModeHandling variants)
carries the same defect class in a structurally worse form: in `Standard`
mode the model's equation is `UPu = URefPu` with the susceptance an
implicit free unknown — there is no expression to clamp. During the
mode-frozen restoration at a fault, the solver holds the faulted bus at
its setpoint by driving `BVarPu` past its limits (this case: 0.613 vs
BMaxPu = 0.5, solved into the network) before the `when`-clause can
switch modes; with a severe fault the restoration itself fails
("KINSOL fails to solve the problem") and the run dies.

A `min`/`max` clamp cannot express the fix; it needs a structural change
(how PV-mode limit switching interacts with the restoration), which is an
upstream design decision. Found by independent review; the verification
suite asserts this defect is STILL PRESENT so the build never silently
claims it fixed. Workaround for personal use: prefer the patched
`SVarCPVProp` (droop) variants where a study allows it.
