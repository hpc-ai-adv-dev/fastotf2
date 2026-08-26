// Copyright Hewlett Packard Enterprise Development LP.
//
// Location-group distributed block strategy.
// Block-distributes groups across locales, then block-partitions within
// each locale across its tasks.
//
// Multi-locale.

module Strategy_LocGroupDistBlock {
  use ConverterArgs;
  use ConverterCommon;
  use ConverterParams;
  use ConverterDefReaders;
  use ConverterEvtReaders;
  use ConverterGroupMap;
  use ConverterWriters;
  use ConverterTimings;
  use FastOTF2;
  use Time;
  use List;
  use Map;
  use BlockDist;

  proc run(conf: ConverterConfig) throws {
    var sw: stopwatch;
    var global_sw: stopwatch;
    global_sw.start();

    const defResult = readGlobalDefinitions(conf.trace);
    const ref defCtx = defResult.defCtx;
    const evtArgs = buildEvtCallbackArgs(conf);
    if enableTimers then sw.start();

    // Build output-group ownership map (resolves HIP contexts to parent MPI ranks)
    const groupLocationMap = buildGroupLocationMap(defCtx);
    const groupMapTime = if enableTimers then sw.elapsed() else 0.0;
    if enableTimers then sw.clear();

    const groupNames = orderedOutputGroups(defCtx, groupLocationMap);
    const totalGroups = groupNames.size;
    logInfo("Using locgroup_dist_block strategy with ", numLocales,
            " locales for ", totalGroups, " output groups");

    // Block-distribute complete output groups across locales. The array's
    // parallel iterator runs each group on the locale that owns it.
    const groupDistArray = blockDist.createArray(
      groupNames.domain, string, groupNames
    );
    var totalEventsRead: c_uint64 = 0;
    var taskTimings: [groupDistArray.domain] TaskTiming;

    const groupDistributionTime = if enableTimers then sw.elapsed() else 0.0;
    if enableTimers then sw.clear();

    logInfo("Writing ", conf.outputFormat: string, " files to directory: ",
            conf.outputDir, " as each group completes (no merge needed)");

    // Each iteration opens one OTF2 reader for all locations in one group.
    // BlockDist limits concurrency to the available tasks on each locale; when
    // there are more groups than tasks, a task processes multiple groups.
    forall (groupName, groupIdx) in zip(groupDistArray, groupDistArray.domain)
      with (+ reduce totalEventsRead, ref taskTimings) {
      const myGroupNames: [0..0] string = [groupName];
      const myLocs = locationsForOutputGroups(myGroupNames, groupLocationMap);

      logTrace("Locale ", here.id, " processing output group '", groupName,
               "' with ", myLocs.size, " locations");

      var taskSw: stopwatch;
      if enableTimers then taskSw.start();

      var evtCtx = new EvtCallbackContext(evtArgs, defCtx);
      const localTraceName = conf.trace;
      const readResult = readEventsForLocations(localTraceName, myLocs, evtCtx);
      totalEventsRead += readResult.eventsRead;
      const totalCallbackTime = evtCtx.totalCallbackTime();

      logDebug("Group ", groupIdx, " on locale ", here.id,
               ": readTime=", readResult.readTime,
               " metricTime=", evtCtx.metricCallbackTime,
               " enterTime=", evtCtx.enterCallbackTime,
               " leaveTime=", evtCtx.leaveCallbackTime,
               " callbackTotal=", totalCallbackTime,
               " otf2Time=", readResult.readTime - totalCallbackTime,
               " cbPct=", if readResult.readTime > 0
                          then (100.0 * totalCallbackTime / readResult.readTime)
                          else 0.0, "%");

      // Write immediately -- each iteration owns one complete group.
      const writeResult = if !noopCallbacks
        then writeOutputForContext(evtCtx, conf.outputFormat, conf.outputDir, conf.sortCallgraph)
        else new WriteResult();

      const taskTotalTime = if enableTimers then taskSw.elapsed() else 0.0;

      taskTimings[groupIdx] = new TaskTiming(
        taskId=groupIdx,
        localeId=here.id,
        locations=myLocs.size,
        eventsRead=readResult.eventsRead,
        openTime=readResult.openTime,
        setupTime=readResult.setupTime,
        readTime=readResult.readTime,
        enterCallbackTime=evtCtx.enterCallbackTime,
        leaveCallbackTime=evtCtx.leaveCallbackTime,
        metricCallbackTime=evtCtx.metricCallbackTime,
        writeTime=writeResult.writeTime,
        callgraphWriteTime=writeResult.callgraphTime,
        metricsWriteTime=writeResult.metricsTime,
        totalTime=taskTotalTime
      );
    }

    var report = new TimingReport();
    var timingsByLocale: [0..<numLocales] list(TaskTiming);
    for timing in taskTimings do
      timingsByLocale[timing.localeId].pushBack(timing);

    for localeId in 0..<numLocales {
      const localeTimings = timingsByLocale[localeId].toArray();
      report.setTaskTimings(localeId, localeTimings);
    }

    const evtReadWriteTime = if enableTimers then sw.elapsed() else 0.0;
    const totalConversionTime = global_sw.elapsed();
    logInfo("Time to setup + read events + write output: ", evtReadWriteTime, " seconds");

    logDebug("Total events read: ", totalEventsRead);
    logInfo("Finished converting trace in ", totalConversionTime, " seconds");


    if conf.timings || conf.timingsCSV != "" {
      report.strategy = conf.strategy;
      report.tracePath = conf.trace;
      report.totalTime = totalConversionTime;
      report.defOpenTime = defResult.openTime;
      report.defSetupTime = defResult.setupTime;
      report.defReadTime = defResult.readTime;
      report.groupMapTime = groupMapTime;
      report.groupDistributionTime = groupDistributionTime;
      report.eventReadWriteTime = evtReadWriteTime;

      if conf.timings then report.print();
      if conf.timingsCSV != "" then report.writeCSV(conf.timingsCSV);
    }
  }
}
