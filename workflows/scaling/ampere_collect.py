#!/usr/bin/env python3
"""Detached arkouda-analysis collector for ampere-workflows-new.ipynb.

WHY THIS EXISTS
---------------
The notebook's inline `collect_arkouda()` is synchronous but runs *inside the Jupyter
kernel*. If you disconnect VS Code / the kernel is torn down, the loop dies mid-run (a
half-finished config, and the arkouda server may be left running). This script runs the
SAME orchestration as a standalone process so it can be launched DETACHED (setsid+nohup)
and survive disconnects -- you close your laptop and come back to a completed run.

The heavy work already lives in Slurm jobs (each arkouda server is its own job launched by
e4s-cl-setup/bin/launch_arkouda.sh); this process is just the lightweight *client
orchestrator* that connects, times trials, and writes the per-config timing CSVs.

RESUMABLE: a config whose output CSV already exists is skipped, so re-launching after an
interruption picks up where it left off.

USAGE
-----
    python ampere_collect.py <config.json>

The notebook writes <config.json> (see the "detached launch" cell). Everything the run needs
is in that JSON; this file imports nothing from the notebook. It must run from a Python
environment that has `ampere` + the `arkouda` client (the e4s-cl venv) and from a CWD where
`import workflows` resolves (the workflows/scaling dir).
"""
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

TIMING_COLUMNS = ["pipeline", "backend", "trace_traced_nodes", "analysis_nodes",
                  "trial", "read_seconds", "attribute_seconds", "status", "error"]

# Slurm states that mean a server job is DONE for good -> stop waiting on it immediately.
TERMINAL_JOB_STATES = {"FAILED", "CANCELLED", "COMPLETED", "TIMEOUT", "NODE_FAIL",
                       "OUT_OF_MEMORY", "BOOT_FAIL", "DEADLINE", "PREEMPTED"}


def log(msg, logfile):
    # The detached launcher redirects this process's stdout to `logfile`, so we write to the file
    # directly and do NOT also print() -- printing would duplicate every line in the log.
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    with open(logfile, "a") as f:
        f.write(line + "\n")


class ServerStartupError(RuntimeError):
    """Raised when an arkouda-server job dies before it ever listens. Carries a SHORT human
    `reason` (for the CSV + a scannable log banner) plus the full `detail` (server log tail)."""
    def __init__(self, reason, detail, job_id=None):
        super().__init__(reason)
        self.reason = reason
        self.detail = detail
        self.job_id = job_id


def classify_failure(text):
    """Turn a raw server-log tail / exception text into ONE short, human sentence so the CSV and
    log say WHAT broke without the 30-line srun dump (the full dump goes to a .fail.log)."""
    t = text or ""
    if "watchdog" in t.lower():
        return ("analysis trial exceeded the per-trial timeout -- the server was killed to "
                "unblock the sweep. ampere's attribute step is COMM-BOUND and anti-scales, so try "
                "FEWER nodes (the fewest that hold the trace in memory), not more, or raise "
                "TRIAL_TIMEOUT.")
    if "fi_mr_reg" in t or "cxip_regattr" in t or "cxil_map" in t:
        return ("CXI fabric memory-registration failed -- the Chapel heap is too large to "
                "register on multi-node. Lower ARKOUDA_HEAP (e.g. 128g -> 96g -> 64g).")
    if "PMI2" in t or "PMI_" in t or "comm-ofi" in t:
        return ("comm-ofi / PMI2 init failed at startup -- host libfabric/CXI/PMI libraries are "
                "likely not bound into the e4s-cl profile (re-run 04_setup_libraries.sh).")
    low = t.lower()
    if "out of memory" in low or "oom-kill" in low or "out_of_memory" in low:
        return "server ran out of memory (OOM) during startup/analysis."
    if "not up within" in t or "never listened" in t:
        return "server never listened within the wait timeout."
    for line in t.splitlines():                      # fallback: first error-looking line
        if any(k in line.lower() for k in ("error", "failed", "exception", "cannot", "not found")):
            return line.strip()[:200]
    return (t.strip().splitlines()[-1][:200] if t.strip() else "unknown failure")


def topology_generator(node_count, ranks_per_node):
    return {f"Node{i}": [f"MPI Rank {i * ranks_per_node + j}" for j in range(ranks_per_node)]
            for i in range(node_count)}


def topology_resolver_generator(node_count, ranks_per_node):
    d4 = [f"MPI Rank {n * ranks_per_node + i}" for i in [0, 1] for n in range(node_count)]
    d2 = [f"MPI Rank {n * ranks_per_node + i}" for i in [2, 3] for n in range(node_count)]
    d6 = [f"MPI Rank {n * ranks_per_node + i}" for i in [4, 5] for n in range(node_count)]
    d0 = [f"MPI Rank {n * ranks_per_node + i}" for i in [6, 7] for n in range(node_count)]

    def resolver(metric_name, ranks):
        if "device=4" in metric_name: return [r for r in ranks if r.name in d4]
        if "device=2" in metric_name: return [r for r in ranks if r.name in d2]
        if "device=6" in metric_name: return [r for r in ranks if r.name in d6]
        if "device=0" in metric_name: return [r for r in ranks if r.name in d0]
        return ranks
    return resolver


def arkouda_server_url(server_log_dir):
    res = subprocess.run("squeue --me --name arkouda-server -t R -h -o %i",
                         shell=True, stdout=subprocess.PIPE).stdout.decode().strip()
    if not res:
        return None
    job_id = res.split()[0]
    out_file = Path(server_log_dir) / f"arkouda_arkouda-server_{job_id}.out"
    if not out_file.exists():
        return None
    pat = re.compile(r"server listening on (tcp://\S+)")
    for line in out_file.read_text(errors="ignore").splitlines():
        m = pat.search(line)
        if m:
            host, port = m.group(1).split("//")[1].split(":")
            return host, port
    return None


def server_job_state(job_id):
    """Slurm state of a specific job while it is still in the queue ('' once it has left the
    queue, i.e. reached a terminal state and been purged from `squeue`)."""
    return subprocess.run(f"squeue -h -j {job_id} -o %T", shell=True,
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout.decode().strip()


def server_log_tail(server_log_dir, job_id, n=20):
    """Last n lines of a server job's .out (the startup/fabric/OOM error usually lands here)."""
    f = Path(server_log_dir) / f"arkouda_arkouda-server_{job_id}.out"
    if f.exists():
        return "\n".join(f.read_text(errors="ignore").splitlines()[-n:])
    return "(no server log found)"


# Child-process driver: runs ONE ampere analysis trial in isolation. WHY a subprocess: killing the
# arkouda SERVER does NOT unblock a hung ZMQ client recv (a REQ socket silently waits through peer
# death), so the only reliable way to abort a stalled read/attribute is to kill the PROCESS running
# it. The parent runs this with a hard timeout and SIGKILLs it if a trial hangs, then continues.
TRIAL_DRIVER_SRC = '''
import os, re, json, time

HOST     = os.environ["AMP_HOST"]
PORT     = int(os.environ["AMP_PORT"])
PQ_DIR   = os.environ["AMP_PQ_DIR"]
T        = int(os.environ["AMP_TRACED_NODES"])
RPN      = int(os.environ["AMP_RPN"])
METRIC   = os.environ["AMP_METRIC"]
STRATEGY = os.environ["AMP_STRATEGY"]
OUT_JSON = os.environ["AMP_OUT_JSON"]

import ampere
from ampere import Ensemble, MetricConfig, MetricType, connect
import arkouda as ak

CFG = {re.compile(r".*rocm.*energy.*"): MetricConfig(MetricType.CUMULATIVE, scale_factor=1e-6),
       re.compile(r".*rocm.*power.*"):  MetricConfig(MetricType.INSTANTANEOUS, scale_factor=1e-6)}

def topo_gen(nc, rpn):
    return {f"Node{i}": [f"MPI Rank {i*rpn+j}" for j in range(rpn)] for i in range(nc)}

def resolver_gen(nc, rpn):
    dev = {4: [0, 1], 2: [2, 3], 6: [4, 5], 0: [6, 7]}
    names = {d: [f"MPI Rank {n*rpn+i}" for i in idx for n in range(nc)] for d, idx in dev.items()}
    def r(mn, ranks):
        for d, ns in names.items():
            if f"device={d}" in mn:
                return [x for x in ranks if x.name in ns]
        return ranks
    return r

ampere.set_backend("arkouda")
connect(server=HOST, port=PORT)
try:
    ak.clear()
except Exception:
    pass
topo, resolver = topo_gen(T, RPN), resolver_gen(T, RPN)
s = time.time()
ens = Ensemble.from_trace_paths_parquet([PQ_DIR], node_ranks=topo, metric_configs=CFG)
read_s = time.time() - s
s = time.time()
ens.attribute(METRIC, topology_resolver=resolver, strategy=STRATEGY)
attr_s = time.time() - s
with open(OUT_JSON, "w") as f:
    f.write(json.dumps({"read_seconds": read_s, "attribute_seconds": attr_s}))
print(f"trial ok: read={read_s:.2f}s attr={attr_s:.2f}s", flush=True)
'''


def main(cfg_path):
    cfg = json.loads(Path(cfg_path).read_text())

    workflow_dir   = Path(cfg["workflow_dir"])
    timings_dir    = Path(cfg["timings_dir"]);   timings_dir.mkdir(parents=True, exist_ok=True)
    server_log_dir = Path(cfg["server_log_dir"]); server_log_dir.mkdir(parents=True, exist_ok=True)
    logfile        = cfg["log_file"]
    metric         = cfg["metric"]
    strategy       = cfg["strategy"]
    num_trials     = int(cfg["num_trials"])
    rpn            = int(cfg["ranks_per_node"])
    wait_timeout   = int(cfg.get("server_wait_timeout", 1800))
    trial_timeout  = int(cfg.get("trial_timeout", 3600))
    profile        = cfg["arkouda_profile"]
    launch_script  = cfg["launch_script"]
    ark_cpus       = cfg["arkouda_cpus"]
    ark_walltime   = cfg["arkouda_walltime"]
    ark_heap       = cfg["arkouda_heap"]
    slurm_account  = cfg.get("slurm_account")
    env            = cfg.get("env", {})
    configs        = cfg["configs"]

    # Record our PID so the notebook can monitor / kill this detached process.
    Path(cfg["pid_file"]).write_text(str(os.getpid()) + "\n")

    # Reproduce the notebook's apptainer / e4s-cl environment so e4s-cl + launch_arkouda.sh work.
    if env.get("APPTAINER_CACHEDIR"):
        os.environ["APPTAINER_CACHEDIR"] = env["APPTAINER_CACHEDIR"]
    path_add = [p for p in (env.get("go_dir") and os.path.join(env["go_dir"], "bin"),
                            env.get("apptainer_bin_path")) if p]
    if path_add:
        os.environ["PATH"] = os.environ.get("PATH", "") + os.pathsep + os.pathsep.join(path_add)
    if env.get("go_dir"):
        os.environ["LD_LIBRARY_PATH"] = (os.environ.get("LD_LIBRARY_PATH", "") + os.pathsep
                                         + os.path.join(env["go_dir"], "lib"))

    os.chdir(workflow_dir)   # so `import workflows` resolves and relative paths behave
    # This PARENT process never connects to arkouda itself: each analysis trial runs in a child
    # process (ampere_trial_driver.py) so a hung read/attribute can be hard-killed on timeout.

    def launch_cmd(n):
        parts = [launch_script, "-N", str(n), "-c", str(ark_cpus),
                 "-t", ark_walltime, "--heap-size", ark_heap]
        if slurm_account:
            parts += ["-A", slurm_account]
        return parts

    log(f"detached arkouda collection started (pid={os.getpid()}) -- {len(configs)} config(s)",
        logfile)
    # launch_arkouda.sh uses the SELECTED e4s-cl profile, so make ours current up front.
    subprocess.run(f"e4s-cl profile select {profile}", shell=True)

    # Write the child trial driver once for this run (see TRIAL_DRIVER_SRC).
    trial_driver = timings_dir.parent / "ampere_trial_driver.py"
    trial_driver.write_text(TRIAL_DRIVER_SRC)

    failures = []   # (trace, nodes, short_reason) for a final summary

    for c in configs:
        t, n = c["trace_traced_nodes"], c["analysis_nodes"]
        pq_dir = c["pq_dir"]
        out_csv = timings_dir / f"arkouda_s{t}_n{n}.csv"
        if out_csv.exists():
            log(f"[skip] arkouda s{t} n{n} already collected -> {out_csv.name}", logfile)
            continue

        rows = []
        try:
            subprocess.run("scancel --me --name arkouda-server", shell=True)
            time.sleep(5)
            log(f"[arkouda s{t} n{n}] launching server ({n} nodes)", logfile)
            # Capture launch_arkouda.sh output so we can grab the Slurm job ID (it prints
            # "Job ID: NNN"); still echo it so the banner stays in the detached log.
            _lp = subprocess.run(launch_cmd(n), cwd=server_log_dir, check=True,
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            _launch_out = _lp.stdout.decode(errors="ignore")
            print(_launch_out, flush=True)
            _m = re.search(r"Job ID:\s*(\d+)", _launch_out)
            server_job_id = _m.group(1) if _m else None

            # Wait for the server to come up -- but FAIL FAST if its Slurm job dies before it
            # ever listens (multi-node startup / fabric-registration / OOM failures otherwise
            # would burn the full wait_timeout doing nothing). We conclude "died" once the job
            # has been SEEN in the queue and then either left it OR entered a terminal state.
            url, waited, seen_in_queue = None, 0, False
            while url is None and waited < wait_timeout:
                time.sleep(10); waited += 10
                state = server_job_state(server_job_id) if server_job_id else ""
                if state:
                    seen_in_queue = True
                url = arkouda_server_url(server_log_dir)
                if url is not None:
                    break
                _left_queue = seen_in_queue and not state
                if server_job_id and (_left_queue or state in TERMINAL_JOB_STATES):
                    _tail = server_log_tail(server_log_dir, server_job_id, n=40)
                    raise ServerStartupError(
                        classify_failure(_tail),
                        f"arkouda server job {server_job_id} died before it listened "
                        f"(state={state or 'left-queue'}).\n\nServer log tail:\n{_tail}",
                        server_job_id)
            if url is None:
                raise ServerStartupError(
                    f"server never listened within {wait_timeout}s",
                    f"arkouda server job {server_job_id} did not print a listening URL within "
                    f"{wait_timeout}s.\n\nServer log tail:\n"
                    f"{server_log_tail(server_log_dir, server_job_id, n=40)}",
                    server_job_id)
            host, port = url

            for trial in range(1, num_trials + 1):
                # Run each trial in a CHILD PROCESS with a hard timeout. Killing the arkouda server
                # does NOT unblock a hung ZMQ client recv, so the only reliable way to abort a
                # stalled read/attribute is to kill the process running it. On timeout we SIGKILL
                # the child (subprocess.run does this) + cancel the server, then record the config
                # as failed and move on to the next one.
                out_json = timings_dir / f".trial_s{t}_n{n}_{trial}.json"
                if out_json.exists():
                    out_json.unlink()
                child_env = dict(os.environ, AMP_HOST=host, AMP_PORT=str(port), AMP_PQ_DIR=pq_dir,
                                 AMP_TRACED_NODES=str(t), AMP_RPN=str(rpn), AMP_METRIC=metric,
                                 AMP_STRATEGY=strategy, AMP_OUT_JSON=str(out_json))
                try:
                    cp = subprocess.run([sys.executable, str(trial_driver)], env=child_env,
                                        timeout=trial_timeout, stdout=subprocess.PIPE,
                                        stderr=subprocess.STDOUT)
                except subprocess.TimeoutExpired:
                    log(f"[arkouda s{t} n{n}] trial {trial} exceeded {trial_timeout}s -- killed the "
                        f"trial process + server job {server_job_id} (hung analysis)", logfile)
                    subprocess.run("scancel --me --name arkouda-server", shell=True)
                    raise TimeoutError(
                        f"analysis trial {trial} hung past trial_timeout={trial_timeout}s "
                        f"(watchdog killed the trial subprocess)")
                _cout = cp.stdout.decode(errors="ignore") if cp.stdout else ""
                if cp.returncode != 0 or not out_json.exists():
                    raise RuntimeError(
                        f"trial {trial} subprocess failed (rc={cp.returncode}). Output tail:\n"
                        f"{_cout[-2000:]}")
                _r = json.loads(out_json.read_text())
                out_json.unlink()
                rows.append(dict(pipeline="fastotf2+arkouda", backend="arkouda",
                                 trace_traced_nodes=t, analysis_nodes=n, trial=trial,
                                 read_seconds=_r["read_seconds"],
                                 attribute_seconds=_r["attribute_seconds"],
                                 status="ok", error=""))
                log(f"[arkouda s{t} n{n}] trial {trial}: read={_r['read_seconds']:.2f}s "
                    f"attr={_r['attribute_seconds']:.2f}s", logfile)
        except Exception as e:
            if isinstance(e, ServerStartupError):
                reason, detail = e.reason, e.detail
            else:
                reason, detail = classify_failure(repr(e)), repr(e)
            # Full detail (server-log tail / traceback) goes to a per-config side file so the
            # CSV + log stay scannable; the CSV keeps only the SHORT reason.
            fail_log = timings_dir / f"arkouda_s{t}_n{n}.fail.log"
            try:
                fail_log.write_text(f"config : arkouda s{t} n{n}\nreason : {reason}\n\n{detail}\n")
            except Exception:
                pass
            failures.append((t, n, reason))
            # Loud, scannable banner so failures are easy to spot in the log; the run CONTINUES.
            log("!" * 78, logfile)
            log(f"!! CONFIG FAILED: arkouda s{t} n{n}   ({len(failures)} failure(s) so far)", logfile)
            log(f"!! reason : {reason}", logfile)
            log(f"!! detail : {fail_log}", logfile)
            log("!! -> recorded as status=failed; CONTINUING with the next config.", logfile)
            log("!" * 78, logfile)
            rows.append(dict(pipeline="fastotf2+arkouda", backend="arkouda",
                             trace_traced_nodes=t, analysis_nodes=n, trial=0,
                             read_seconds=np.nan, attribute_seconds=np.nan,
                             status="failed", error=reason))
        finally:
            subprocess.run("scancel --me --name arkouda-server", shell=True)
            time.sleep(5)

        pd.DataFrame(rows, columns=TIMING_COLUMNS).to_csv(out_csv, index=False)
        log(f"[done] arkouda s{t} n{n} -> {out_csv.name}", logfile)

    log("=" * 78, logfile)
    if failures:
        log(f"detached arkouda collection COMPLETE -- {len(failures)} config(s) FAILED:", logfile)
        for t, n, reason in failures:
            log(f"   - s{t} n{n}: {reason}", logfile)
        log("   (full dumps: timings/arkouda_s<t>_n<n>.fail.log; rows tagged status=failed)",
            logfile)
    else:
        log("detached arkouda collection COMPLETE -- all configs OK.", logfile)
    log("=" * 78, logfile)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: python ampere_collect.py <config.json>", file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1])
