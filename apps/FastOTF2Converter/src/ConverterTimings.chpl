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
    var numTasks: int;
    var taskData: [0..<numTasks] TaskTiming;

    // Strategy name for the header
    var strategy: string;
  }

  // -------------------------------------------------------------------------
  // setTaskTimings — populate the report with collected per-task data
  // -------------------------------------------------------------------------

  proc ref TimingReport.setTaskTimings(const ref timings: [] TaskTiming) {
    numTasks = timings.size;
    taskData = timings;
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

    // Per-task breakdown
    if numTasks > 0 {
      writeln();
      writeln("  Per-Task Breakdown (", numTasks, " tasks):");
      writeln("  Task  Locations  Events      Open (s)  Setup (s)  Read (s)  Write Callgraphs (s)  Write Metrics (s)  Write Total (s)  Total (s)");
      writeln("  ────  ─────────  ──────────  ────────  ─────────  ────────  ────────────────────  ─────────────────  ───────────────  ─────────");
      for t in taskData {
        writef("  %4u  %9u  %10u  %8.3dr  %9.3dr  %8.3dr  %20.3dr  %17.3dr  %15.3dr  %9.3dr\n",
               t.taskId, t.locations, t.eventsRead,
               t.openTime, t.setupTime,
               t.readTime,
               t.callgraphWriteTime, t.metricsWriteTime, t.writeTime,
               t.totalTime);
      }
      writeln("  ────  ─────────  ──────────  ────────  ─────────  ────────  ────────────────────  ─────────────────  ───────────────  ─────────");

      // Summary stats
      var minOpen = taskData[0].openTime, maxOpen = taskData[0].openTime, sumOpen = 0.0;
      var minSetup = taskData[0].setupTime, maxSetup = taskData[0].setupTime, sumSetup = 0.0;
      var minRead = taskData[0].readTime, maxRead = taskData[0].readTime, sumRead = 0.0;
      var minCallgraphWrite = taskData[0].callgraphWriteTime, maxCallgraphWrite = taskData[0].callgraphWriteTime, sumCallgraphWrite = 0.0;
      var minMetricsWrite = taskData[0].metricsWriteTime, maxMetricsWrite = taskData[0].metricsWriteTime, sumMetricsWrite = 0.0;
      var minWrite = taskData[0].writeTime, maxWrite = taskData[0].writeTime, sumWrite = 0.0;
      var minTotal = taskData[0].totalTime, maxTotal = taskData[0].totalTime, sumTotal = 0.0;
      var totalEvents: uint(64) = 0;
      for t in taskData {
        if t.openTime < minOpen then minOpen = t.openTime;
        if t.openTime > maxOpen then maxOpen = t.openTime;
        sumOpen += t.openTime;
        if t.setupTime < minSetup then minSetup = t.setupTime;
        if t.setupTime > maxSetup then maxSetup = t.setupTime;
        sumSetup += t.setupTime;
        if t.readTime < minRead then minRead = t.readTime;
        if t.readTime > maxRead then maxRead = t.readTime;
        sumRead += t.readTime;
        if t.callgraphWriteTime < minCallgraphWrite then minCallgraphWrite = t.callgraphWriteTime;
        if t.callgraphWriteTime > maxCallgraphWrite then maxCallgraphWrite = t.callgraphWriteTime;
        sumCallgraphWrite += t.callgraphWriteTime;
        if t.metricsWriteTime < minMetricsWrite then minMetricsWrite = t.metricsWriteTime;
        if t.metricsWriteTime > maxMetricsWrite then maxMetricsWrite = t.metricsWriteTime;
        sumMetricsWrite += t.metricsWriteTime;
        if t.writeTime < minWrite then minWrite = t.writeTime;
        if t.writeTime > maxWrite then maxWrite = t.writeTime;
        sumWrite += t.writeTime;
        if t.totalTime < minTotal then minTotal = t.totalTime;
        if t.totalTime > maxTotal then maxTotal = t.totalTime;
        sumTotal += t.totalTime;
        totalEvents += t.eventsRead;
      }
      const n = numTasks: real;
      const meanOpen = sumOpen / n;
      const meanSetup = sumSetup / n;
      const meanRead = sumRead / n;
      const meanCallgraphWrite = sumCallgraphWrite / n;
      const meanMetricsWrite = sumMetricsWrite / n;
      const meanWrite = sumWrite / n;
      const meanTotal = sumTotal / n;

      writef("   %<26s  %8.3dr  %9.3dr  %8.3dr  %20.3dr  %17.3dr  %15.3dr  %9.3dr\n",
             "Min", minOpen, minSetup, minRead, minCallgraphWrite, minMetricsWrite, minWrite, minTotal);
      writef("   %<26s  %8.3dr  %9.3dr  %8.3dr  %20.3dr  %17.3dr  %15.3dr  %9.3dr\n",
             "Max", maxOpen, maxSetup, maxRead, maxCallgraphWrite, maxMetricsWrite, maxWrite, maxTotal);
      writef("   %<26s  %8.3dr  %9.3dr  %8.3dr  %20.3dr  %17.3dr  %15.3dr  %9.3dr\n",
             "Mean", meanOpen, meanSetup, meanRead, meanCallgraphWrite, meanMetricsWrite, meanWrite, meanTotal);

      // Imbalance ratios (max/mean), only if mean > 0
      if meanTotal > 0.0 {
        const imbOpen = if meanOpen > 0.0 then maxOpen / meanOpen else 0.0;
        const imbSetup = if meanSetup > 0.0 then maxSetup / meanSetup else 0.0;
        const imbRead = if meanRead > 0.0 then maxRead / meanRead else 0.0;
        const imbCallgraphWrite = if meanCallgraphWrite > 0.0 then maxCallgraphWrite / meanCallgraphWrite else 0.0;
        const imbMetricsWrite = if meanMetricsWrite > 0.0 then maxMetricsWrite / meanMetricsWrite else 0.0;
        const imbWrite = if meanWrite > 0.0 then maxWrite / meanWrite else 0.0;
        const imbTotal = maxTotal / meanTotal;
        writef("   %<26s  %7.3drx  %8.3drx  %7.3drx  %19.3drx  %16.3drx  %14.3drx  %8.3drx\n",
               "Imbalance (max/mean)", imbOpen, imbSetup, imbRead, imbCallgraphWrite, imbMetricsWrite, imbWrite, imbTotal);
      }

      if totalTime > 0.0 {
        const eventsPerSec = totalEvents: real / totalTime;
        writeln("  Total events/sec: ", eventsPerSec);
      }
    }

    writeln("=== End Timing Report ===");
  }

  // -------------------------------------------------------------------------
  // printPhase — helper to print one phase line with percentage
  // -------------------------------------------------------------------------

  proc const ref TimingReport.printPhase(name: string, time: real) {
    const pct = if totalTime > 0.0 then (time / totalTime) * 100.0 else 0.0;
    writef("  %<31s  %10.3dr  %5.1dr%%\n", name, time, pct);
  }
}
