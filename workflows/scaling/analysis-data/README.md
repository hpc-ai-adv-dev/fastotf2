# analysis-data — small, git-tracked data to RE-RUN the analysis halves

This folder holds the **minimal, clean, non-sensitive** data needed to re-run the *analysis /
graphing* cells of the scaling notebooks **without** the multi-TB traces/Parquet and without
any account/system-sensitive content. It is safe to commit and to clone onto another machine.

If you are an agent picking this up on another system (e.g. **Frontier**): read this whole file,
then follow "Replicating on a new system" at the bottom. The scheme is designed so each machine
contributes its own results under its own `<system>/` label.

## Layout

```
analysis-data/
  README.md                     # this file
  tools/
    build_converter_merged.py   # builds the converter (B) merged run from TWO raw out/ runs
    build_converter_single.py   # builds the converter (B) run from ONE complete out/ run
  <system>/                     # neutral machine label: "other-ex", "frontier", ...
    ampere/                     # analysis A (ampere-workflows-new.ipynb)
      <run>/end_to_end_results.csv, plan.json, plots/
    converter/                  # analysis B (converter-scaling-new.ipynb)
      run_converter_merged/timings/{conversion_timings,conversion_phases}.csv,
                            trace_sizes.json, plan.json, SOURCES.md
  # (bench C lives in the SEPARATE fastotf2-bench repo under its own analysis-data/)
```

`<system>` is a **neutral** label (never the real cluster name). Today: `other-ex` (its
converter data is the two-run *merge*, see below) and `frontier` (a single complete STRONG
sweep, built with `build_converter_single.py`). Same shape either way — analyses can compare
systems.

## How to re-run each analysis from here

In every case: **restart the kernel, jump to the notebook's §5 analysis, set the run pointer to
the folder here, run the graph cells.** No collection, no traces, no Parquet needed.

- **A — ampere-workflows-new.ipynb (§5):** set
  `ANALYZE_RUN = "<...>/analysis-data/<system>/ampere/<run>"`. §5 reads only
  `end_to_end_results.csv` (fully self-contained; size + everything derived from that one CSV).
- **B — converter-scaling-new.ipynb (§5):** set
  `ANALYZE_RUN = "<...>/analysis-data/<system>/converter/run_converter_merged"`. The §5
  `load_timings()` has an **aggregated-read shim**: when a run's `timings/conversion_timings.csv`
  exists it loads that (+ `conversion_phases.csv`) directly instead of globbing raw per-config
  timings. `df_tasks` is then empty, so the optional **per-task breakdown graph auto-skips**;
  the run-level scaling graphs and the phase-breakdown graph work normally. `trace_sizes.json`
  is read from the run folder so the `du -sb` size step is skipped (no traces present).
- **C — fastotf2-benchmark.ipynb:** in the `fastotf2-bench` repo; set its analysis run pointer to
  that repo's `analysis-data/<system>/<run>` (its `results.csv` is already the combined artifact).

## What is / isn't here (and why)

KEPT (small, needed, non-sensitive):
- Aggregated timing CSVs / results CSV; `plan.json` / `config.json` (design matrix; neutral
  `system` label + filepaths only); `trace_sizes.json` / `parquet_sizes.json` caches (so the
  size-measurement step is skipped); rendered `plots/` PNGs.

DROPPED (huge and/or sensitive and/or unused by analysis):
- `pq/` (multi-TB Parquet), `*.sif` containers, `scratch/`.
- `slurm_logs/`, `arkouda_server_logs/`, `run_logs/` — carry node **hostnames / system details**
  and sbatch scripts with `--account` / `--mail-user` ⇒ **sensitive**. Never upload.
- `tasks_*.csv` per-task detail for B (bulky; only fed the optional per-task graph).
- `manifest.csv`, `*.pid`, `job_times/`, `*.fail.log` — not needed to re-graph.

## B (converter) merge — important, non-obvious

The two raw converter runs come from **different notebook versions** and neither is complete:
- `run_20260717_203803_save` (newer): traces {16,32,128,384}, 5 trials — **no small traces**.
- `run_20260714_043638_save` (older): has small traces {2,4,8} (and more), 10 trials.

`tools/build_converter_merged.py` fabricates ONE clean run: small traces {2,4,8} from the OLD run
(**capped to trials 1–5** to match), everything else from the NEW run. Both share the same
`run_/phases_` CSV schema (verified), so the concat is apples-to-apples. See the run's
`SOURCES.md` for the exact trace→source→trials table.

## C (bench) — code-provenance caveat (TODO, tracked)

The bench `_save` run's **python** numbers are from a **serial** python converter that was later
replaced in the repo by a "parallel" version which is **GIL-bound (not actually parallel)**. So
`_save` corresponds to code no longer in the repo. Follow-up: restore the serial implementation
as the canonical python representer, and note in the bench `analysis-data` that `_save` == that
serial version. (Does not block re-graphing.)

## Replicating on a new system (e.g. Frontier)

1. Do the collection runs on that system as usual (they land in each repo's ignored `out/`).
2. **converter (B):** edit the paths + `SYSTEM = "frontier"` at the top of
   `tools/build_converter_merged.py` (or generalize via args) and run it → writes
   `analysis-data/frontier/converter/run_converter_merged/`. If that system's runs aren't split
   across two notebook versions, use `tools/build_converter_single.py` instead — point its
   `SRC_RUN` at the one complete run and set `SYSTEM` → it writes
   `analysis-data/<system>/converter/<run_tag>/` (this is how the existing `frontier/converter/`
   data was built from a single STRONG sweep).
3. **ampere (A):** run the notebook's §4 combine **while the conversion runs still exist on that
   system** to bake `end_to_end_results.csv`, then copy it (+ `plan.json`, `plots/`) to
   `analysis-data/frontier/ampere/<run>/`.
4. **bench (C):** copy `results.csv` (+ `config.json`, `trace_sizes.json`, `plots/`) to that
   repo's `analysis-data/frontier/<run>/`.
5. Confirm `.gitignore` keeps `analysis-data/` trackable while ignoring anything bulky/sensitive
   inside it; `git status` + check staged size before committing.
6. Re-graph by setting each notebook's §5 run pointer to the new `analysis-data/frontier/...`
   folder (see "How to re-run" above).
