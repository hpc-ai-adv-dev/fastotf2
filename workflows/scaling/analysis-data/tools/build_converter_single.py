#!/usr/bin/env python3
"""Build B's analysis-data from a SINGLE, self-complete converter run.

Sibling of build_converter_merged.py. That tool exists only because the `other-ex` data was
split across two incomplete notebook versions and had to be fabricated into one clean run.
When a system produces ONE run that already covers every trace it cares about (e.g. the
Frontier STRONG sweep), no merge is needed -- this is the "plain aggregation of one run" the
README mentions.

It AGGREGATES the tiny per-trial CSVs into two small tidy CSVs (dropping the bulky per-task
tasks_*.csv, which only feeds one optional breakdown graph):
  * conversion_timings.csv  -- one row per (traced_nodes, nl, trial): run_*.csv columns.
  * conversion_phases.csv   -- one row per (traced_nodes, nl, trial, phase): phases_*.csv columns.

and copies the small, non-sensitive caches/figures the analysis half needs:
  * trace_sizes.json / parquet_sizes.json  (so the du -sb size step is skipped)
  * plan.json                              (§5 uses node_counts for x-axis tick labels)
  * plots/                                 (pre-rendered PNGs)

The converter notebook's §5 `load_timings()` has a shim that reads the aggregated CSVs when
present (and then `df_tasks` is empty, so the per-task graph auto-skips). Nothing here carries
account/mail/user data -- the run/phase CSVs hold only timings + a world-shared trace path,
and plan/size JSONs are pure numbers. (slurm_logs/, run_logs/, pq/, etc. are never copied.)

Re-runnable on any machine: point SRC_RUN at that machine's run and set SYSTEM.
"""
import json
import re
import shutil
import sys
from pathlib import Path

import pandas as pd

# ---- Configure (edit these when replicating on another system) ----
SCALING_DIR = Path(__file__).resolve().parents[2]                 # .../workflows/scaling
SRC_RUN = SCALING_DIR / "out" / "run_20260717_215056"             # the single, self-complete run
SYSTEM = "frontier"                                               # analysis-data/<SYSTEM>/converter/...
OUT = SCALING_DIR / "analysis-data" / SYSTEM / "converter" / SRC_RUN.name

_TAG = re.compile(r"size(\d+)_nl(\d+)_trial(\d+)$")


def _collect(run_dir):
    """Return (run_rows, phase_rows) lists for every size{T}_nl{N}_trial{K} config under
    run_dir/timings, tagging each row with traced_nodes/nl/trial/source_run."""
    run_rows, phase_rows = [], []
    tdir = Path(run_dir) / "timings"
    for d in sorted(tdir.iterdir()):
        m = _TAG.match(d.name)
        if not m:
            continue                       # skip warmup_/other dirs
        t, nl, trial = int(m[1]), int(m[2]), int(m[3])
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
    if not (SRC_RUN / "timings").is_dir():
        sys.exit(f"ERROR: no timings/ under {SRC_RUN}")

    run_rows, phase_rows = _collect(SRC_RUN)
    if not run_rows:
        sys.exit(f"ERROR: no size*_nl*_trial* configs found under {SRC_RUN}/timings")
    runs = pd.concat(run_rows, ignore_index=True)
    phases = pd.concat(phase_rows, ignore_index=True)

    OUT.mkdir(parents=True, exist_ok=True)
    # CSVs live under a timings/ subdir so the notebook's resolve_timings_dir() (which returns
    # <run>/timings) works unchanged -- only load_timings() gets the aggregated-read shim.
    tdir_out = OUT / "timings"
    tdir_out.mkdir(parents=True, exist_ok=True)
    _cols = ["traced_nodes", "nl", "trial", "timestamp", "strategy", "numLocales",
             "tracePath", "totalTime", "throughput", "source_run"]
    runs[_cols].sort_values(["traced_nodes", "nl", "trial"]).to_csv(
        tdir_out / "conversion_timings.csv", index=False)
    phases[["traced_nodes", "nl", "trial", "phase", "time", "pctTotal", "source_run"]].to_csv(
        tdir_out / "conversion_phases.csv", index=False)

    # Small, non-sensitive caches/figures the analysis half reads (all pure numbers / PNGs).
    for name in ("trace_sizes.json", "parquet_sizes.json", "plan.json"):
        src = SRC_RUN / name
        if src.exists():
            shutil.copy2(src, OUT / name)
        else:
            print(f"WARNING: {name} missing in {SRC_RUN}")
    if (SRC_RUN / "plots").is_dir():
        shutil.copytree(SRC_RUN / "plots", OUT / "plots", dirs_exist_ok=True)

    # Provenance
    per_trace = (runs.groupby("traced_nodes")
                 .agg(nls=("nl", lambda s: sorted(int(x) for x in s.unique())),
                      trials=("trial", "nunique")).reset_index())
    lines = ["# SOURCES — converter analysis data (single run)", "",
             f"- Source run: `{SRC_RUN.name}` (a single, self-complete {SYSTEM} sweep).",
             "- Aggregated the per-trial `run_/phases_` CSVs into `conversion_timings.csv` /",
             "  `conversion_phases.csv`; the bulky per-task `tasks_*.csv` is intentionally dropped",
             "  (only the optional per-task breakdown graph used it; it auto-skips when absent).",
             "- Also copied (non-sensitive): trace_sizes.json, parquet_sizes.json, plan.json, plots/.",
             "- Dropped (bulky and/or sensitive, unused by analysis): pq/, slurm_logs/, run_logs/,",
             "  timings_sample/, job_times/, manifest.csv, workflow.log.", "",
             "| trace (traced_nodes) | nl values | trials |",
             "|---|---|---|"]
    for _, r in per_trace.iterrows():
        lines.append(f"| {r.traced_nodes} | {r.nls} | {r.trials} |")
    (OUT / "SOURCES.md").write_text("\n".join(lines) + "\n")

    print(f"Wrote {OUT}")
    print(f"  conversion_timings.csv : {len(runs)} rows, "
          f"traces={sorted(int(x) for x in runs.traced_nodes.unique())}")
    print(f"  conversion_phases.csv  : {len(phases)} rows")
    print(f"  node_counts            : {sorted(int(x) for x in runs.nl.unique())}")
    print(per_trace.to_string(index=False))


if __name__ == "__main__":
    main()
