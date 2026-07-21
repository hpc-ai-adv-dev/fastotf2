# SOURCES — converter analysis data (single run)

- Source run: `run_20260717_215056` (a single, self-complete frontier sweep).
- Aggregated the per-trial `run_/phases_` CSVs into `conversion_timings.csv` /
  `conversion_phases.csv`; the bulky per-task `tasks_*.csv` is intentionally dropped
  (only the optional per-task breakdown graph used it; it auto-skips when absent).
- Also copied (non-sensitive): trace_sizes.json, parquet_sizes.json, plan.json, plots/.
- Dropped (bulky and/or sensitive, unused by analysis): pq/, slurm_logs/, run_logs/,
  timings_sample/, job_times/, manifest.csv, workflow.log.

| trace (traced_nodes) | nl values | trials |
|---|---|---|
| 16 | [1, 2, 4, 8, 16, 32] | 5 |
| 32 | [1, 2, 4, 8, 16, 32, 64] | 5 |
| 128 | [16, 32, 64, 128] | 5 |
| 384 | [64, 128, 256] | 5 |
