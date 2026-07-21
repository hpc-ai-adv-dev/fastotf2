# `ampere-workflows-new.ipynb` — end-to-end analysis comparison

This notebook measures the **analysis** half of two OTF2 pipelines and adds it to the
already-measured **conversion** half, to compare the *whole* workflow:

| Pipeline | Conversion (already measured elsewhere) | Analysis (measured by this notebook) |
|---|---|---|
| **fastotf2 + arkouda** | `out/run_20260717_203803_save/timings` (`totalTime`) | Ampere, `arkouda` backend, on a Slurm-launched arkouda server |
| **python + pandas** | `../../../fastotf2-bench/out/run_20260717_203326_save/timings` (`seconds`) | Ampere, `pandas` backend, single node |

## Why both backends read the *fastotf2* Parquet (important — read this first)

The Ampere analysis for **both** pipelines loads the **fastotf2-converted Parquet** in
`out/run_20260717_203803_save/pq/`. This is intentional:

- The Parquet **content is the same trace** regardless of which converter produced it, so
  feeding both backends the identical bytes makes the **analysis-time** comparison
  apples-to-apples — only the Ampere backend (`arkouda` vs `pandas`) differs, not the input.
- The Python converter's *output* Parquet is **never** used as analysis input. The Python
  pipeline contributes **only its already-measured conversion time** to the end-to-end total.
- This also avoids **regenerating the very expensive Python Parquet** — the Python conversion
  of the 32 GiB trace alone took ~3.75 h, and its scratch output was deleted by the benchmark
  harness anyway.

So if you see the `pandas` backend reading a path under the *fastotf2* run folder — that is
correct and by design. It is not a bug, and it does not mean we lost the Python Parquet.

## End-to-end formula

```
end_to_end(fastotf2+arkouda) = fastotf2 conversion time (paired nl) + Ampere arkouda analysis time
end_to_end(python+pandas)    = python  conversion time (1 node)     + Ampere pandas  analysis time
```

### Conversion-time pairing

Each arkouda analysis point (at `N` server nodes) is paired with the fastotf2 conversion time
at `nl == N` when that conversion exists, otherwise the **nearest available** `nl`, flagged
`conversion_nl_exact=False` in the results. Rationale: analysis usually needs *fewer* nodes
than conversion, so a low-node analysis pairs with the lowest-node conversion that exists.
With the default matrix, only **`384 GiB @ 16 nodes`** is inexact (pairs with `nl=64`).

The Python conversion is inherently single-node; its measured time pairs with the single-node
pandas analysis on the head-to-head traces (16 & 32 GiB).

## Ampere backends

Ampere (fresh clone in `ampere-repo/`, installed editable into `e4s-cl-setup/.venv`) exposes a
pluggable backend: `ampere.set_backend('arkouda' | 'pandas')`. The **same**
`Ensemble`/`AttributionEngine` code runs on either backend, so the two pipelines share one
analysis code path.

> **Local change to the pandas backend.** Upstream's `PandasBackend` did not implement
> `read_parquet` / `full`, which `Ensemble.from_trace_paths_parquet()` needs. We added both to
> `ampere-repo/src/ampere/_pandas_backend.py`. If you re-clone or update `ampere-repo`,
> re-apply that change (or the pandas side will fail on load).

## Trace / node matrix (defaults, all editable in §2)

- Head-to-head (both pipelines): **16, 32 GiB**.
- Arkouda-only (single-node pandas can't hold them): **128, 384 GiB**.
- `ANALYSIS_NODES = {16:[1,4], 32:[1,8], 128:[16,32], 384:[16,64]}` — arkouda server node
  counts per trace. Head-to-head traces include `1` (to line up with single-node pandas);
  arkouda-only traces start at `16` (one node can't hold ~291 GiB / ~1.5 TiB).
- Topology is always built from the **trace's own node count** (`traced_nodes × ranks/node`
  MPI ranks), **not** the arkouda-server node count — the server node count is only compute.
- Metric `A2rocm_smi:::energy_count:device=6`, strategy `exclusive`, 3 trials/config
  (all trials in one allocation).

## Structure

- **§0** setup (`SYSTEM` switch, secrets via `local_secrets.py`, timestamped `out/run_*` folder)
- **§1** environment (Ampere / arkouda client / container / e4s-cl profile — arkouda side only)
- **§2** design (editable matrix; `SAMPLE_RUN`/`DRY_RUN` both default `True`; writes `plan.json`)
- **§3** collect (arkouda live-driven + pandas single-node batch driver → timing CSVs)
- **§4** combine (join analysis + conversion → `end_to_end_results.csv`)
- **§5** analyse (plotnine graphs; self-contained via `ANALYZE_RUN`)

The analysis logic (topology, metric config, `attribute` call) is ported from the original
`ampere-workflow.ipynb`, which is left **unchanged**.

See `ampere-workflows-new.PLAN.md` for the full design spec and the gap sanity-check.
