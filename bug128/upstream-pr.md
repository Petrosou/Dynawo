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

Three coupled changes: the three non-constant expressions clamped to
[0,1]; the disconnected-state `UMinPu` floored at its documented `Ud2Pu`
bound (fixes a sustained negative connectedShare after reconnection; the
floor alone would enlarge the excursion, so the parts ship together); and
an assert making the `0 <= recoveringShare <= 1` contract explicit (the
clamp is only inert in-guard under it). On the issue's MRE and variants
(fault depth, recoveringShare 0/0.7/1, double dip, SolverIDA and
SolverSIM), curves are unchanged except the excursion itself and the
reconnection regime described in the issue; the generated code's
event/mode structure is identical for this shape (min/max compile to value
selection, no new zero-crossings).
