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
in-guard under it). Behavior changes in exactly three regimes, each one
where stock violates the model's own [0,1] invariant: the jump-instant
excursion sample (capped), and the two below-band-UMinPu regimes (a
sustained negative share becomes `recoveringShare`). Elsewhere, on the
issue's MRE and variants (fault depth, recoveringShare 0/0.7/1, double
dip, SolverIDA and SolverSIM), curves were unchanged in our runs, and the
generated code's event/mode structure is identical for this shape (min/max
compile to value selection, no new zero-crossings).
