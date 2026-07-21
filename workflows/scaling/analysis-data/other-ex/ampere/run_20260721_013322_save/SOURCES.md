# SOURCES — ampere-workflows-new analysis data (other-ex)

- Source run: `run_20260721_013322_save` (renamed from `run_20260721_013322` after its detached
  collector exited; see workflow.log / arkouda_collect.log in the full run for history).
- `end_to_end_results.csv` was produced by a HEADLESS replay of the notebook's §4
  combine logic (identical to running the §4 cell with COMBINE_RUN set to this run --
  the collector process itself was no longer alive to run it interactively).
- **`s128 @ 16 nodes` is intentionally EXCLUDED** (not even as a status=failed row):
  it never finished -- the per-trial watchdog killed it after TRIAL_TIMEOUT (1h) hung.
  That's an incomplete-collection artifact, not a reproducible outcome worth reporting
  (unlike e.g. the `s16` pandas OOM, which IS a real, repeatable result and IS kept).
  `128 @ 32`, `384 @ 16`, `384 @ 64` were never collected at all (run stopped early)
  and are simply absent -- no row for them either.
- plan.json is sanitized (account/mail redaction; a no-op here, SLURM_ACCOUNT=None).
- Re-run §5: set the notebook's ANALYZE_RUN to this folder.
