from io import StringIO
import importlib.util
import os, stat, subprocess
import ipywidgets as widgets
from ipywidgets import HBox, Layout, Box
from IPython.display import display, DisplayHandle
import subprocess
import threading
import time
import shlex
import select
import re
from generate_container_filename import generate_filename

workflowScriptDir = os.path.dirname(os.path.realpath(__file__))
workflow_log = None

class SafeDisplay:
    def __init__(self, display_handle: DisplayHandle | None = None):
        self.display_handle = display_handle
        self.display_buffer = StringIO()
        self.display_buffer_lock = threading.Lock()
        self.max_display_chars = 1_000_000
        self.total_truncated_chars = 0

    def update_display(self):
        if self.display_handle is None:
            return

        with self.display_buffer_lock:
            # If output exceeds threshold, drop the oldest data (keep half).
            current_size = self.display_buffer.tell()
            if current_size > self.max_display_chars:
                keep_chars = self.max_display_chars // 2
                chars_to_trim = current_size - keep_chars
                self.total_truncated_chars += chars_to_trim

                self.display_buffer.seek(chars_to_trim)
                remaining_content = self.display_buffer.read()

                self.display_buffer.seek(0)
                self.display_buffer.truncate(0)
                self.display_buffer.write(f"[Output truncated total={self.total_truncated_chars} chars]\n")
                self.display_buffer.write(remaining_content)

            self.display_handle.update({'text/plain': self.display_buffer.getvalue()}, raw=True)

    def new_thread_buffer(self, flush_interval: float = 3.0) -> 'ThreadBuffer':
        return ThreadBuffer(self, flush_interval)


class ThreadBuffer:
    """Per-thread output buffer that rate-limits flushes to a SafeDisplay.

    Calls to write() accumulate data locally and only push to the shared
    SafeDisplay when at least *flush_interval* seconds have elapsed since the
    last flush.  Call flush() to force an immediate push regardless of the
    timer.
    """

    def __init__(self, safe_display: SafeDisplay, flush_interval: float = 1.0):
        self._local_buffer = StringIO()
        self._safe_display = safe_display
        self._flush_interval = flush_interval
        self._last_flush = time.monotonic()

    def write(self, data: str):
        self._local_buffer.write(data)
        if time.monotonic() - self._last_flush >= self._flush_interval:
            self.flush()

    def flush(self):
        content = self._local_buffer.getvalue()
        if not content:
            return
        self._local_buffer.seek(0)
        self._local_buffer.truncate(0)
        self._last_flush = time.monotonic()
        with self._safe_display.display_buffer_lock:
            self._safe_display.display_buffer.write(content)
        self._safe_display.update_display()


class StopExecution(Exception):
    def _render_traceback_(self):
        return []

def set_workflow_log(log_path):
    global workflow_log
    workflow_log = log_path
    log_dir = os.path.dirname(os.path.abspath(workflow_log))
    os.makedirs(log_dir, exist_ok=True)
    os.chdir(log_dir)
    open(workflow_log, 'w').close()
    log(f"Workflow started at {time.ctime()}")
    log(f"> cd {log_dir}")

def log(msg):
    with open(workflow_log, 'a') as f:
        f.write(f'{msg}\n')

def print_and_log(msg):
    print(msg)
    log(msg)

def run_cmd(cmd):
    if isinstance(cmd, str):
        args = shlex.split(cmd)
    else:
        args = list(cmd)
    print_and_log(f"> {cmd}")
    subprocess.run(args, check=True)

def run_in_container(cmd, container, additional_apptainer_args=''):
    curDir = os.getcwd()
    args = shlex.split(f"apptainer exec --no-home --bind {curDir}:{curDir} --pwd {curDir} {additional_apptainer_args} {container} bash -lc")
    args.append(cmd)
    run_cmd(args)

def cd(dir):
    log(f'> cd {dir}')
    os.chdir(dir)

def download_custom_container(container_uri, force=False, method="podman"):
    """Fetch container_uri as a local .sif file.

    method="podman" (default) converts via podman + convert-to-sif.sh -- needs a working
    podman install. method="apptainer" pulls directly with `apptainer pull`, no podman
    required (e.g. on systems like Frontier where podman isn't usable)."""
    containerName = generate_filename(container_uri) + '.sif'
    if not force and os.path.exists(containerName):
        print(f"Container {containerName} already exists, skipping download.")
        return containerName
    if method == "apptainer":
        pull_uri = container_uri if "://" in container_uri else f"docker://{container_uri}"
        cmd = ["apptainer", "pull"]
        if force:
            cmd.append("--force")
        cmd += [containerName, pull_uri]
        run_cmd(cmd)
    else:
        run_cmd(f"{workflowScriptDir}/convert-to-sif.sh {container_uri}")
    return containerName

def download_sst_container(version, force=False):
    return download_custom_container(f'ghcr.io/hpc-ai-adv-dev/sst-core:{version}', force=force)

def launch_and_log_sst(image, srun_args, sst_args, log_file, config_path=None, safe_display: SafeDisplay | None = None, depends_on=None):
    def readAndLog(output_file, safe_display, depends_on, cwd):
        if depends_on is not None:
            depends_on.join()

        print_and_log(f'> {cmd}')
        process = subprocess.Popen(cmd, shell=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=False, cwd=cwd)
        if process.stdout is None:
            raise RuntimeError('Failed to capture subprocess stdout')

        fd = process.stdout.fileno()
        pending = ''
        thread_buf = safe_display.new_thread_buffer()

        with open(output_file, 'w') as f:
            while True:
                # Poll stdout with timeout so this thread can yield when there is no output.
                ready, _, _ = select.select([fd], [], [], 0.2)

                if ready:
                    chunk = os.read(fd, 4096)
                    if not chunk:
                        break

                    pending += chunk.decode(errors='replace')
                    linesPrinted = 0
                    while '\n' in pending:
                        line, pending = pending.split('\n', 1)
                        line = line + '\n'
                        f.write(line)
                        f.flush()
                        linesPrinted += 1

                        thread_buf.write(line)

                if process.poll() is not None and not ready:
                    break

                # Explicit thread yield
                time.sleep(0)

            if pending:
                f.write(pending)
                f.flush()
                thread_buf.write(pending)

            thread_buf.flush()

        process.wait()

    if not os.path.exists(image):
        raise FileNotFoundError(f"SST image not found: {image}")

    cmd = f'e4s-cl launch --image {image} srun {srun_args} -- sst {sst_args}'
    if config_path:
        cmd = f'SST_CONFIG_FILE_PATH={config_path} {cmd}'
    log_thread = threading.Thread(target=readAndLog, args=(
        log_file, safe_display, depends_on, os.getcwd()), daemon=True)
    log_thread.start()
    return log_thread


def inspect_logs(log_dir):
    #!find ./runs -type f | xargs realpath | sort -V
    import re, os
    from pathlib import Path

    _number_re = re.compile(r'(\d+)')
    def naturalSort(items):
        def natural_key(s: str):
            parts = _number_re.split(s)
            return [int(p) if p.isdigit() else p.lower() for p in parts]

        if not isinstance(items, list):
            items = list(items)
        items.sort(key=lambda p: (natural_key(p.name), str(p)))
        return items

    allFiles = []
    for dir in (Path(log_dir), *naturalSort(filter(Path.is_dir, Path(log_dir).iterdir()))):
        for file in naturalSort(dir.iterdir()):
            if file.is_file():
                allFiles.append(file)
                print(file)
    print()

    #for file in allFiles:
    #    print("=" * 80)
    #    print(file)
    #    print("=" * 80)
    #    print(open(file).read())
    #    print()

stop_squeue = threading.Event()
squeue_thread = None
def watch_queue_widget(interval=2.0):
    """Live queue monitor -- richer than `watch squeue --me`.

    Jobs are sorted (RUNNING first, longest-running on top; then PENDING by estimated start
    time; then everything else) and rendered as a scrollable, colour-coded table:
      * RUNNING  -> time USED, walltime LIMIT, and time LEFT (green)
      * PENDING  -> estimated START clock + a live countdown, plus the scheduler REASON (amber)
    A summary header shows counts, nodes in use, and the next estimated start. `interval` is
    the refresh period in seconds (also changeable live via the dropdown)."""
    import html as _html
    from datetime import datetime as _dt

    def _ts(s):
        try:
            return _dt.strptime(s, "%Y-%m-%dT%H:%M:%S")
        except Exception:
            return None

    def _dur_to_s(t):
        if not t or t in ("UNLIMITED", "INVALID", "NOT_SET", "N/A", ""):
            return None
        days = 0
        if "-" in t:
            d, t = t.split("-", 1)
            days = int(d)
        p = [int(x) for x in t.split(":")]
        while len(p) < 3:
            p.insert(0, 0)
        return days * 86400 + p[-3] * 3600 + p[-2] * 60 + p[-1]

    def _fmt_s(secs):
        if secs is None:
            return "?"
        neg = secs < 0
        secs = abs(int(secs))
        d, r = divmod(secs, 86400)
        h, r = divmod(r, 3600)
        m, s = divmod(r, 60)
        out = f"{d}d{h}h" if d else (f"{h}h{m:02d}m" if h else f"{m}m{s:02d}s")
        return ("-" + out) if neg else out

    def _collect():
        fmt = "%i|%j|%T|%M|%l|%D|%Q|%r|%S"
        cmd = ["squeue", "-h", "-o", fmt] + (["--me"] if cb_just_me.value else [])
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            return None, (res.stderr.strip() or f"rc={res.returncode}")
        rows = []
        for line in res.stdout.splitlines():
            f = line.split("|")
            if len(f) < 9:
                continue
            rows.append(dict(jid=f[0], name=f[1], st=f[2], elapsed=f[3], tlimit=f[4],
                             nodes=f[5], prio=f[6], reason=f[7], start=f[8]))
        return rows, None

    def _render():
        rows, err = _collect()
        now = _dt.now()
        stamp = now.strftime("%H:%M:%S")
        scope = "my" if cb_just_me.value else "all"
        BG, FG, MUTE, ACC = "#12141c", "#d6d9e0", "#8b93a7", "#9ecbff"
        RUN_C, WAIT_C, OTHER_C = "#4caf50", "#ffb74d", "#9e9e9e"

        def _wrap(inner):
            return (f"<div style='font-family:ui-monospace,SFMono-Regular,Menlo,monospace;"
                    f"font-size:12px;background:{BG};color:{FG};padding:10px;border-radius:6px;"
                    f"max-height:480px;overflow:auto'>{inner}</div>")

        if err is not None:
            return _wrap(f"<span style='color:#ff6b6b'>squeue error: {_html.escape(err)}</span>")

        def _tbl(title, tcolor, headers, rowvals):
            if not rowvals:
                return ""
            th = "".join(f"<th style='text-align:left;padding:3px 14px 3px 0;color:{MUTE};"
                         f"font-weight:normal;border-bottom:1px solid #2c3040'>{h}</th>"
                         for h in headers)
            body = ""
            for cells in rowvals:
                tds = "".join(f"<td style='padding:3px 14px 3px 0;white-space:nowrap'>"
                              f"{_html.escape(str(c))}</td>" for c in cells)
                body += f"<tr>{tds}</tr>"
            dot = f"<span style='color:{tcolor}'>&#9679;</span> "
            return (f"<div style='margin:10px 0 3px;font-weight:bold;color:{tcolor}'>{dot}{title}</div>"
                    f"<table style='border-collapse:collapse'><tr>{th}</tr>{body}</table>")

        run = [r for r in rows if r["st"] == "RUNNING"]
        pend = [r for r in rows if r["st"] == "PENDING"]
        other = [r for r in rows if r["st"] not in ("RUNNING", "PENDING")]

        # RUNNING: longest-running first.
        run.sort(key=lambda r: (_ts(r["start"]).timestamp() if _ts(r["start"]) else 0.0))
        run_rows = []
        for r in run:
            es, ls = _dur_to_s(r["elapsed"]), _dur_to_s(r["tlimit"])
            left = _fmt_s(ls - es) if (es is not None and ls is not None) else "?"
            run_rows.append([r["jid"], r["name"][:28], r["nodes"], r["elapsed"], r["tlimit"], left])

        # WAITING: highest priority first (that's the order they'll actually start).
        pend.sort(key=lambda r: -int(r["prio"]) if r["prio"].isdigit() else 0)
        wait_rows = []
        for r in pend:
            t = _ts(r["start"])
            when = t.strftime("%m-%d %H:%M") if t else "unknown"
            countdown = _fmt_s((t - now).total_seconds()) if t else "—"
            wait_rows.append([r["jid"], r["name"][:28], r["nodes"], r["prio"],
                              when, countdown, r["reason"]])

        other.sort(key=lambda r: r["st"])
        other_rows = [[r["jid"], r["name"][:28], r["st"], r["nodes"], r["reason"]] for r in other]

        run_nodes = sum(int(r["nodes"]) for r in run if r["nodes"].isdigit())
        pend_starts = [t for t in (_ts(r["start"]) for r in pend) if t]
        nxt = min(pend_starts).strftime("%m-%d %H:%M") if pend_starts else "n/a (deps/limits)"
        summary = (f"<span style='color:{ACC};font-weight:bold'>{stamp}</span> "
                   f"<span style='color:{MUTE}'>({scope} jobs)</span> &nbsp; "
                   f"<span style='color:{RUN_C}'>&#9679; {len(run)} running</span> "
                   f"<span style='color:{MUTE}'>({run_nodes} nodes)</span> &nbsp; "
                   f"<span style='color:{WAIT_C}'>&#9679; {len(pend)} waiting</span> &nbsp; "
                   f"<span style='color:{MUTE}'>next start: {nxt}</span>"
                   + ("  <b style='color:#ff6b6b'>[STOPPED]</b>" if stop_squeue.is_set() else ""))

        if not rows:
            return _wrap(summary + "<div style='margin-top:8px;color:#8b93a7'>(no jobs in queue)</div>")

        parts = [summary]
        parts.append(_tbl("RUNNING now — newest at bottom, time left to walltime", RUN_C,
                          ["job id", "name", "nodes", "elapsed", "walltime", "time left"], run_rows))
        parts.append(_tbl("WAITING to start — highest priority first (order they'll run)", WAIT_C,
                          ["job id", "name", "nodes", "priority", "est. start", "starts in",
                           "waiting on"], wait_rows))
        parts.append(_tbl("Other states", OTHER_C,
                          ["job id", "name", "state", "nodes", "reason"], other_rows))
        return _wrap("".join(parts))

    def squeue_update_thread():
        while not stop_squeue.is_set():
            out.value = _render()
            time.sleep(max(0.5, float(dd_interval.value)))
        out.value = _render()

    def on_btn_start(b):
        global squeue_thread
        stop_squeue.clear()
        if squeue_thread is None or not squeue_thread.is_alive():
            squeue_thread = threading.Thread(target=squeue_update_thread, daemon=True)
            squeue_thread.start()

    def on_force_refresh(b):
        out.value = _render()

    def on_btn_stop(b):
        stop_squeue.set()

    def on_btn_force_kill(b):
        run_cmd('scancel --me')

    stop_squeue.set()

    btn_start      = widgets.Button(description='Start', button_style='primary', icon='play')
    btn_stop       = widgets.Button(description='Stop',  button_style='danger', icon='stop')
    btn_refresh    = widgets.Button(description='Force Update', button_style='info', icon='refresh')
    btn_force_kill = widgets.Button(description='Force Kill', button_style='danger', icon='eject')
    cb_just_me     = widgets.Checkbox(description='My jobs only', value=True, disabled=False)
    dd_interval    = widgets.Dropdown(options=[1, 2, 5, 10], value=int(interval) if int(interval) in (1, 2, 5, 10) else 2,
                                      description='every (s)', style={'description_width': 'initial'},
                                      layout=Layout(width='140px'))

    btn_start.on_click(on_btn_start)
    btn_stop.on_click(on_btn_stop)
    btn_refresh.on_click(on_force_refresh)
    btn_force_kill.on_click(on_btn_force_kill)
    cb_just_me.observe(lambda ch: on_force_refresh(None) if ch['name'] == 'value' else None)

    controls = HBox(
        [btn_start, btn_stop, btn_refresh, dd_interval, Box(layout=Layout(flex='1 1 auto')),
         cb_just_me, btn_force_kill],
        layout=Layout(display='flex', flex_flow='row', align_items='center', gap='8px'))
    out = widgets.HTML(value="<div style='font-family:monospace'>Idle — press Start</div>")
    display(controls, out)

def wait_until_my_jobs_finished():
    wait = True
    while wait:
        #check queue length
        result = subprocess.run(f'squeue --me | wc -l', shell=True, capture_output=True, text=True)
        queue_length = int(result.stdout.strip())
        if queue_length == 1: # there's always the header line
            wait = False
        else:
            time.sleep(5)

sst_output_data_regexps = {
    "total_duration": r"^[^\n]*\btotal\b\s*\n[^\n]*Duration:\s*([\d.]+)\s*seconds",
    "total_memory": r"^[^\n]*\btotal\b\s*\n(?:[^\n]*\n)?[^\n]*Memory:\s*Total\s*-\s*([\d.]+)\s*(KB|MB|GB|TB)",
    "build_duration": r"^[^\n]*\bbuild\b\s*\n[^\n]*Duration:\s*([\d.]+)\s*seconds",
    "build_memory": r"^[^\n]*\bbuild\b\s*\n(?:[^\n]*\n)?[^\n]*Memory:\s*Total\s*-\s*([\d.]+)\s*(KB|MB|GB|TB)",
    "graph_processing_duration": r"^[^\n]*\bgraph-processing\b\s*\n[^\n]*Duration:\s*([\d.]+)\s*seconds",
    "graph_processing_memory": r"^[^\n]*\bgraph-processing\b\s*\n(?:[^\n]*\n)?[^\n]*Memory:\s*Total\s*-\s*([\d.]+)\s*(KB|MB|GB|TB)",
    "construct_duration": r"^[^\n]*\bconstruct\b\s*\n[^\n]*Duration:\s*([\d.]+)\s*seconds",
    "construct_memory": r"^[^\n]*\bconstruct\b\s*\n(?:[^\n]*\n)?[^\n]*Memory:\s*Total\s*-\s*([\d.]+)\s*(KB|MB|GB|TB)",
    "execute_time": r"^[^\n]*\bexecute\b\s*\n[^\n]*Duration:\s*([\d.]+)\s*seconds",
    "execute_memory": r"^[^\n]*\bexecute\b\s*\n(?:[^\n]*\n)?[^\n]*Memory:\s*Total\s*-\s*([\d.]+)\s*(KB|MB|GB|TB)",
    "init_duration": r"^[^\n]*\binit\b\s*\n[^\n]*Duration:\s*([\d.]+)\s*seconds",
    "init_memory": r"^[^\n]*\binit\b\s*\n(?:[^\n]*\n)?[^\n]*Memory:\s*Total\s*-\s*([\d.]+)\s*(KB|MB|GB|TB)",
    "setup_duration": r"^[^\n]*\bsetup\b\s*\n[^\n]*Duration:\s*([\d.]+)\s*seconds",
    "setup_memory": r"^[^\n]*\bsetup\b\s*\n(?:[^\n]*\n)?[^\n]*Memory:\s*Total\s*-\s*([\d.]+)\s*(KB|MB|GB|TB)",
    "run_duration": r"^[^\n]*\brun\b\s*\n[^\n]*Duration:\s*([\d.]+)\s*seconds",
    "run_memory": r"^[^\n]*\brun\b\s*\n(?:[^\n]*\n)?[^\n]*Memory:\s*Total\s*-\s*([\d.]+)\s*(KB|MB|GB|TB)",
    "complete_duration": r"^[^\n]*\bcomplete\b\s*\n[^\n]*Duration:\s*([\d.]+)\s*seconds",
    "complete_memory": r"^[^\n]*\bcomplete\b\s*\n(?:[^\n]*\n)?[^\n]*Memory:\s*Total\s*-\s*([\d.]+)\s*(KB|MB|GB|TB)",
    "finish_duration": r"^[^\n]*\bfinish\b\s*\n[^\n]*Duration:\s*([\d.]+)\s*seconds",
    "finish_memory": r"^[^\n]*\bfinish\b\s*\n(?:[^\n]*\n)?[^\n]*Memory:\s*Total\s*-\s*([\d.]+)\s*(KB|MB|GB|TB)",
    "simulated_time": r"^\s*Simulated\s+time:\s*([\d.]+)\s*(s|ms|us|ns|ps)\s*$",
    "max_resident_set_size": r"^\s*Max Resident Set Size:\s*([\d.]+)\s*(B|KB|MB|GB|TB)\s*$",
    "approx_global_max_rss_size": r"^\s*Approx\.\s*Global\s*Max\s*RSS\s*Size:\s*([\d.]+)\s*(B|KB|MB|GB|TB)\s*$",
    "max_local_page_faults": r"^\s*Max Local Page Faults:\s*(\d+)\s*faults\s*$",
    "global_page_faults": r"^\s*Global Page Faults:\s*(\d+)\s*faults\s*$",
    "max_output_blocks": r"^\s*Max Output Blocks:\s*(\d+)\s*blocks\s*$",
    "max_input_blocks": r"^\s*Max Input Blocks:\s*(\d+)\s*blocks\s*$",
    "max_mempool_usage": r"^\s*Max mempool usage:\s*([\d.]+)\s*(B|KB|MB|GB|TB)\s*$",
    "global_mempool_usage": r"^\s*Global mempool usage:\s*([\d.]+)\s*(B|KB|MB|GB|TB)\s*$",
    "global_active_activities": r"^\s*Global active activities:\s*(\d+)\s*activities\s*$",
    "current_global_timevortex_depth": r"^\s*Current global TimeVortex depth:\s*(\d+)\s*entries\s*$",
    "max_timevortex_depth": r"^\s*Max TimeVortex depth:\s*(\d+)\s*entries\s*$",
    "max_sync_data_size": r"^\s*Max Sync data size:\s*([\d.]+)\s*(B|KB|MB|GB|TB)\s*$",
    "global_sync_data_size": r"^\s*Global Sync data size:\s*([\d.]+)\s*(B|KB|MB|GB|TB)\s*$",
}

def _extract_data_from_sst_output(file):
    with open(file, "r") as f:
        content = f.read()

    row = {"file": str(file)}
    for field_name, pattern in sst_output_data_regexps.items():
        match = re.search(pattern, content, re.IGNORECASE | re.MULTILINE)
        if match:
            groups = match.groups()
            if len(groups) == 2:
                row[field_name] = (float(groups[0]), groups[1].upper())
            else:
                number_text = groups[0]
                if number_text.isdigit():
                    row[field_name] = int(number_text)
                else:
                    row[field_name] = float(number_text)
        else:
            row[field_name] = ""
            print(f"  {field_name}: not found")

    return row

def extract_sst_output_in_files(filesIter):
    results = []
    for file in filesIter:
        row = _extract_data_from_sst_output(file)
        results.append(row)

    return results

def convert_to_csv(data):
    """Convert extracted data to CSV format, normalizing byte-sized values to bytes."""
    if not data:
        return []

    byte_multipliers = {
        "B": 1,
        "KB": 1024,
        "MB": 1024**2,
        "GB": 1024**3,
        "TB": 1024**4,
    }

    query_fields = list(sst_output_data_regexps.keys())
    csv_lines = ["Size," + ",".join(query_fields)]
    csv_entries = {}
    for row in data:
        file = row.get("file", "")
        # Extract size value (may be number of nodes or components depending on context) from filename (e.g., 'size_1' -> '1').
        size_match = re.search(r"size_(\d+)", file)
        if size_match:
            size = int(size_match.group(1))
            values = []
            for field_name in query_fields:
                value = row.get(field_name, "")
                if isinstance(value, tuple) and len(value) == 2:
                    number, unit = value
                    unit = str(unit).upper()
                    if unit in byte_multipliers:
                        values.append(str(number * byte_multipliers[unit]))
                    else:
                        values.append(str(number))
                else:
                    values.append(str(value))
            csv_entries[size] = f"{size}," + ",".join(values)

    for size in sorted(csv_entries.keys()):
        csv_lines.append(csv_entries[size])

    return csv_lines


def _load_user_workflows():
    user_workflows_path = os.path.expanduser("~/.workflows.py")
    if not os.path.isfile(user_workflows_path):
        print("No user workflows file found at ~/.workflows.py, skipping.")
        return

    spec = importlib.util.spec_from_file_location("_user_workflows", user_workflows_path)
    if spec is None or spec.loader is None:
        print(f"Warning: unable to load user workflows from {user_workflows_path}")
        return

    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except Exception as exc:
        print(f"Warning: failed to import user workflows from {user_workflows_path}: {exc}")
        return

    if hasattr(module, "__all__"):
        export_names = [name for name in module.__all__ if isinstance(name, str)]
    else:
        export_names = [name for name in dir(module) if not name.startswith("_")]

    for name in export_names:
        if hasattr(module, name):
            globals()[name] = getattr(module, name)


_load_user_workflows()