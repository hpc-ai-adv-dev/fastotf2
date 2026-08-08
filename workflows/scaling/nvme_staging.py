"""NVMe stage-out / full-workflow accounting helpers for converter-scaling-new.ipynb.

These cover the optional Frontier NVMe output path, which is slower than writing straight to
Lustre and only works on Frontier. A run without a workflow.csv returns None/empty.

Plot functions take a `ctx` with the notebook's graphing helpers:
    ctx.theme_pub, ctx.trace_cat, ctx.node_axis, ctx.size_label, ctx.SEC_PER_MIN
"""
import re
from pathlib import Path

import numpy as np
import pandas as pd
from plotnine import *  # noqa: F401,F403

DARK2 = ["#1B9E77", "#D95F02", "#7570B3", "#E7298A",
         "#66A61E", "#E6AB02", "#A6761D", "#666666"]

# Workflow stages, first step on the bottom of the stack.
WORKFLOW_STAGE_ORDER = [
    "Internal conversion", "Runtime launch/teardown", "Archive",
    "Copy to shared storage", "Extract/publish", "Preparation + cleanup",
]
WORKFLOW_STAGE_COLORS = {
    "Internal conversion": DARK2[2],
    "Runtime launch/teardown": DARK2[7],
    "Archive": DARK2[5],
    "Copy to shared storage": DARK2[0],
    "Extract/publish": DARK2[1],
    "Preparation + cleanup": DARK2[6],
}
# Merged-frame column for each stage (see build_workflow_merged).
WORKFLOW_COMPONENT_COLUMNS = {
    "Internal conversion": "internal_conversion_seconds",
    "Runtime launch/teardown": "runtime_overhead_seconds",
    "Archive": "archive_seconds",
    "Copy to shared storage": "copy_seconds",
    "Extract/publish": "extract_seconds",
    "Preparation + cleanup": "preparation_cleanup_seconds",
}
STORAGE_COLORS = {
    "NVMe internal": DARK2[0],
    "NVMe internal + stage-out": DARK2[1],
    "Shared filesystem (historical)": DARK2[2],
}


def _parse_tag(name):
    m = re.match(r"size(\d+)_nl(\d+)_trial(\d+)", name)
    return dict(traced_nodes=int(m[1]), nl=int(m[2]), trial=int(m[3])) if m else {}


# --------------------------------------------------------------------------- load / merge
def load_workflow_timings(base_dir):
    """Load notebook-level launch, stage-out, and end-to-end timings when present (NVMe runs)."""
    frames = []
    for csv_path in sorted(Path(base_dir).rglob("workflow.csv")):
        frame = pd.read_csv(csv_path)
        if frame.empty:
            continue
        meta = _parse_tag(csv_path.parent.name)
        for key, value in meta.items():
            if key not in frame.columns:
                frame[key] = value
        frames.append(frame)
    return pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()


def build_workflow_merged(runs, workflow):
    """One successful row per trial with additive internal and operational timing components."""
    if runs.empty or workflow.empty:
        return pd.DataFrame()

    keys = ["traced_nodes", "nl", "trial"]
    valid = workflow[(workflow["status"] == "ok") & (workflow["rc"] == 0)].copy()
    merged = runs.merge(valid, on=keys, how="inner", validate="one_to_one",
                        suffixes=("", "_workflow"))
    if merged.empty:
        return merged

    merged["internal_conversion_seconds"] = merged["totalTime"]
    merged["runtime_overhead_seconds"] = (
        merged["converter_seconds"] - merged["internal_conversion_seconds"]
    ).clip(lower=0)
    merged["stageout_residual_seconds"] = (
        merged["stageout_seconds"] - merged["archive_seconds"]
        - merged["copy_seconds"] - merged["extract_seconds"]
    ).clip(lower=0)
    merged["workflow_residual_seconds"] = (
        merged["end_to_end_seconds"] - merged["prep_seconds"]
        - merged["converter_seconds"] - merged["stageout_seconds"]
    ).clip(lower=0)
    merged["preparation_cleanup_seconds"] = (
        merged["prep_seconds"] + merged["stageout_residual_seconds"]
        + merged["workflow_residual_seconds"]
    )
    merged["events"] = merged["throughput"] * merged["totalTime"]
    merged["effective_workflow_throughput"] = merged["events"] / merged["end_to_end_seconds"]
    merged["stageout_fraction"] = merged["stageout_seconds"] / merged["end_to_end_seconds"]

    component_columns = [
        "internal_conversion_seconds", "runtime_overhead_seconds", "archive_seconds",
        "copy_seconds", "extract_seconds", "preparation_cleanup_seconds",
    ]
    merged["component_sum_seconds"] = merged[component_columns].sum(axis=1)
    merged["component_residual_seconds"] = (
        merged["end_to_end_seconds"] - merged["component_sum_seconds"]
    )
    return merged


# --------------------------------------------------------------------------- workflow accounting
def plot_workflow_accounting(traced_nodes, workflow_merged, ctx):
    """Stacked stage medians for one trace with the end-to-end median and a P5-P95 whisker.
    None if there is no workflow data for this trace."""
    if workflow_merged.empty:
        return None
    rows = workflow_merged[workflow_merged["traced_nodes"] == traced_nodes].copy()
    if rows.empty:
        return None
    nodes = sorted(int(n) for n in rows["nl"].unique())
    node_cats = [str(n) for n in nodes]

    recs = []
    for stage in WORKFLOW_STAGE_ORDER:
        col = WORKFLOW_COMPONENT_COLUMNS[stage]
        if col not in rows:
            continue
        med = rows.groupby("nl")[col].median() / ctx.SEC_PER_MIN
        for n in nodes:
            recs.append({"nl": str(n), "stage": stage, "minutes": float(med.get(n, 0.0))})
    comp = pd.DataFrame(recs)
    stages_present = [s for s in WORKFLOW_STAGE_ORDER if s in set(comp["stage"])]
    comp["stage"] = pd.Categorical(comp["stage"],
                                   categories=list(reversed(stages_present)), ordered=True)
    comp["nl"] = pd.Categorical(comp["nl"], categories=node_cats, ordered=True)

    tq = (rows.groupby("nl")["end_to_end_seconds"].quantile([0.05, 0.50, 0.95])
          .unstack().reindex(nodes))
    td = pd.DataFrame({"nl": node_cats, "med": tq[0.50].to_numpy() / ctx.SEC_PER_MIN,
                       "lo": tq[0.05].to_numpy() / ctx.SEC_PER_MIN,
                       "hi": tq[0.95].to_numpy() / ctx.SEC_PER_MIN})
    td["nl"] = pd.Categorical(td["nl"], categories=node_cats, ordered=True)

    return (ggplot(comp, aes("nl", "minutes", fill="stage"))
            + geom_col(position=position_stack(reverse=True), width=0.72)
            + geom_errorbar(td, aes("nl", ymin="lo", ymax="hi"), inherit_aes=False,
                            width=0.12, size=0.6)
            + geom_point(td, aes("nl", "med"), inherit_aes=False, color="black", size=2.4)
            + scale_fill_manual(values=WORKFLOW_STAGE_COLORS, breaks=stages_present)
            + guides(fill=guide_legend(nrow=2))
            + expand_limits(y=float(td["hi"].max()) * 1.08)
            + labs(title=f"End-to-End Workflow (NVMe stage-out): {ctx.size_label(traced_nodes)} Trace",
                   subtitle="point = end-to-end median, whisker = P5-P95",
                   x="Number of Nodes", y="Median Time (minutes)", fill="Stage")
            + ctx.theme_pub(9, 5.5))


# ----------------------------------------------------- Historical shared-FS vs NVMe diagnostics
def load_historical_internal_runs(run_groups, load_timings, out_root):
    """Load converter-internal timings only; historical runs have no workflow.csv."""
    frames = []
    for storage_label, run_refs in run_groups.items():
        for run_ref in run_refs:
            path = Path(run_ref)
            run_dir = path if path.exists() else out_root / str(run_ref)
            timing_dir = run_dir / "timings"
            if not timing_dir.is_dir():
                print(f"Historical timing directory missing: {timing_dir}")
                continue
            historical_runs, _, _ = load_timings(timing_dir)
            if historical_runs.empty:
                continue
            historical_runs = historical_runs.copy()
            historical_runs["storage_path"] = storage_label
            historical_runs["source_run"] = run_dir.name
            frames.append(historical_runs)
    return pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()


def matched_historical_data(current_runs, historical_runs, selected_traces):
    """Keep only (trace, nl) configurations represented in both current and historical data."""
    if current_runs.empty or historical_runs.empty:
        return pd.DataFrame()
    current = current_runs[current_runs["traced_nodes"].isin(selected_traces)].copy()
    historical = historical_runs[historical_runs["traced_nodes"].isin(selected_traces)].copy()
    matched_frames = []
    for storage_label, subset in historical.groupby("storage_path"):
        keys = current[["traced_nodes", "nl"]].drop_duplicates().merge(
            subset[["traced_nodes", "nl"]].drop_duplicates(),
            on=["traced_nodes", "nl"], how="inner")
        if keys.empty:
            continue
        current_match = current.merge(keys, on=["traced_nodes", "nl"], how="inner")
        current_match["storage_path"] = "NVMe internal"
        historical_match = subset.merge(keys, on=["traced_nodes", "nl"], how="inner")
        matched_frames.extend([current_match, historical_match])
    return pd.concat(matched_frames, ignore_index=True) if matched_frames else pd.DataFrame()


def plot_historical_internal_comparison(matched, ctx):
    """Diagnostic internal-time comparison; not a controlled storage A/B experiment."""
    if matched.empty:
        print("Historical internal-time comparison: no completed matched configurations yet.")
        return None
    summary = (matched.groupby(["traced_nodes", "nl", "storage_path"])["totalTime"]
               .agg(med="median", lo="min", hi="max").reset_index())
    summary["minutes"] = summary["med"] / ctx.SEC_PER_MIN
    summary["lo_min"] = summary["lo"] / ctx.SEC_PER_MIN
    summary["hi_min"] = summary["hi"] / ctx.SEC_PER_MIN
    summary["trace"] = ctx.trace_cat(summary["traced_nodes"])
    return (ggplot(summary, aes("nl", "minutes", color="storage_path", fill="storage_path"))
            + geom_ribbon(aes(ymin="lo_min", ymax="hi_min"), alpha=0.12, color=None)
            + geom_line() + geom_point(size=2.2)
            + facet_wrap("trace", scales="free_y")
            + ctx.node_axis(summary["nl"]) + expand_limits(y=0)
            + scale_color_manual(values=STORAGE_COLORS)
            + scale_fill_manual(values=STORAGE_COLORS)
            + labs(title="Historical Storage Comparison: Internal Conversion Time",
                   x="Number of Nodes", y="Median Internal Time (minutes)",
                   color="Storage Path", fill="Storage Path")
            + ctx.theme_pub(10, 5.5))


def build_break_even_data(historical_runs, current_workflow, selected_traces):
    """Matched historical internal vs NVMe internal and NVMe internal plus stage-out."""
    if historical_runs.empty or current_workflow.empty:
        return pd.DataFrame()
    historical = historical_runs[historical_runs["traced_nodes"].isin(selected_traces)].copy()
    current = current_workflow[current_workflow["traced_nodes"].isin(selected_traces)].copy()
    keys = historical[["traced_nodes", "nl"]].drop_duplicates().merge(
        current[["traced_nodes", "nl"]].drop_duplicates(),
        on=["traced_nodes", "nl"], how="inner")
    if keys.empty:
        return pd.DataFrame()

    historical_summary = (historical.merge(keys, on=["traced_nodes", "nl"])
                          .groupby(["traced_nodes", "nl"])["totalTime"].median()
                          .rename("seconds").reset_index())
    historical_summary["series"] = "Shared filesystem (historical)"

    current_matched = current.merge(keys, on=["traced_nodes", "nl"])
    internal = (current_matched.groupby(["traced_nodes", "nl"])["internal_conversion_seconds"]
                .median().rename("seconds").reset_index())
    internal["series"] = "NVMe internal"
    with_stageout = current_matched.assign(
        internal_plus_stageout=current_matched["internal_conversion_seconds"]
        + current_matched["stageout_seconds"]
    ).groupby(["traced_nodes", "nl"])["internal_plus_stageout"].median().rename(
        "seconds").reset_index()
    with_stageout["series"] = "NVMe internal + stage-out"
    return pd.concat([historical_summary, internal, with_stageout], ignore_index=True)


def plot_break_even(data, ctx):
    if data.empty:
        print("Historical break-even comparison: no completed matched workflow rows yet.")
        return None
    data = data.copy()
    data["minutes"] = data["seconds"] / ctx.SEC_PER_MIN
    data["trace"] = ctx.trace_cat(data["traced_nodes"])
    return (ggplot(data, aes("nl", "minutes", color="series"))
            + geom_line() + geom_point(size=2.2)
            + facet_wrap("trace", scales="free_y")
            + ctx.node_axis(data["nl"]) + expand_limits(y=0)
            + scale_color_manual(values=STORAGE_COLORS)
            + labs(title="Historical Storage Break-Even Diagnostic",
                   x="Number of Nodes", y="Median Time (minutes)", color="Timing Scope")
            + ctx.theme_pub(10, 5.5))


def plot_stageout_fraction(current_workflow, selected_traces, ctx, trace_colors):
    selected = current_workflow[current_workflow["traced_nodes"].isin(selected_traces)].copy()
    if selected.empty:
        print("Stage-out fraction: no completed selected workflow rows yet.")
        return None
    summary = (selected.groupby(["traced_nodes", "nl"])["stageout_fraction"]
               .agg(med="median", lo="min", hi="max").reset_index())
    summary[["med", "lo", "hi"]] *= 100.0
    summary["trace"] = ctx.trace_cat(summary["traced_nodes"])
    return (ggplot(summary, aes("nl", "med", color="trace", fill="trace"))
            + geom_ribbon(aes(ymin="lo", ymax="hi"), alpha=0.12, color=None)
            + geom_line() + geom_point(size=2.2)
            + facet_wrap("trace", scales="free_y")
            + ctx.node_axis(summary["nl"]) + expand_limits(y=0)
            + scale_color_manual(values=trace_colors)
            + scale_fill_manual(values=trace_colors)
            + labs(title="NVMe Stage-Out Share of End-to-End Time",
                   x="Number of Nodes", y="Stage-Out / End-to-End Time (%)",
                   color="Trace Size", fill="Trace Size")
            + ctx.theme_pub(10, 5.5))
