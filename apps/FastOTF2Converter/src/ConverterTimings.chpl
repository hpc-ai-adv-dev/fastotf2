// Copyright Hewlett Packard Enterprise Development LP.
//
// Timing infrastructure for the converter.
// Provides records for collecting per-phase and per-task timing data,
// column-descriptor methods for auto-generated pretty-print and CSV output,
// and a formatted report printer. Opt-in via --timings / --timings-csv flags.

module ConverterTimings {
  use IO;
  use FileSystem;
  use Path;
  use Time;
  use ConverterCommon;

  // -------------------------------------------------------------------------
  // TaskTiming — per-task timing data collected inside coforall
  // -------------------------------------------------------------------------

  record TaskTiming {
    var taskId: uint;
    var localeId: int;
    var locations: uint;
    var eventsRead: uint;
    var openTime: real;              // from ReadResult
    var setupTime: real;             // from ReadResult
    var readTime: real;              // from ReadResult
    var enterCallbackTime: real;     // from EvtCallbackContext
    var leaveCallbackTime: real;     // from EvtCallbackContext
    var metricCallbackTime: real;    // from EvtCallbackContext
    // Write times only for strategies that write per-task, otherwise 0
    var writeTime: real;             // from WriteResult (total)
    var callgraphWriteTime: real;    // from WriteResult
    var metricsWriteTime: real;      // from WriteResult
    var totalTime: real;             // wall-clock for the entire task body
  }

  // -------------------------------------------------------------------------
  // Column descriptors — single source of truth for both CSV and pretty-print
  // -------------------------------------------------------------------------

  // Number of timing columns (real-valued)
  param numTimingColumns = 13;

  // Minimum column width for formatted output
  param minColumnWidth = 10;

  proc timingColumnNames(): numTimingColumns * string {
    return ("Open (s)", "Setup (s)", "EnterCB (s)", "LeaveCB (s)", "MetricCB (s)",
            "CBTotal (s)", "libOTF2 (s)", "ReadTotal (s)", "CBPct (%)",
            "WriteCG (s)", "WriteMet (s)", "WriteTot (s)", "Total (s)");
  }

  proc TaskTiming.timingColumnValues(): numTimingColumns * real {
    const cbTotal = enterCallbackTime + leaveCallbackTime + metricCallbackTime;
    const otf2Time = readTime - cbTotal;
    const cbPct = if readTime > 0.0 then 100.0 * cbTotal / readTime else 0.0;
    return (openTime, setupTime, enterCallbackTime, leaveCallbackTime,
            metricCallbackTime, cbTotal, otf2Time, readTime, cbPct,
            callgraphWriteTime, metricsWriteTime, writeTime, totalTime);
  }

  // Meta columns (identifiers, not timing data)
  param numMetaColumns = 4;

  proc metaColumnNames(): numMetaColumns * string {
    return ("Task", "Locale", "Locations", "Events");
  }

  proc TaskTiming.metaColumnValues(): numMetaColumns * uint {
    return (taskId, localeId: uint, locations, eventsRead);
  }

  // Compute total display width of meta columns area (excluding leading indent)
  proc computeMetaColsWidth(): int {
    const names = metaColumnNames();
    var w = 0;
    for param i in 0..<numMetaColumns {
      if i > 0 then w += 2; // gap between columns
      w += max(names(i).size + 2, minColumnWidth);
    }
    return w;
  }

  // -------------------------------------------------------------------------
  // LocaleTiming
  // -------------------------------------------------------------------------

  record LocaleTiming {
    var numTasks: int;
    var taskTimingDom = {0..<numTasks};
    var taskTimings: [taskTimingDom] TaskTiming;
  }

  // -------------------------------------------------------------------------
  // TimingReport — aggregates all timing data for the final report
  // -------------------------------------------------------------------------

  record TimingReport {
    // Global phases
    var totalTime: real;
    var defOpenTime: real;
    var defSetupTime: real;
    var defReadTime: real;
    var groupMapTime: real;
    var groupDistributionTime: real; // only for strategies with a group distribution phase
    var eventReadWriteTime: real;    // combined time for event reading + callgraph writing
    var evtReadTime: real;           // only for strategies that separate event read from write
    var writeTime: real;             // only for strategies that separate event read from write
    var mergeTime: real;             // only for strategies with a merge phase

    // Per-task data per locale
    var localeTimingData: [0..<numLocales] LocaleTiming;

    // Strategy name for the header
    var strategy: string;

    // Trace path (for CSV output)
    var tracePath: string;
  }

  // -------------------------------------------------------------------------
  // setTaskTimings — populate the report with collected per-task data
  // -------------------------------------------------------------------------

  proc ref TimingReport.setTaskTimings(const ref timings: [] TaskTiming) {
    localeTimingData[here.id] = new LocaleTiming();
    ref locData = localeTimingData[here.id];
    locData.numTasks = timings.size;
    locData.taskTimingDom = {0..<timings.size};
    locData.taskTimings = timings;
  }

  // -------------------------------------------------------------------------
  // print — column-driven formatted timing report
  // -------------------------------------------------------------------------

  proc const ref TimingReport.print() {
    writeln();
    writeln("=== Timing Report (", strategy, ") ===");

    const defTotal = defOpenTime + defSetupTime + defReadTime;
    const otherTime = totalTime - defTotal - groupMapTime - eventReadWriteTime - mergeTime;

    writeln("  Phase                            Time (s)    % Total");
    writeln("  ───────────────────────────────  ──────────  ───────");
    printPhase("Read global definitions", defTotal);
    if groupMapTime > 0.0 then
      printPhase("Build group/location map", groupMapTime);
    if groupDistributionTime > 0.0 then
      printPhase("Distribute groups to readers", groupDistributionTime);
    if evtReadTime > 0.0 then
      printPhase("Read events", evtReadTime);
    if writeTime > 0.0 then
      printPhase("Write output", writeTime);
    if eventReadWriteTime > 0.0 then
      printPhase("Read events + write output", eventReadWriteTime);
    if mergeTime > 0.0 then
      printPhase("Merge contexts", mergeTime);
    if otherTime > 0.0 then
      printPhase("Other (overhead)", otherTime);
    writeln("  ───────────────────────────────  ──────────  ───────");
    printPhase("Total", totalTime);

    // Per-locale, per-task breakdown
    var globalTaskCount = 0;
    for loc in localeTimingData do globalTaskCount += loc.numTasks;

    if globalTaskCount > 0 {
      // Build header and separator dynamically from column descriptors
      const mNames = metaColumnNames();
      const tNames = timingColumnNames();

      var header = "";
      var sep = "";

      // Meta columns
      for param i in 0..<numMetaColumns {
        header += "  ";
        sep += "  ";
        const name = mNames(i);
        const width = max(name.size + 2, minColumnWidth);
        const pad = width - name.size;
        for j in 0..<pad do header += " ";
        header += name;
        for j in 0..<width do sep += "─";
      }

      // Timing columns
      for param i in 0..<numTimingColumns {
        header += "  ";
        sep += "  ";
        const name = tNames(i);
        const width = max(name.size + 2, minColumnWidth);
        const pad = width - name.size;
        for j in 0..<pad do header += " ";
        header += name;
        for j in 0..<width do sep += "─";
      }

      // --- Per-locale sections ---
      for locId in 0..<numLocales {
        ref loc = localeTimingData[locId];
        if loc.numTasks == 0 then continue;

        writeln();
        writeln("┌─ Locale ", locId, " (", loc.numTasks, " tasks) ─────────────────────────────────────────");
        writeln(header);
        writeln(sep);
        for t in loc.taskTimings {
          const meta = t.metaColumnValues();
          for param i in 0..<numMetaColumns {
            const width = max(mNames(i).size + 2, minColumnWidth);
            writef("  %*u", width, meta(i));
          }
          const vals = t.timingColumnValues();
          for param i in 0..<numTimingColumns {
            const width = max(tNames(i).size + 2, minColumnWidth);
            writef("  %*.3dr", width, vals(i));
          }
          writeln();
        }
        writeln(sep);

        // Per-locale summary stats
        printTaskStats(loc.taskTimings, loc.numTasks, "  ");
        writeln("└", sep[2..]);
      }

      // --- Global (all-locale) aggregate stats ---
      if numLocales > 1 {
        writeln();
        writeln("╔═ Global Task Summary (all ", globalTaskCount, " tasks across ", numLocales, " locales) ═══════════");

        // Collect all tasks into flat view for stats
        var allTasks: [0..<globalTaskCount] TaskTiming;
        var idx = 0;
        for loc in localeTimingData {
          for t in loc.taskTimings {
            allTasks[idx] = t;
            idx += 1;
          }
        }
        printTaskStats(allTasks, globalTaskCount, "║ ");

        // Per-locale wall times
        writeln("║");
        writeln("║  Per-Locale Wall Times (max task total = locale wall time):");
        writeln("║   Locale  Tasks  Events      Wall (s)");
        writeln("║   ──────  ─────  ──────────  ────────");
        var minLocWall = max(real), maxLocWall = 0.0, sumLocWall = 0.0;
        var activeLocales = 0;
        for locId in 0..<numLocales {
          ref loc = localeTimingData[locId];
          if loc.numTasks == 0 then continue;
          activeLocales += 1;
          var locEvents: uint(64) = 0;
          var locWall = 0.0;
          for t in loc.taskTimings {
            locEvents += t.eventsRead;
            if t.totalTime > locWall then locWall = t.totalTime;
          }
          if locWall < minLocWall then minLocWall = locWall;
          if locWall > maxLocWall then maxLocWall = locWall;
          sumLocWall += locWall;
          writef("║   %6i  %5i  %10u  %8.3dr",
                 locId, loc.numTasks, locEvents, locWall);
          writeln();
        }
        if activeLocales > 1 {
          const meanLocWall = sumLocWall / activeLocales: real;
          const imbLoc = if meanLocWall > 0.0 then maxLocWall / meanLocWall else 0.0;
          writeln("║   ──────  ─────  ──────────  ────────");
          writef("║   Min: %.3dr  Max: %.3dr  Mean: %.3dr  Imbalance: %.3drx",
                 minLocWall, maxLocWall, meanLocWall, imbLoc);
          writeln();
        }
        writeln("╚══════════════════════════════════════════════════════════════════════════");
      }

      if totalTime > 0.0 {
        var totalEvents: uint(64) = 0;
        for loc in localeTimingData do for t in loc.taskTimings do totalEvents += t.eventsRead;
        writeln();
        writef("  Throughput: %.0dr events/sec\n", totalEvents: real / totalTime);
      }
    }

    writeln("=== End Timing Report ===");
  }

  // -------------------------------------------------------------------------
  // printTaskStats — print min/max/mean/imbalance for a set of tasks
  // -------------------------------------------------------------------------

  proc printTaskStats(const ref tasks, n: int, prefix: string) {
    if n == 0 then return;

    const tNames = timingColumnNames();
    const metaWidth = computeMetaColsWidth();
    var mins: numTimingColumns * real;
    var maxs: numTimingColumns * real;
    var sums: numTimingColumns * real;

    // Initialize from first task
    const firstVals = tasks[0].timingColumnValues();
    for param i in 0..<numTimingColumns {
      mins(i) = firstVals(i);
      maxs(i) = firstVals(i);
      sums(i) = 0.0;
    }

    // Accumulate
    for t in tasks {
      const vals = t.timingColumnValues();
      for param i in 0..<numTimingColumns {
        if vals(i) < mins(i) then mins(i) = vals(i);
        if vals(i) > maxs(i) then maxs(i) = vals(i);
        sums(i) += vals(i);
      }
    }

    const cnt = n: real;

    // Print Min row
    write(prefix);
    writef("%<*s", metaWidth, "Min");
    for param i in 0..<numTimingColumns {
      const width = max(tNames(i).size + 2, minColumnWidth);
      writef("  %*.3dr", width, mins(i));
    }
    writeln();

    // Print Max row
    write(prefix);
    writef("%<*s", metaWidth, "Max");
    for param i in 0..<numTimingColumns {
      const width = max(tNames(i).size + 2, minColumnWidth);
      writef("  %*.3dr", width, maxs(i));
    }
    writeln();

    // Print Mean row
    write(prefix);
    writef("%<*s", metaWidth, "Mean");
    for param i in 0..<numTimingColumns {
      const width = max(tNames(i).size + 2, minColumnWidth);
      writef("  %*.3dr", width, sums(i) / cnt);
    }
    writeln();

    // Print Imbalance row
    write(prefix);
    writef("%<*s", metaWidth, "Imbalance (max/mean)");
    for param i in 0..<numTimingColumns {
      const width = max(tNames(i).size + 2, minColumnWidth);
      const mean = sums(i) / cnt;
      const imb = if mean > 0.0 then maxs(i) / mean else 0.0;
      writef("  %*.3dr", width - 1, imb);
      write("x");
    }
    writeln();
  }

  // -------------------------------------------------------------------------
  // printPhase — helper to print one phase line with percentage
  // -------------------------------------------------------------------------

  proc const ref TimingReport.printPhase(name: string, time: real) {
    const pct = if totalTime > 0.0 then (time / totalTime) * 100.0 else 0.0;
    writef("  %<31s  %10.3dr  %5.1dr%%\n", name, time, pct);
  }

  // -------------------------------------------------------------------------
  // writeCSV — column-driven CSV export with auto-organized output
  // -------------------------------------------------------------------------

  proc const ref TimingReport.writeCSV(baseDir: string) throws {
    // Derive trace name from tracePath
    const traceName = deriveTraceName(tracePath);
    const outDir = baseDir + "/" + traceName + "/" + strategy;

    // Create directory structure
    if !exists(outDir) {
      mkdir(outDir, parents=true);
    }

    // Timestamp for filenames
    const now = dateTime.now();
    const ts = (now: string).replace(":", "-").replace(" ", "_");

    // Write tasks CSV
    const tasksPath = outDir + "/tasks_" + ts + ".csv";
    writeTasksCSV(tasksPath);

    // Write phases CSV
    const phasesPath = outDir + "/phases_" + ts + ".csv";
    writePhasesCSV(phasesPath);

    // Append to runs.csv manifest
    const runsPath = baseDir + "/" + traceName + "/runs.csv";
    appendRunsCSV(runsPath);

    logInfo("Timing CSV written to: ", outDir);
  }

  proc const ref TimingReport.writeTasksCSV(path: string) throws {
    var f = open(path, ioMode.cw);
    var w = f.writer(locking=false);

    // Header: meta columns + timing columns
    w.write("strategy,numLocales,tracePath");
    const mNames = metaColumnNames();
    for param i in 0..<numMetaColumns {
      w.write(",", mNames(i));
    }
    const tNames = timingColumnNames();
    for param i in 0..<numTimingColumns {
      w.write(",", tNames(i));
    }
    w.writeln();

    // Data rows
    for loc in localeTimingData {
      for t in loc.taskTimings {
        w.write(strategy, ",", numLocales, ",", tracePath);
        const meta = t.metaColumnValues();
        for param i in 0..<numMetaColumns {
          w.write(",", meta(i));
        }
        const vals = t.timingColumnValues();
        for param i in 0..<numTimingColumns {
          w.writef(",%.6dr", vals(i));
        }
        w.writeln();
      }
    }

    w.close();
    f.close();
  }

  proc const ref TimingReport.writePhasesCSV(path: string) throws {
    var f = open(path, ioMode.cw);
    var w = f.writer(locking=false);

    w.writeln("strategy,numLocales,tracePath,phase,time,pctTotal");

    const defTotal = defOpenTime + defSetupTime + defReadTime;
    const otherTime = totalTime - defTotal - groupMapTime - eventReadWriteTime - mergeTime;

    proc writePhaseRow(phaseName: string, phaseTime: real) throws {
      const pct = if totalTime > 0.0 then (phaseTime / totalTime) * 100.0 else 0.0;
      w.writef("%s,%i,%s,%s,%.6dr,%.2dr\n",
               strategy, numLocales, tracePath, phaseName, phaseTime, pct);
    }

    writePhaseRow("Read global definitions", defTotal);
    if groupMapTime > 0.0 then writePhaseRow("Build group/location map", groupMapTime);
    if groupDistributionTime > 0.0 then writePhaseRow("Distribute groups", groupDistributionTime);
    if evtReadTime > 0.0 then writePhaseRow("Read events", evtReadTime);
    if writeTime > 0.0 then writePhaseRow("Write output", writeTime);
    if eventReadWriteTime > 0.0 then writePhaseRow("Read events + write output", eventReadWriteTime);
    if mergeTime > 0.0 then writePhaseRow("Merge contexts", mergeTime);
    if otherTime > 0.0 then writePhaseRow("Other (overhead)", otherTime);
    writePhaseRow("Total", totalTime);

    w.close();
    f.close();
  }

  proc const ref TimingReport.appendRunsCSV(path: string) throws {
    const writeHeader = !exists(path);
    var f = open(path, ioMode.cwr);
    var w = f.writer(locking=false);

    if !writeHeader {
      // Seek to end for appending
      w.seek(f.size..);
    } else {
      w.writeln("strategy,numLocales,tracePath,totalTime,throughput");
    }

    var totalEvents: uint(64) = 0;
    for loc in localeTimingData do for t in loc.taskTimings do totalEvents += t.eventsRead;
    const throughput = if totalTime > 0.0 then totalEvents: real / totalTime else 0.0;

    w.writef("%s,%i,%s,%.6dr,%.0dr\n",
             strategy, numLocales, tracePath, totalTime, throughput);

    w.close();
    f.close();
  }

  // -------------------------------------------------------------------------
  // deriveTraceName — extract a meaningful trace name from a path
  // -------------------------------------------------------------------------

  proc deriveTraceName(tracePathStr: string): string {
    // Given e.g. /path/to/frontier-4-node-single-HPL-run/traces.otf2
    // Return "frontier-4-node-single-HPL-run"
    const dir = dirname(tracePathStr);
    const name = basename(dir);
    if name == "" || name == "." then return "unknown-trace";
    return name;
  }
}
