# Workflow notebook best practices

Distilled, reusable conventions for the HPC "collect timings on Slurm, then graph them"
notebooks in this repo (`converter-scaling-new.ipynb`, `ampere-workflows-new.ipynb`, …).
Copy these patterns when building the next one.

---

## 1. One `SYSTEM` switch, all machine specifics in a dict

- A single top-of-notebook `SYSTEM = "other-ex" | "frontier"` line selects the cluster.
- Everything machine-specific lives in one `SYSTEM_CONFIGS[SYSTEM]` dict: cpus-per-task,
  container image + pull method, apptainer PATH/cache dirs, `sbatch` extras, input/trace
  paths, ranks-per-node. Nothing else in the notebook branches on the machine name.
- Never write the real cluster name in the notebook — use a neutral label (`"other-ex"`).
- Entries that don't apply on a machine are `None` and skipped (e.g. apptainer already on PATH
  on Frontier → `apptainer_bin_path: None`).
- Fail fast: if the selected system is missing required config (paths, secrets), `raise`
  immediately with a message that says exactly what to set.

## 2. Secrets never hardcoded

- Slurm account / mail live in a **gitignored `local_secrets.py`** next to the notebook,
  with a committed `local_secrets.example.py` template.
- Import with a fallback to environment variables:
  ```python
  try:
      from local_secrets import SLURM_ACCOUNT, SLURM_MAIL_USER
  except ImportError:
      SLURM_ACCOUNT   = os.environ.get("SLURM_ACCOUNT")
      SLURM_MAIL_USER = os.environ.get("SLURM_MAIL_USER")
  ```
- Remember: env vars exported in a shell are **not** inherited by an already-running Jupyter
  kernel — `local_secrets.py` is the reliable path; document that in the cell.

## 3. Timestamped run folders — never clobber

- Each collection run creates `out/run_<YYYYmmdd_HHMMSS>/` with fixed subdirs
  (`timings/`, `slurm_logs/`, `run_logs/`, `plots/`, plus a `plan.json` and `workflow.log`).
- Large/regenerable outputs (Parquet, scratch) go in clearly-labelled subdirs that are safe to
  delete.
- `workflows.set_workflow_log()` chdir's into the run dir — restore the workflow dir right
  after (`os.chdir(WORKFLOW_DIR)`) so relative paths keep working.
- **Never rename or move a run folder while its detached collector is still running.** The
  collector holds absolute paths (from its config JSON); renaming `out/run_X` → `out/run_X_save`
  breaks new CSV writes and server-log lookups (already-open fds survive, but fresh opens fail).
  Rename to an archival `_save` name only *after* the run is fully done.

## 4. Split "collect" from "analyse" — and make analysis self-contained

- Data collection (§0–§3/4) and graphing (§5) are separate halves.
- The analysis half must run **standalone after a kernel restart**: it reads only files from a
  run folder, driven by an `ANALYZE_RUN` variable:
  - `None` → the run created in this session,
  - a run **tag** → resolve under `out/`,
  - a full **path** → use directly.
- Persist a `plan.json` at design time and a tidy results CSV at combine time, so §5 can redraw
  a **previous** run's graphs exactly, with no re-collection and no hidden in-kernel state.

## 5. Always-safe first execution: `DRY_RUN` and `SAMPLE_RUN`

- `DRY_RUN` (default **`True`**): submit/launch nothing; print the exact commands, sbatch
  scripts, and the planned matrix. Flip off only when the preview looks right.
- `SAMPLE_RUN` (default **`True`**): a tiny but *real* matrix (fewest/smallest configs, 1
  trial) that still exercises the whole pipeline and produces real (small) graphs before
  committing to the overnight sweep. Keep sample outputs separate so they never mix with a
  full sweep.

## 6. Make the experiment matrix plain, editable config

- Prefer an explicit editable dict/list over a clever formula (e.g. `ANALYSIS_NODES = {16:[1,4],
  …}`). Formulas hide intent; dicts let the user add/remove points trivially.
- Print the resolved matrix (and any inexact/auto-derived choices, flagged) before running, so
  the cost and the exact configs are visible up front.

## 7. Slurm job design

- **One job per config, multiple trials inside it.** Pay the queue wait once per config; loop
  `NUM_TRIALS` trials back-to-back inside one allocation. Keep per-trial output dirs
  regex-parseable (`size{T}_nl{N}_trial{K}`).
- **Dependency-chain** jobs (`--dependency afterany:<prev>`) so I/O-heavy runs execute
  **serially** — overlapping jobs contend for the shared filesystem and corrupt each other's
  timings. Optionally cross-check for overlap afterwards (self-reported wall windows + `sacct`).
- Use `--exclusive` for clean, non-shared performance numbers.
- Budget walltime per trial × trials, capped by the machine's node-count walltime tiers.
- Write each job's `sbatch` script, `run_args.json`, and submission command under `run_logs/`,
  and a `manifest.csv` of every job id.

## 8. Measure the thing, not the noise

- Reset state between trials (e.g. `ak.clear()` on an arkouda server; `gc.collect()` +
  `del` in pandas) so trial *k* doesn't inherit trial *k-1*'s memory/caches.
- Aggregate trials by **median** in graphs (robust to a stray slow first run).
- Keep heavy work **off the login node** — run even "single-node" analyses as an exclusive
  batch job, not inline in the kernel, when the data is large.
- Wrap each config in `try/except`: record `status="failed"` + the error and **continue** the
  sweep. A single OOM/timeout must not abort the whole run.

## 9. Timings from CSV, not log-scraping

- Have the tool emit a machine-readable timing CSV (a `--timings-csv` flag, or a one-row CSV
  per job) and read that. Don't parse wall-clock out of stdout/logs.
- Define one **common timing schema** shared by every collector so the combine step is a plain
  `pd.concat`.

## 10. Consistent, honest units and labels

- Measure sizes with `du -sb` and compute GiB as `1024**3` (not `du -h`'s decimal). Use one
  shared size formatter across notebooks so "11.6 GiB" is never "12 GiB" elsewhere.
- Make trace/size an **ordered categorical** (ascending by real size) so legends and axes are
  stable across plots.
- Node-count axes: `log2` with integer tick labels for power-of-two grids; linear integer
  breaks for bespoke (non-doubling) node counts.

## 11. Graphing (plotnine)

- Save every figure to `plots/` (`dpi=150`) *and* display it, so runs are self-documenting.
- Label axes with units; add a subtitle capturing the fixed parameters (metric, strategy).
- Guard graphs that need ≥ N groups (e.g. a strong-scaling line needs ≥ 2 node counts) with a
  clear "add more points" message instead of erroring on a sample run.
- **Define ONE shared theme + palette** in the analysis-config cell and reuse it in every figure
  so the set looks like one coherent publication set — e.g. `theme_pub(w,h)` = `theme_bw(base_size=14)`
  + top legend, bold title/axis-titles, no minor grid, styled facet strip. Fix a colour-blind-safe
  Brewer "Dark2" mapping **by name** so a given series is the same colour in every figure
  (`scale_*_manual(values=…)`, not auto colours): e.g. arkouda `#1B9E77`, pandas `#D95F02`; stages
  conversion `#7570B3`, analysis `#1B9E77`.
- **Value axis linear from 0** (`expand_limits(y=0)`), avoid a log value axis; put the
  wide-ranging categorical (trace size) on x as an *ordered* categorical so a 0.7 GiB…1.5 TiB span
  stays readable without a log scale. (Node count for strong scaling is the one place a `log2`
  axis with integer ticks is right.)
- **Label values on bars/points** (`geom_text`, bold) — the number carries magnitude the bar
  can't, especially with faceted `free_y` (where small + huge panels otherwise look equal-height).
  Give top headroom so labels aren't clipped: `scale_y_continuous(expand=(0,0,0.30,0))`.
- **Stacked bars: first workflow step on the BOTTOM.** Order the stage categorical
  `["conversion","analysis"]` and use `geom_col(position=position_stack(reverse=True))` (plain
  stacking flips it).
- **Record failures in the figure, don't drop them.** A NaN/OOM row plots as an empty/short bar
  that reads as "0"; annotate it explicitly ("analysis OOM", "pandas OOM") in every graph it
  appears in.
- **Paper-figure hygiene:** descriptive titles only (no "how to read me" subtitles — that's the
  caption's job); a dimension that's constant across the whole figure goes in the *title*, not on
  every tick; only add a shape/linetype legend when that variable has >1 level in the plotted
  data; a head-to-head figure includes only configs where *both* arms exist (put one-arm-only data
  in its own figure); explain a non-obvious categorical label once in a subtitle (units / what a
  panel is) — units are fine, instructions are not.
- Use `dpi=200` for publication PNGs (150 for quick checks). **Always eyeball the saved PNG** after
  a change (render headless with `MPLBACKEND=Agg` + a `display` stub, then view the image) —
  "it rendered" checks miss clipping, wrong stack order, and unreadable scales.

## 12. Reuse shared helpers; don't fork logic

- Put cross-notebook helpers in a shared `workflows.py` (container download, size measurement,
  queue widget, `run_cmd`/`cd`, logging). If two notebooks must agree on a number (e.g. trace
  sizes), call the **same** function, don't reimplement.
- When porting analysis logic from another notebook, **leave the original unchanged** and copy
  the pieces (topology, metric configs, the timed core) verbatim, so behaviour is identical and
  the source of truth is obvious.

## 13. Document non-obvious design choices in-place

- If something looks wrong-but-is-right (e.g. the pandas backend reading fastotf2 Parquet), say
  so in a markdown cell, an inline comment, **and** a README, so future-you doesn't "fix" it.
- Keep a `PLAN.md` with a gap/sanity-check section; note assumptions and the one or two
  subtle correctness traps (e.g. "topology comes from the *data's* node count, not the
  *server's*").
- After any programmatic edit to a (large) notebook or driver script, **validate it** —
  `py_compile`/`ast.parse` every code cell — before running; scrambled cells and stray escapes
  are easy to introduce and expensive to debug on a Slurm queue.

## 14. Sharing one e4s-cl install between notebooks (no toe-stepping)

Multiple notebooks share ONE e4s-cl install (rezaii's `e4s-cl-setup` → its `.venv`) whose
profiles live in a single global `~/.local/e4s_cl/user.json` with one mutable "selected"
profile. To keep independent notebooks from clobbering each other or the venv:

- **Install once, never from a notebook.** e4s-cl is a shared, one-time manual bootstrap
  (`e4s-cl-setup/setup_all.sh`, answer **N** to "Recreate it?" if a `.venv` exists). A notebook
  must **never** run `setup_all.sh` — its first step recreates the venv and silently picks the
  first `python3.X` on PATH, wiping installed packages. Guard with `workflows.ensure_e4s_cl()`,
  which only *asserts* e4s-cl is present and otherwise raises the bootstrap instructions.
- **One named profile per notebook; configure it BY NAME.** Use
  `workflows.ensure_e4s_profile("<name>", image=…, add_files=[…], source=…)`, which creates the
  profile if missing and edits it via `e4s-cl profile edit <name> …`. Addressing by name means
  a notebook never touches another's profile or the global "selected" slot. Profiles persist,
  so they're created once and reused → stable across runs.
- **Don't rely on the "selected" profile for batch work.** Pin
  `e4s-cl launch --profile=<name>` on every launch that runs later in the queue, so the job is
  immune to whatever gets selected between submit and run. (CLI flags override profile fields.)
- **Cede the "selected" slot to launchers that require it.** Some helper scripts (e.g. rezaii's
  `launch_arkouda.sh`) use the *selected* profile and can't be pinned; that notebook just
  `e4s-cl profile select`s its profile right before launching. This is safe precisely because
  every *other* notebook pins `--profile` and never depends on the selection.
- Net rule of thumb: **name-addressed config for everyone; `--profile` for batch/async launches;
  the global selection belongs to whoever is actively launching via a script that needs it.**

### 14a. Container env vars: set them via the profile's `--source` pre-exec, NOT `srun --export`

The single most expensive gotcha in this repo. e4s-cl / apptainer **scrubs the host environment**,
so an env var you export on the host (or pass via `srun --export=…,VAR=…`) does **not** reach the
program running *inside* the container — it silently falls back to its default.

- Concrete bite: `CHPL_RT_MAX_HEAP_SIZE` set through `launch_arkouda.sh --heap-size` (an
  `srun --export`) never reached the Chapel/arkouda server; it used its **default ~352 GiB heap**
  no matter what we set, and multi-node servers died in `fi_mr_reg (Cannot allocate memory)` on the
  Slingshot/CXI NIC. Proof it was ignored: the CXI registration size was **byte-identical** across
  runs set to 40% / 128g / 64g.
- **Fix:** give the e4s-cl profile a **`--source` pre-exec script** that `export`s the var, so
  e4s-cl sources it *inside* the container right before launch. `workflows.ensure_e4s_profile(…,
  source=<path>)` wires it — and it re-applies `profile edit --source` every run, so re-run that
  cell **once** to attach a source to a profile that was first created without one. Verify with
  `e4s-cl profile show <name>` or `~/.local/e4s_cl/user.json` (`source: …` vs `None`).
- Rule: **any** env var the containerized program needs (`CHPL_*`, `FI_*`, extra
  `LD_LIBRARY_PATH`, …) belongs in the pre-exec, not in `--export`.
- Related NIC fact: the CXI heap-registration ceiling is a NIC page-table/ATU limit, **not** total
  RAM (single-node registers nothing with the fabric, so any heap "works" at n=1 — misleading).
  Because the backend distributes data, a modest per-node heap is fine (capacity = heap × nodes);
  the only way to *keep* a large per-node heap on CXI is hugepages (a launch-script/container
  change).

## 15. Disconnect-proof, resumable, self-healing collection

For long Slurm sweeps you'll disconnect from, an in-kernel loop isn't enough — it dies with the
kernel. Run collection as a **detached** process and make it robust:

- **Detach it.** Launch the collector as a standalone script via `setsid nohup … </dev/null
  >>log 2>&1 &` so it survives the kernel / VS Code / SSH dying. It writes a PID file + a log the
  notebook can poll from a monitor cell. Keep the heavy work in the Slurm jobs; the detached
  process is just a lightweight client orchestrator that imports nothing from the notebook (it
  reads a self-contained config JSON).
- **Resumable.** Skip any config whose output CSV already exists, so re-launching after an
  interruption picks up where it left off.
- **Exactly-one-collector guard.** Detached collectors SURVIVE across sessions, so a relaunch can
  leave an OLD one alive; two collectors that share a server job name cancel each other's servers
  and stall. The launch cell must REFUSE to start if one is already running
  (`pgrep -af "[a]mpere_collect.py"` — the `[a]` bracket keeps pgrep from matching its own shell).
- **Fail FAST on a dead server job.** Don't only wait for "server is listening" — a job that dies
  at startup looks identical to "still booting" and burns the whole wait timeout. Capture the
  Slurm job id, poll `squeue -h -j <id> -o %T`, and once the job has been *seen* in the queue and
  then leaves it (or hits a terminal state FAILED/CANCELLED/OUT_OF_MEMORY/TIMEOUT/…) without ever
  listening, raise immediately with the server-log tail. Guard with a `seen_in_queue` flag to
  avoid a submit race.
- **A hung analysis can't be unblocked by killing the server.** An arkouda/ZMQ REQ client silently
  waits through server death (no heartbeat), so a thread-watchdog that only `scancel`s the server
  leaves the client stuck in `recv` forever. Run each trial in a **child process** with
  `subprocess.run(timeout=…)`; on timeout the child is SIGKILLed (its socket dies with it), then
  record the config failed and continue. The orchestrator parent should not hold the client
  connection itself.
- **Surface failures loudly + briefly.** Classify each failure into ONE human sentence for the CSV
  `error` column and a scannable log banner; dump the full multi-line error to a per-config
  `*.fail.log`; print an end-of-run summary of which configs failed and why. A monitor cell reads
  each CSV's status and lists `[ok]`/`[FAIL]` at a glance.
- **In a detached process, `log()` writes to the file only** — its stdout is already redirected
  into that same log file, so also `print()`ing duplicates every line.
- **Diagnose "is it stuck?" with the log mtime**, not vibes: compare `date` to the collector
  log's last-write time. A frozen mtime = genuinely hung; a moving one (or advancing tqdm) = just
  slow (big-trace reads/attributes legitimately take many minutes).
