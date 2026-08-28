# Pull request draft for github.com/dynawo/dynawo

Branch (per CONTRIBUTING: NUMBEROFISSUE_name, fill in after creating the
issue): `<ISSUE#>_electronicload_clamp_connectedshare`

Title: Clamp ElectronicLoad connectedShare to [0,1] (fixes #<ISSUE#>)

---

**Disclosure: written entirely by an AI (Anthropic's Claude), no human
review — see #<ISSUE#>.**

Fixes #<ISSUE#>: `connectedShare` was exported at 2.498 at a fault-clearing
voltage jump, because the previously selected branch of the if-equation is
evaluated at the post-jump voltage during the algebraic restoration, where
it is unbounded.

Five coupled changes: the three non-constant expressions clamped to
[0,1]; the disconnected-state `UMinPu` AND its `start` attribute floored
at the documented `Ud2Pu` bound (fixes a sustained negative
connectedShare on both below-band entry paths — reconnection, and a load
initialized at depressed voltage; the floors alone would enlarge the
excursion, so the parts ship together); and an assert making the
`0 <= recoveringShare <= 1` contract explicit (the clamps are only inert
in-guard under it). Behavior changes in these regimes, each one where
stock violates the model's own contracts: the jump-instant excursion
sample (capped); the two below-band-UMinPu regimes — reconnection and
depressed-voltage initialization — where a sustained negative share
becomes `recoveringShare` (note the consequence: a clean breaker cycle at
healthy voltage now permanently sheds `1 - recoveringShare`, since
`UMinPu` never rises; whether it should track the node voltage while
tripped is the design question deferred below); and parameterizations
with `recoveringShare` outside [0,1], which now fail the assert instead
of running. Elsewhere, on the
issue's MRE and variants (fault depth, recoveringShare 0/0.7/1, double
dip, SolverIDA and SolverSIM), curves were unchanged in our runs, and the
generated code's event/mode structure is identical for this shape (min/max
compile to value selection, no new zero-crossings).
