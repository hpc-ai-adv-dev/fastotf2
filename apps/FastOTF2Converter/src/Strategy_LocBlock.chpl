// Copyright Hewlett Packard Enterprise Development LP.
//
// Location-based block partitioning strategy.
// Partitions trace locations into contiguous blocks across reader tasks,
// then merges all event contexts at the end.
//
// Single-locale only.

module Strategy_LocBlock {
  use ConverterArgs;
  use ConverterCommon;
  use ConverterParams;
  use ConverterDefReaders;
  use ConverterEvtReaders;
  use ConverterWriters;
  use ConverterTimings;
  use FastOTF2;
  use Time;
  use RangeChunk;

  proc run(conf: ConverterConfig) throws {
    var sw: stopwatch;
    var global_sw: stopwatch;
    global_sw.start();

    const defResult = readGlobalDefinitions(conf.trace);
    const ref defCtx = defResult.defCtx;
    const numberOfLocations = defResult.numberOfLocations;
    const evtArgs = buildEvtCallbackArgs(conf);
    if enableTimers then sw.start();

    // Convert locationIds to array for partitioning
    const locationArray: [0..<numberOfLocations] OTF2_LocationRef =
      for l in defCtx.locationIds do l;
    const totalLocs = locationArray.size;
    const numberOfReaders = min(here.maxTaskPar, totalLocs);
    logInfo("Using loc_block strategy with ", numberOfReaders, " reader tasks");

    // Prepare per-reader contexts
    var evtContexts = [0..<numberOfReaders] new EvtCallbackContext(evtArgs, defCtx);
    var totalEventsRead: c_uint64 = 0;
    var taskTimings: [0..<numberOfReaders] TaskTiming;

    coforall i in 0..<numberOfReaders
      with (+ reduce totalEventsRead, ref evtContexts, ref taskTimings) {
      const myRange = chunk(0..<totalLocs, numberOfReaders, i);

      logTrace("Reader ", i, " assigned locations [", myRange.low, "..", myRange.high, "]");

      const myLocs: [0..<myRange.size] OTF2_LocationRef =
        for idx in myRange do locationArray[idx];

      var taskSw: stopwatch;
      if enableTimers then taskSw.start();

      const readResult = readEventsForLocations(conf.trace, myLocs, evtContexts[i]);
      totalEventsRead += readResult.eventsRead;

      const taskTotalTime = if enableTimers then taskSw.elapsed() else 0.0;

      taskTimings[i] = new TaskTiming(
        taskId=i,
        localeId=here.id,
        locations=myLocs.size,
        eventsRead=readResult.eventsRead,
        openTime=readResult.openTime,
        setupTime=readResult.setupTime,
        readTime=readResult.readTime,
        enterCallbackTime=evtContexts[i].enterCallbackTime,
        leaveCallbackTime=evtContexts[i].leaveCallbackTime,
        metricCallbackTime=evtContexts[i].metricCallbackTime,
        totalTime=taskTotalTime
      );
    }

    const evtReadTime = if enableTimers then sw.elapsed() else 0.0;
    if enableTimers {
      logDebug("Time to setup + read events: ", evtReadTime, " seconds");
      sw.clear();
    }

    logDebug("Total events read: ", totalEventsRead);

    // Merge contexts (required for location partitioning)
    logDebug("Merging event contexts...");
    var mergedCtx = mergeEvtContexts(evtContexts);
    const mergeTime = if enableTimers then sw.elapsed() else 0.0;
    if enableTimers {
      logInfo("Time to merge contexts: ", mergeTime, " seconds");
      sw.clear();
    }

    logInfo("Trace loaded in ", global_sw.elapsed(), " seconds");
    logInfo("Writing ", conf.outputFormat: string, " files to directory: ", conf.outputDir);

    const writeResult = if !noopCallbacks
      then writeOutputForContext(mergedCtx, conf.outputFormat, conf.outputDir, conf.sortCallgraph)
      else new WriteResult();
    if !noopCallbacks && enableTimers then
      logInfo("Finished writing to ", conf.outputDir, " in ", writeResult.writeTime, " seconds");
    logInfo("Finished converting trace in ", global_sw.elapsed(), " seconds");

    if conf.timings || conf.timingsCSV != "" {
      var report = new TimingReport();
      report.strategy = conf.strategy;
      report.tracePath = conf.trace;
      report.totalTime = global_sw.elapsed();
      report.defOpenTime = defResult.openTime;
      report.defSetupTime = defResult.setupTime;
      report.defReadTime = defResult.readTime;
      report.evtReadTime = evtReadTime;
      report.writeTime = writeResult.writeTime;
      report.mergeTime = mergeTime;
      report.setTaskTimings(taskTimings);
      if conf.timings then report.print();
      if conf.timingsCSV != "" then report.writeCSV(conf.timingsCSV);
    }
  }
}
