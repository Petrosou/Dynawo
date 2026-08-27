# Dynawo 1.7.0 setup

Scripts to install and verify [Dynawo](https://dynawo.github.io) v1.7.0 —
RTE's hybrid C++/Modelica open-source time-domain simulation tool for power
systems — using the official pre-built Linux release.

## Install

```bash
./install_dynawo_1.7.0.sh            # installs to ~/dynawo-install/dynawo
# or: ./install_dynawo_1.7.0.sh /path/to/install/dir
```

The script:

1. installs system prerequisites via apt (`curl`, `unzip`, `g++`, `make` —
   the compiler is needed when a job compiles Modelica models on the fly with
   the bundled OpenModelica toolchain);
2. downloads `Dynawo_Linux_v1.7.0.zip` (~157 MB) from the official GitHub
   release;
3. unpacks it and runs `./dynawo.sh version` as a smoke test.

## Verify

```bash
./verify_dynawo.sh                   # or: ./verify_dynawo.sh /path/to/dynawo
```

Runs one bundled IEEE14 example from each of Dynawo's three simulation
families and checks that curves/timeline outputs are produced:

| Family | Case | Result |
|---|---|---|
| DynaSwing (transient stability) | IEEE14 bus fault | succeeded — 849 curve rows |
| DynaFlow (steady-state calculation) | IEEE14 line disconnection | succeeded — 104 curve rows |
| DynaWaltz (long-term voltage stability) | IEEE14 generator disconnections | succeeded — 544 curve rows, 164 timeline events |

Verified on Ubuntu 24.04 (x86_64) with `dynawo.sh version` reporting
`1.7.0 (rev:HEAD-6211f2e)`.

## BUG-128: ElectronicLoad connectedShare fix

[`bug128/`](bug128/) contains a confirmed bug in the library model
`Dynawo.Electrical.Loads.ElectronicLoad` (its `connectedShare`, a fraction
in [0,1] by definition, is exported as 2.498 at a fault-clearing voltage
jump), a candidate one-line-per-expression clamp fix
([`patches/ElectronicLoad-clamp-connectedShare.patch`](patches/ElectronicLoad-clamp-connectedShare.patch)),
and an A/B harness (`bug128/verify_bug128_fix.sh`) proving the fix removes
the excursion without changing any in-guard behavior. See
[`bug128/README.md`](bug128/README.md).

## Patched personal build

```bash
./build_patched_dynawo.sh            # installs to ~/dynawo-install, patches, rebuilds, verifies (~1-2 h)
```

Builds a **modified** Dynawo 1.7.0 with the clamp fixes from
[`patches/`](patches/) applied (ElectronicLoad, the HVDC reactive-power
limits, the SVarC PVProp susceptance limits, the SignalN generator
active-power limit, the exciter rectifier characteristic) and the 83
affected precompiled models rebuilt from the patched sources. All patches
were authored and verified by AI with no human review; results from this
build must not be attributed to stock Dynawo. Stock models are kept beside
the replacements (`*.so.stock`, `*.mo.stock`) and
[`patched-verify/verify_patched_dynawo.sh`](patched-verify/verify_patched_dynawo.sh)
proves, on the built install (every check gates the exit status): each
known excursion present with the stock model and absent with the patched
one, the stock SVarC IDA abort and exciter FEX abort gone, stock/patched
byte-identical before each case's first event, and the three IEEE14
examples byte-identical to stock.

Some patches are disclosed behavior changes, not pure clamps: after a
switch-off/reconnection, stock ElectronicLoad holds a **negative**
connected share in-guard (a load injecting power; `UMinPu` restarts at 0,
below `Ud2Pu`) — the patched model floors `UMinPu` at its documented
`Ud2Pu` bound and recovers `recoveringShare` instead (consequence: a clean
breaker cycle permanently sheds `1 - recoveringShare`; the floor and the
clamps are coupled and ship together), and it asserts
`0 <= recoveringShare <= 1`, without which the clamps are not inert
in-guard. **Known limitation, deliberately not fixed:** the non-Prop
`SVarCPV` family carries the same defect class with nothing to clamp
(`UPu = URefPu` with the susceptance implicit) — see
[`patched-verify/svarcpv-unfixed/`](patched-verify/svarcpv-unfixed/); the
suite asserts it is still present. Two rounds of independent AI review of
this repository found the reconnect defect, the missed SVarC families, the
`recoveringShare` contract gap, and gaps in the earlier verification
suite; see
[`bug128/SWEEP.md`](bug128/SWEEP.md#corrections-from-independent-review).

## Running your own simulations

```bash
cd ~/dynawo-install/dynawo
./dynawo.sh jobs <path/to/your.jobs>
./dynawo.sh jobs-with-curves <path/to/your.jobs>   # also renders curves in a browser
./dynawo.sh jobs-help                              # launcher options
```

Outputs (curves CSV, event timeline, logs, final state) land in the
`outputs/` directory next to the `.jobs` file.
