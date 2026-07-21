#!/usr/bin/env python3
"""Build A's (ampere-workflows-new.ipynb) analysis-data: the small, clean, git-safe subset
needed to re-run §5 (results analysis) on another machine.

A's §5 is fully self-contained from `end_to_end_results.csv` -- nothing else is needed (no
traces, no Parquet, no B/C conversion runs). This script assumes that CSV was already produced
(here, via a headless replay of §4 against a run whose collector had died -- see SOURCES.md);
it just copies the small, non-sensitive artifacts into analysis-data/.

Re-run on another system by editing SRC_RUN / SYSTEM below (e.g. SYSTEM="frontier").
"""
import json
import re
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]        # workflows/scaling/
SRC_RUN = REPO / "out" / "run_20260721_013322_save"
SYSTEM = "other-ex"
OUT = REPO / "analysis-data" / SYSTEM / "ampere" / SRC_RUN.name

# Same sanitizer as the bench tool -- ampere's plan.json currently carries no account/mail
# (SLURM_ACCOUNT is None on this system), but route it through anyway for defense-in-depth
# (e.g. if this is ever replicated on Frontier where SLURM_ACCOUNT is set).
_SENS_KEY = re.compile(r"(account|mail|secret|token|password|passwd)", re.I)
_SENS_VAL = re.compile(r"(--?(account|mail[-_]?user|uid)\b|[\w.+-]+@[\w.-]+)", re.I)
REDACT = "<redacted>"


def sanitize_json(obj):
    if isinstance(obj, dict):
        return {k: (REDACT if _SENS_KEY.search(k) else sanitize_json(v)) for k, v in obj.items()}
    if isinstance(obj, list):
        return [sanitize_json(x) for x in obj]
    if isinstance(obj, str) and _SENS_VAL.search(obj):
        return REDACT
    return obj


def main():
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
