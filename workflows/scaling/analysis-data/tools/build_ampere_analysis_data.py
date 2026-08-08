#!/usr/bin/env python3
"""Build the ampere analysis-data from one complete run.

Copies end_to_end_results.csv, a sanitized plan.json, and plots/. The results CSV must already
exist (produced by the notebook's §4 combine).

    python build_ampere_analysis_data.py --src-run out/run_YYYYMMDD_HHMMSS_save --system frontier
"""
import argparse
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sanitize import sanitize_json

REPO = Path(__file__).resolve().parents[2]        # workflows/scaling/


def main():
    ap = argparse.ArgumentParser(
        description="Build the ampere (A) analysis-data subset from one complete run.")
    ap.add_argument("--src-run", type=Path, required=True,
                    help="source run folder under out/ (absolute, or relative to workflows/scaling)")
    ap.add_argument("--system", required=True,
                    help="system label for analysis-data/<system>/ampere/ (e.g. other-ex, frontier)")
    args = ap.parse_args()

    SRC_RUN = args.src_run if args.src_run.is_absolute() else (REPO / args.src_run)
    SYSTEM = args.system
    # Unified layout: analysis-data/<system>/<analysis>/<run>/ (this notebook's analysis = ampere).
    OUT = REPO / "analysis-data" / SYSTEM / "ampere" / SRC_RUN.name

    if not (SRC_RUN / "end_to_end_results.csv").exists():
        sys.exit(f"ERROR: {SRC_RUN}/end_to_end_results.csv missing -- run §4 combine first.")
    OUT.mkdir(parents=True, exist_ok=True)

    shutil.copy2(SRC_RUN / "end_to_end_results.csv", OUT / "end_to_end_results.csv")

    plan = json.loads((SRC_RUN / "plan.json").read_text())
    (OUT / "plan.json").write_text(json.dumps(sanitize_json(plan), indent=2))

    if (SRC_RUN / "plots").is_dir() and any((SRC_RUN / "plots").iterdir()):
        shutil.copytree(SRC_RUN / "plots", OUT / "plots", dirs_exist_ok=True)

    (OUT / "SOURCES.md").write_text(
        f"# SOURCES — ampere-workflows-new analysis data ({SYSTEM})\n\n"
        f"- Source run: `{SRC_RUN.name}` (renamed from `run_20260721_013322` after its detached\n"
        f"  collector exited; see workflow.log / arkouda_collect.log in the full run for history).\n"
        f"- `end_to_end_results.csv` was produced by a HEADLESS replay of the notebook's §4\n"
        f"  combine logic (identical to running the §4 cell with COMBINE_RUN set to this run --\n"
        f"  the collector process itself was no longer alive to run it interactively).\n"
        f"- **`s128 @ 16 nodes` is intentionally EXCLUDED** (not even as a status=failed row):\n"
        f"  it never finished -- the per-trial watchdog killed it after TRIAL_TIMEOUT (1h) hung.\n"
        f"  That's an incomplete-collection artifact, not a reproducible outcome worth reporting\n"
        f"  (unlike e.g. the `s16` pandas OOM, which IS a real, repeatable result and IS kept).\n"
        f"  `128 @ 32`, `384 @ 16`, `384 @ 64` were never collected at all (run stopped early)\n"
        f"  and are simply absent -- no row for them either.\n"
        f"- plan.json is sanitized (account/mail redaction; a no-op here, SLURM_ACCOUNT=None).\n"
        f"- Re-run §5: set the notebook's ANALYZE_RUN to this folder.\n")

    print(f"Wrote {OUT}")
    for f in sorted(OUT.rglob("*")):
        if f.is_file():
            print("  ", f.relative_to(OUT), f"({f.stat().st_size} B)")


if __name__ == "__main__":
    main()
