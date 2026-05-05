// Copyright Hewlett Packard Enterprise Development LP.
//
// Timing infrastructure for the converter.
// Provides records for collecting per-phase and per-task timing data,
// and a formatted report printer. Opt-in via --timings flag.

module ConverterTimings {

  // -------------------------------------------------------------------------
  // TaskTiming — per-task timing data collected inside coforall
  // -------------------------------------------------------------------------

  record TaskTiming {
    var taskId: uint;
    var locations: uint;
    var eventsRead: uint;
    var openTime: real;          // from ReadResult
    var setupTime: real;         // from ReadResult
    var readTime: real;          // from ReadResult
    // Write times only for strategies that write per-task (e.g., locgroup_block)
    // for others, these will be 0 and the total write time will be in writeTime in the report
    var writeTime: real;         // from WriteResult
    var callgraphWriteTime: real; // from WriteResult
    var metricsWriteTime: real;  // from WriteResult
    var totalTime: real;         // wall-clock for the entire task body
  }

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
    var eventReadWriteTime: real;  // combined time for event reading + callgraph writing
    var evtReadTime: real;        // only for strategies that separate event read from write
    var writeTime: real;          // only for strategies that separate event read from write
    var mergeTime: real;        // only for strategies with a merge phase

    // Per-task data
    // var numTasks: int;
    // var taskData: [0..<numTasks] TaskTiming;
    // Replaced with locale breakdown for better clarity in locgroup strategies
    var localeTimingData : [0..<numLocales] LocaleTiming;

    // Strategy name for the header
    var strategy: string;
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
  // print — output the formatted timing report
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
      const taskHeader = "  Task  Locations  Events      Open (s)  Setup (s)  Read (s)  Write CG (s)  Write Met (s)  Write Tot (s)  Total (s)";
      const taskSep    = "  ────  ─────────  ──────────  ────────  ─────────  ────────  ────────────  ─────────────  ─────────────  ─────────";

      // --- Per-locale sections with per-locale stats ---
      for locId in 0..<numLocales {
        ref loc = localeTimingData[locId];
        if loc.numTasks == 0 then continue;

        writeln();
        writeln("┌─ Locale ", locId, " (", loc.numTasks, " tasks) ─────────────────────────────────────────");
        writeln(taskHeader);
        writeln(taskSep);
        for t in loc.taskTimings {
          writef("  %4u  %9u  %10u  %8.3dr  %9.3dr  %8.3dr  %12.3dr  %13.3dr  %13.3dr  %9.3dr\n",
                 t.taskId, t.locations, t.eventsRead,
                 t.openTime, t.setupTime, t.readTime,
                 t.callgraphWriteTime, t.metricsWriteTime, t.writeTime,
                 t.totalTime);
        }
        writeln(taskSep);

        // Per-locale summary stats
        printTaskStats(loc.taskTimings, loc.numTasks, "  ");
        writeln("└──────────────────────────────────────────────────────────────────────────");
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

        // Per-locale wall times for inter-locale balance
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

    var minOpen = tasks[0].openTime, maxOpen = tasks[0].openTime, sumOpen = 0.0;
    var minSetup = tasks[0].setupTime, maxSetup = tasks[0].setupTime, sumSetup = 0.0;
    var minRead = tasks[0].readTime, maxRead = tasks[0].readTime, sumRead = 0.0;
    var minCGWrite = tasks[0].callgraphWriteTime, maxCGWrite = tasks[0].callgraphWriteTime, sumCGWrite = 0.0;
    var minMetWrite = tasks[0].metricsWriteTime, maxMetWrite = tasks[0].metricsWriteTime, sumMetWrite = 0.0;
    var minWrite = tasks[0].writeTime, maxWrite = tasks[0].writeTime, sumWrite = 0.0;
    var minTotal = tasks[0].totalTime, maxTotal = tasks[0].totalTime, sumTotal = 0.0;
    var totalEvents: uint(64) = 0;

    for t in tasks {
      if t.openTime < minOpen then minOpen = t.openTime;
      if t.openTime > maxOpen then maxOpen = t.openTime;
      sumOpen += t.openTime;
      if t.setupTime < minSetup then minSetup = t.setupTime;
      if t.setupTime > maxSetup then maxSetup = t.setupTime;
      sumSetup += t.setupTime;
      if t.readTime < minRead then minRead = t.readTime;
      if t.readTime > maxRead then maxRead = t.readTime;
      sumRead += t.readTime;
      if t.callgraphWriteTime < minCGWrite then minCGWrite = t.callgraphWriteTime;
      if t.callgraphWriteTime > maxCGWrite then maxCGWrite = t.callgraphWriteTime;
      sumCGWrite += t.callgraphWriteTime;
      if t.metricsWriteTime < minMetWrite then minMetWrite = t.metricsWriteTime;
      if t.metricsWriteTime > maxMetWrite then maxMetWrite = t.metricsWriteTime;
      sumMetWrite += t.metricsWriteTime;
      if t.writeTime < minWrite then minWrite = t.writeTime;
      if t.writeTime > maxWrite then maxWrite = t.writeTime;
      sumWrite += t.writeTime;
      if t.totalTime < minTotal then minTotal = t.totalTime;
      if t.totalTime > maxTotal then maxTotal = t.totalTime;
      sumTotal += t.totalTime;
      totalEvents += t.eventsRead;
    }

    const cnt = n: real;
    const meanOpen = sumOpen / cnt;
    const meanSetup = sumSetup / cnt;
    const meanRead = sumRead / cnt;
    const meanCGWrite = sumCGWrite / cnt;
    const meanMetWrite = sumMetWrite / cnt;
    const meanWrite = sumWrite / cnt;
    const meanTotal = sumTotal / cnt;

    writef("%s%<27s  %8.3dr  %9.3dr  %8.3dr  %12.3dr  %13.3dr  %13.3dr  %9.3dr\n",
           prefix, "Min", minOpen, minSetup, minRead, minCGWrite, minMetWrite, minWrite, minTotal);
    writef("%s%<27s  %8.3dr  %9.3dr  %8.3dr  %12.3dr  %13.3dr  %13.3dr  %9.3dr\n",
           prefix, "Max", maxOpen, maxSetup, maxRead, maxCGWrite, maxMetWrite, maxWrite, maxTotal);
    writef("%s%<27s  %8.3dr  %9.3dr  %8.3dr  %12.3dr  %13.3dr  %13.3dr  %9.3dr\n",
           prefix, "Mean", meanOpen, meanSetup, meanRead, meanCGWrite, meanMetWrite, meanWrite, meanTotal);

    if meanTotal > 0.0 {
      const imbOpen = if meanOpen > 0.0 then maxOpen / meanOpen else 0.0;
      const imbSetup = if meanSetup > 0.0 then maxSetup / meanSetup else 0.0;
      const imbRead = if meanRead > 0.0 then maxRead / meanRead else 0.0;
      const imbCGWrite = if meanCGWrite > 0.0 then maxCGWrite / meanCGWrite else 0.0;
      const imbMetWrite = if meanMetWrite > 0.0 then maxMetWrite / meanMetWrite else 0.0;
      const imbWrite = if meanWrite > 0.0 then maxWrite / meanWrite else 0.0;
      const imbTotal = maxTotal / meanTotal;
      writef("%s%<27s  %7.3drx  %8.3drx  %7.3drx  %11.3drx  %12.3drx  %12.3drx  %8.3drx\n",
             prefix, "Imbalance (max/mean)", imbOpen, imbSetup, imbRead, imbCGWrite, imbMetWrite, imbWrite, imbTotal);
    }
  }

  // -------------------------------------------------------------------------
  // printPhase — helper to print one phase line with percentage
  // -------------------------------------------------------------------------

  proc const ref TimingReport.printPhase(name: string, time: real) {
    const pct = if totalTime > 0.0 then (time / totalTime) * 100.0 else 0.0;
    writef("  %<31s  %10.3dr  %5.1dr%%\n", name, time, pct);
  }
}
