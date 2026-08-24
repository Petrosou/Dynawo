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

This clamps the three non-constant expressions to [0,1]. Each is already
within [0,1] under its own guard, so behavior only changes at the
out-of-guard evaluations: on the issue's MRE and variants (fault depth,
recoveringShare 0/0.7/1, double dip, SolverIDA and SolverSIM), curves are
unchanged except the excursion itself, and the generated code's
event/mode structure is identical (min/max compile to value selection, no
new zero-crossings).
