# Running the Performance Matrix Headlessly

## Steps

1. Make sure the notebook is saved with the desired configuration
   (NUM_TRIALS, TRACE_INPUTS, NODE_COUNTS, etc.)

2. Convert to a Python script:
   ```bash
   jupyter nbconvert --to script perf_matrix.ipynb
   ```

3. Launch in tmux:
   ```bash
   tmux new -s perf
   python perf_matrix.py 2>&1 | tee perf_matrix.log
   ```
   Then detach with `Ctrl-b d`. Close your laptop — the session persists.

4. Reconnect later:
   ```bash
   tmux attach -t perf
   ```

5. The plotting cells will error (no display backend) — that's fine.
   All timing CSVs and the manifest are saved under the RUN_DIR printed
   at the start of the run.

6. To analyze the results, open the notebook and set `HOST_TIMINGS_DIR`
   to the completed run's `timings/` folder, then run the analysis cells.

## Notes

- The script only does lightweight work on the login node (sbatch + squeue polling).
  The actual compute happens in Slurm jobs.
