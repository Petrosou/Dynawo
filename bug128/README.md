# BUG-128: ElectronicLoad connectedShare leaves [0,1] at an algebraic voltage jump

Confirmed bug in the Dynawo Modelica model library, reproduced independently
on a clean Dynawo v1.7.0 install (`1.7.0 (rev:HEAD-6211f2e)`) and still
present in upstream `dynawo/dynawo` master (checked at commit `0443c55`,
2026-07-28).

## The bug

`Dynawo.Electrical.Loads.ElectronicLoad` computes `connectedShare` — by
definition a fraction in [0,1] — from piecewise expressions that are each
bounded only by their if-guard. Dynawo's event handling evaluates the
previously selected branch with post-discontinuity values during the
mode-frozen algebraic restoration, i.e. outside the branch's guard, where
the expression is unclamped.

Running `mre/` (one InfiniteBus, one line, one ElectronicLoad with
Ud1Pu=0.7 / Ud2Pu=0.5, node fault at t=1.0..1.1 s) on stock v1.7.0 exports
three consecutive samples at the clearing instant t=1.100000:

| t | U (pu) | connectedShare | PPu (pu) |
|---|---|---|---|
| 1.100000 | 0.636088 | 0.680440 | 0.034022 |
| 1.100000 | **0.999624** | **2.498122** | **0.124906** |
| 1.100000 | 0.999864 | 0.904154 | 0.045208 |

The middle sample is the stale falling-branch expression evaluated at the
post-jump voltage: (0.999624 − 0.5)/0.2 = 2.498122, exactly. It is not an
export artifact: the bus voltage in that sample differs from the final one
by precisely the extra line drop of the load momentarily drawing 250% of
its reference power — the solver genuinely closes the frozen-mode algebraic
system on that point before mode processing corrects it. With many such
loads mid-band at a fault clearing, the restoration must close across many
simultaneous kinks with physically absurd iterates (reported to kill the
KINSOL algebraic restoration on multi-load cases).

## The fix

Clamp the three non-constant piecewise expressions to [0,1] with
`min(1, max(0, ...))` — see
[`../patches/ElectronicLoad-clamp-connectedShare.patch`](../patches/ElectronicLoad-clamp-connectedShare.patch)
(generated against upstream master, applies cleanly at `0443c55`). Each
expression already stays within [0,1] whenever its guard holds (given
0 ≤ recoveringShare ≤ 1), so the clamp only affects out-of-guard
evaluations: equilibria and in-guard behavior are untouched.

## Verification

```bash
./verify_bug128_fix.sh          # or: ./verify_bug128_fix.sh /path/to/dynawo
```

`control/` compiles a verbatim copy of the v1.7.0 model from source
(`ElectronicLoadStock.mo`) via a `modelicaModel`/`unitDynamicModel`
declaration; `fix/` compiles the clamped variant (`ElectronicLoadClamped.mo`).
Same case, same toolchain — any difference is attributable to the clamp.
Result on v1.7.0 (Ubuntu 24.04, SolverIDA):

- control reproduces the bug **bit-for-bit** with the precompiled library
  model: one exported sample with `connectedShare = 2.498121955786`;
- fix: zero samples outside [0,1]; the restoration sample is clamped at
  1.0 (nominal power) and mode processing then lands on the same recovery
  value 0.904154000855;
- pre-event trajectories and the final state of the two runs are
  **byte-identical** — the clamp changed nothing but the excursion.

The heavier-load variant (P0=0.45: stock share = 2.482881 = (0.996576−0.5)/0.2)
is likewise clean with the clamp.

Directory layout:

- `mre/` — the original minimal reproducible example (stock v1.7.0
  precompiled model; run with `dynawo.sh jobs mre/case.jobs` to see the bug
  as reported);
- `control/` — same case, stock model compiled from source (reproduces);
- `fix/` — same case, clamped model compiled from source (clean);
- `verify_bug128_fix.sh` — runs both and asserts all of the above.

Note: the two `.mo` files here are standalone copies (fully qualified class
references, `Complex(0, 0)` constructor) because a model outside the
`Dynawo` package cannot rely on the package's internal imports; the
equations are otherwise verbatim. On-the-fly Modelica compilation on
Ubuntu 24.04 needs the bundled Boost header fix applied by
`../install_dynawo_1.7.0.sh`.
