# Patches

- **`apply_model_patches.py`** — the authoritative, applicable form of all
  fixes, targeting the **v1.7.0** library as shipped in `ddb/Dynawo`
  (idempotent, asserts every expected match).
- **`ElectronicLoad-clamp-connectedShare.patch`** — a git patch of the
  original ElectronicLoad clamp only, generated against **upstream master**
  (`0443c55`) for submission there; it does **not** apply to the v1.7.0
  tree (master renamed `UPu.value` to `UPu`). For v1.7.0 use the Python
  script.
- **`rebuilt-models.txt`** — the 83 preassembled models whose precompiled
  `.so` embed at least one patched class (derived from the v1.7.0
  descriptors via the transitive closure over the voltage-regulator
  classes), consumed by `rebuild_patched_models.sh`.
