#!/usr/bin/env python3
"""Build the converter analysis-data from one complete run.

Aggregates the per-trial run_/phases_ CSVs into conversion_timings.csv and conversion_phases.csv,
and copies trace_sizes.json, parquet_sizes.json, plan.json, and plots/. The per-task tasks_*.csv
and everything under slurm_logs/, run_logs/, pq/ are left out.

    python build_converter_single.py --src-run out/run_YYYYMMDD_HHMMSS --system frontier
"""
import argparse
import json
import re
import shutil
import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sanitize import sanitize_json

SCALING_DIR = Path(__file__).resolve().parents[2]                 # .../workflows/scaling

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
    ap = argparse.ArgumentParser(
        description="Build the converter (B) analysis-data subset from ONE complete run.")
    ap.add_argument("--src-run", type=Path, required=True,
                    help="source run folder under out/ (absolute, or relative to workflows/scaling)")
    ap.add_argument("--system", required=True,
                    help="system label for analysis-data/<system>/converter/ (e.g. other-ex, frontier)")
    args = ap.parse_args()

    SRC_RUN = args.src_run if args.src_run.is_absolute() else (SCALING_DIR / args.src_run)
    SYSTEM = args.system
    # Unified layout: analysis-data/<system>/<analysis>/<run>/ (this notebook's analysis = converter).
    OUT = SCALING_DIR / "analysis-data" / SYSTEM / "converter" / SRC_RUN.name

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
    for name in ("trace_sizes.json", "parquet_sizes.json"):
        src = SRC_RUN / name
        if src.exists():
            shutil.copy2(src, OUT / name)
        else:
            print(f"WARNING: {name} missing in {SRC_RUN}")
    # plan.json is the provenance matrix -- sanitize it (defence-in-depth; it holds only numbers/
    # neutral labels today, but the shared sanitizer makes every tool safe by default).
    plan_src = SRC_RUN / "plan.json"
    if plan_src.exists():
        (OUT / "plan.json").write_text(
            json.dumps(sanitize_json(json.loads(plan_src.read_text())), indent=2) + "\n")
    else:
        print(f"WARNING: plan.json missing in {SRC_RUN}")
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
