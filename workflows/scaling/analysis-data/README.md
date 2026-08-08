# analysis-data

Small, non-sensitive data to re-run the analysis/graphing cells of the scaling notebooks without
the multi-TB traces/Parquet or any account/system-sensitive content. Safe to commit and clone.

Runs live at `analysis-data/<system>/<analysis>/<run>/`, where `<system>` is a neutral label
(`other-ex`, `frontier`) and `<analysis>` is `converter` or `ampere`. The bench notebook uses the
same layout under `bench/` in the fastotf2-bench repo. `other-ex` converter data is a merge (see
below); `frontier` converter data is a single complete STRONG sweep.

## Re-run an analysis

Restart the kernel, go to the notebook's §5, set `ANALYZE_RUN`, and run the graph cells. No
collection, traces, or Parquet needed.

- converter (`converter-scaling-new.ipynb`): `ANALYZE_RUN = "analysis-data/<system>/converter/<run>"`.
  §5 reads the aggregated `conversion_timings.csv` / `conversion_phases.csv`, plus
  `conversion_tasks.csv` (per-task rows for the summary configs) for the task-imbalance graph.
- ampere (`ampere-workflows-new.ipynb`): `ANALYZE_RUN = "analysis-data/<system>/ampere/<run>"`.
  §5 reads `end_to_end_results.csv`.
- bench: in the fastotf2-bench repo, `ANALYZE_RUN = "<system>/bench/<run>"`.

## What's kept and dropped

Kept: the aggregated timing CSVs, per-task rows for the summary configs (`conversion_tasks.csv`),
`plan.json`, `trace_sizes.json` / `parquet_sizes.json`, and `plots/`. Dropped: `pq/` Parquet,
`*.sif`, `scratch/`, `slurm_logs/`, `run_logs/` (they carry hostnames and `--account`/`--mail-user`),
per-task rows for every other config, manifests, `*.pid`, `job_times/`.

## other-ex converter merge

The `other-ex` converter data is merged from two partial runs: the small traces {2,4,8} come from
`run_20260714_043638_save` (capped to 5 trials), the rest from `run_20260717_203803_save`. See the
run's `SOURCES.md`.

## Build a run on a new system

Runs land in each repo's ignored `out/`. Then:

- converter, one complete run: `python tools/build_converter_single.py --src-run out/<run> --system <system>`
- converter, split across two runs: `python tools/build_converter_merged.py --new-run out/<new> --old-run out/<old> --system <system>`
- ampere, after the notebook's §4 combine: `python tools/build_ampere_analysis_data.py --src-run out/<run> --system <system>`
- bench, in the fastotf2-bench repo: `python analysis-data/tools/build_bench_analysis_data.py --src-run out/<run> --system <system>`

Run `git status` and check the staged size before committing.
