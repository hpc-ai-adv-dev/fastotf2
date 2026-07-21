#!/usr/bin/env python3
"""Build B's SYNTHETIC merged converter run for analysis-data/.

WHY: neither converter run is complete on its own. The two runs come from different notebook
versions:
  * NEW  run_20260717_203803_save : traces {16,32,128,384}, 5 trials/config. NO small traces.
  * OLD  run_20260714_043638_save : has the small traces {2,4,8} (and others), 10 trials/config.

So we fabricate ONE clean run for the analysis half: small traces {2,4,8} come from the OLD run
(capped to trials 1-5 to match), everything else from the NEW run (already 5 trials). Both runs
share the SAME run_/phases_ CSV schema (verified), so the concat is apples-to-apples.

We AGGREGATE the tiny per-trial CSVs into two small tidy CSVs (dropping the bulky per-task
tasks_*.csv, which only feeds one optional breakdown graph):
  * conversion_timings.csv  -- one row per (traced_nodes, nl, trial): run_*.csv columns.
  * conversion_phases.csv   -- one row per (traced_nodes, nl, trial, phase): phases_*.csv columns.

The converter notebook's §5 `load_timings()` has a shim that reads these when present (and then
`df_tasks` is empty, so the per-task graph auto-skips).

Re-runnable on any machine: just point the paths below at that machine's two runs and set the
output system label (e.g. "frontier").
"""
import json
import re
import sys
from pathlib import Path

import pandas as pd

# ---- Configure the merge (edit these when replicating on another system) ----
SCALING_DIR = Path(__file__).resolve().parents[2]          # .../workflows/scaling
NEW_RUN = SCALING_DIR / "out" / "run_20260717_203803_save"  # larger traces, 5 trials
OLD_RUN = SCALING_DIR / "out" / "run_20260714_043638_save"  # source of small traces (10 trials)
SMALL_FROM_OLD = {2, 4, 8}        # traces taken from OLD (missing in NEW)
TRIAL_CAP = 5                     # cap OLD's 10 trials to match NEW's 5
SYSTEM = "other-ex"               # analysis-data/<SYSTEM>/converter/...
OUT = SCALING_DIR / "analysis-data" / SYSTEM / "converter" / "run_converter_merged"

_TAG = re.compile(r"size(\d+)_nl(\d+)_trial(\d+)$")


def _collect(run_dir, keep_size):
    """Return (run_rows, phase_rows) lists for configs whose traced_nodes passes keep_size(t),
    with trial <= TRIAL_CAP. Tags every row with traced_nodes/nl/trial/timestamp/source_run."""
    run_rows, phase_rows = [], []
    tdir = Path(run_dir) / "timings"
    for d in sorted(tdir.iterdir()):
        m = _TAG.match(d.name)
        if not m:
            continue
        t, nl, trial = int(m[1]), int(m[2]), int(m[3])
        if not keep_size(t) or trial > TRIAL_CAP:
            continue
        for run_csv in d.glob("run_*.csv"):
            df = pd.read_csv(run_csv)
            df["traced_nodes"], df["nl"], df["trial"] = t, nl, trial
            df["source_run"] = Path(run_dir).name
            run_rows.append(df)
        for ph_csv in d.glob("phases_*.csv"):
            df = pd.read_csv(ph_csv)
            df["traced_nodes"], df["nl"], df["trial"] = t, nl, trial
            df["source_run"] = Path(run_dir).name
            phase_rows.append(df)
    return run_rows, phase_rows


def main():
    for r in (NEW_RUN, OLD_RUN):
        if not (r / "timings").is_dir():
            sys.exit(f"ERROR: no timings/ under {r}")

    # NEW: everything it has (all its traces are non-small). OLD: only the small traces.
    new_runs, new_ph = _collect(NEW_RUN, keep_size=lambda t: t not in SMALL_FROM_OLD)
    old_runs, old_ph = _collect(OLD_RUN, keep_size=lambda t: t in SMALL_FROM_OLD)

    runs = pd.concat(new_runs + old_runs, ignore_index=True)
    phases = pd.concat(new_ph + old_ph, ignore_index=True)

    # Sanity: no (trace,nl,trial) collisions between the two sources.
    dup = runs.duplicated(subset=["traced_nodes", "nl", "trial"]).sum()
    if dup:
        sys.exit(f"ERROR: {dup} duplicate (trace,nl,trial) rows across sources -- overlap bug")

    OUT.mkdir(parents=True, exist_ok=True)
    # CSVs live under a timings/ subdir so the notebook's resolve_timings_dir() (which returns
    # <run>/timings) works unchanged -- only load_timings() gets an aggregated-read shim.
    tdir_out = OUT / "timings"
    tdir_out.mkdir(parents=True, exist_ok=True)
    _cols = ["traced_nodes", "nl", "trial", "timestamp", "strategy", "numLocales",
             "tracePath", "totalTime", "throughput", "source_run"]
    runs[_cols].sort_values(["traced_nodes", "nl", "trial"]).to_csv(
        tdir_out / "conversion_timings.csv", index=False)
    phases[["traced_nodes", "nl", "trial", "phase", "time", "pctTotal", "source_run"]].to_csv(
        tdir_out / "conversion_phases.csv", index=False)

    # Merged trace-size cache (OLD already has ALL traces incl. 2/4/8). Union to be safe.
    sizes = {}
    for r in (OLD_RUN, NEW_RUN):
        j = r / "trace_sizes.json"
        if j.exists():
            sizes.update({str(k): v for k, v in json.loads(j.read_text()).items()})
    (OUT / "trace_sizes.json").write_text(json.dumps(sizes, indent=2, sort_keys=True))

    # Minimal merged plan.json (§5 only uses node_counts for x-axis tick labels).
    node_counts = sorted(int(n) for n in runs["nl"].unique())
    (OUT / "plan.json").write_text(json.dumps({
        "synthetic": True,
        "note": "Merged analysis-only run; see SOURCES.md.",
        "system": SYSTEM,
        "node_counts": node_counts,
        "num_trials": TRIAL_CAP,
        "traces_from_old_run": sorted(SMALL_FROM_OLD),
        "old_run": OLD_RUN.name, "new_run": NEW_RUN.name,
    }, indent=2))

    # Provenance
    per_trace = (runs.groupby("traced_nodes")
                 .agg(source=("source_run", "first"),
                      nls=("nl", lambda s: sorted(s.unique())),
                      trials=("trial", "nunique")).reset_index())
    lines = ["# SOURCES — how run_converter_merged was assembled", "",
             f"- NEW run (larger traces): `{NEW_RUN.name}`",
             f"- OLD run (small traces {sorted(SMALL_FROM_OLD)}, trials 1-{TRIAL_CAP}): "
             f"`{OLD_RUN.name}`", "",
             "run_/phases_ CSV schemas are identical across the two runs (verified). The bulky",
             "per-task `tasks_*.csv` is intentionally dropped (only the optional per-task",
             "breakdown graph used it; it auto-skips when absent).", "",
             "| trace (traced_nodes) | source run | nl values | trials |",
             "|---|---|---|---|"]
    for _, r in per_trace.iterrows():
        lines.append(f"| {r.traced_nodes} | {r.source} | {r.nls} | {r.trials} |")
    (OUT / "SOURCES.md").write_text("\n".join(lines) + "\n")

    print(f"Wrote {OUT}")
    print(f"  conversion_timings.csv : {len(runs)} rows, "
          f"traces={sorted(runs.traced_nodes.unique())}")
    print(f"  conversion_phases.csv  : {len(phases)} rows")
    print(f"  node_counts            : {node_counts}")
    print(per_trace.to_string(index=False))


if __name__ == "__main__":
    main()
