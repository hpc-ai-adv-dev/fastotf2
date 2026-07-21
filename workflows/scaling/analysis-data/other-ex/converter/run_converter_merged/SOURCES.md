# SOURCES — how run_converter_merged was assembled

- NEW run (larger traces): `run_20260717_203803_save`
- OLD run (small traces [2, 4, 8], trials 1-5): `run_20260714_043638_save`

run_/phases_ CSV schemas are identical across the two runs (verified). The bulky
per-task `tasks_*.csv` is intentionally dropped (only the optional per-task
breakdown graph used it; it auto-skips when absent).

| trace (traced_nodes) | source run | nl values | trials |
|---|---|---|---|
| 2 | run_20260714_043638_save | [np.int64(1), np.int64(2), np.int64(3), np.int64(4), np.int64(8)] | 5 |
| 4 | run_20260714_043638_save | [np.int64(1), np.int64(2), np.int64(4), np.int64(8), np.int64(16)] | 5 |
| 8 | run_20260714_043638_save | [np.int64(1), np.int64(2), np.int64(4), np.int64(7), np.int64(8), np.int64(13), np.int64(16), np.int64(23), np.int64(32)] | 5 |
| 16 | run_20260717_203803_save | [np.int64(1), np.int64(2), np.int64(4), np.int64(8), np.int64(16), np.int64(32)] | 5 |
| 32 | run_20260717_203803_save | [np.int64(1), np.int64(2), np.int64(4), np.int64(8), np.int64(16), np.int64(32), np.int64(64)] | 5 |
| 128 | run_20260717_203803_save | [np.int64(16), np.int64(32), np.int64(64), np.int64(128)] | 5 |
| 384 | run_20260717_203803_save | [np.int64(64), np.int64(128), np.int64(256)] | 5 |
