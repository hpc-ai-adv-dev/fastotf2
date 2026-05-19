# Running the Memory Matrix Headlessly

## Steps

1. Make sure the notebook is saved with the desired configuration
   (NUM_TRIALS, TRACE_INPUTS, NODE_COUNT, etc.)

2. Convert to a Python script:
   ```bash
   jupyter nbconvert --to script mem_matrix.ipynb
   ```

3. Launch in tmux:
   ```bash
   tmux new -s mem
   python mem_matrix.py 2>&1 | tee mem_matrix.log
   ```
   Then detach with `Ctrl-b d`. Close your laptop — the session persists.

4. Reconnect later:
   ```bash
   tmux attach -t mem
   ```

5. The plotting cells will error (no display backend) — that's fine.
   Memory data is parsed from `.out` files under the JOB_LOG_DIR printed
   at the start of the run.

6. To analyze the results, open the notebook and set `HOST_LOG_DIR`
   to the completed run's `slurm_logs/` folder, then run the analysis cells.

