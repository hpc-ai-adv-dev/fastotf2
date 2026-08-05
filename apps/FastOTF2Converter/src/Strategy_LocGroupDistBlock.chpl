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
  use ConverterParallelism;
  use ConverterWriters;
  use ConverterTimings;
  use FastOTF2;
  use Time;
  use List;
  use Map;
  use BlockDist;
  use RangeChunk;

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

    // Block-distribute group indices across locales
    const groupDom = blockDist.createDomain(0..<totalGroups);
    const totalReaders = min(totalGroups, numLocales * here.maxTaskPar);
    if conf.parallelismReport then
      printLocationGroupParallelism(conf, defCtx, evtArgs,
                                    defResult.numberOfLocations,
                                    groupLocationMap, totalReaders);
    const readerDom = blockDist.createDomain(0..<totalReaders);
    var totalEventsRead: c_uint64 = 0;
    var taskTimings: [readerDom] TaskTiming;

    const groupDistributionTime = if enableTimers then sw.elapsed() else 0.0;
    if enableTimers then sw.clear();

    logInfo("Writing ", conf.outputFormat: string, " files to directory: ",
            conf.outputDir, " as each reader completes (no merge needed)");

    forall readerIdx in readerDom
      with (+ reduce totalEventsRead, ref taskTimings) {
      const localReaderDom = readerDom.localSubdomain();
      const localGroupDom = groupDom.localSubdomain();
      const readerId = readerIdx - localReaderDom.low;
      const numberOfReaders = localReaderDom.size;
      const groupRange = chunk(localGroupDom.dim(0), numberOfReaders, readerId);

      const myGroupNames: [0..<groupRange.size] string =
        for gIdx in groupRange do groupNames[gIdx];
      const myLocs = locationsForOutputGroups(myGroupNames, groupLocationMap);

      logTrace("Locale ", here.id, " reader ", readerId, " assigned ",
               groupRange.size, " groups with ", myLocs.size, " locations");

      var taskSw: stopwatch;
      if enableTimers then taskSw.start();

      var evtCtx = new EvtCallbackContext(evtArgs, defCtx);
      const localTraceName = conf.trace;
      const readResult = readEventsForLocations(localTraceName, myLocs, evtCtx);
      totalEventsRead += readResult.eventsRead;
      const totalCallbackTime = evtCtx.totalCallbackTime();

      logDebug("Task ", readerId, " on locale ", here.id,
               ": readTime=", readResult.readTime,
               " metricTime=", evtCtx.metricCallbackTime,
               " enterTime=", evtCtx.enterCallbackTime,
               " leaveTime=", evtCtx.leaveCallbackTime,
               " callbackTotal=", totalCallbackTime,
               " otf2Time=", readResult.readTime - totalCallbackTime,
               " cbPct=", if readResult.readTime > 0
                          then (100.0 * totalCallbackTime / readResult.readTime)
                          else 0.0, "%");

      // Write immediately -- each reader owns complete groups.
      const writeResult = if !noopCallbacks
        then writeOutputForContext(evtCtx, conf.outputFormat, conf.outputDir, conf.sortCallgraph)
        else new WriteResult();

      const taskTotalTime = if enableTimers then taskSw.elapsed() else 0.0;

      taskTimings[readerIdx] = new TaskTiming(
        taskId=readerId,
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
