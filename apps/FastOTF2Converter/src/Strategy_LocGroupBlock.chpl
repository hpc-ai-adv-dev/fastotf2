// Copyright Hewlett Packard Enterprise Development LP.
//
// Location-group block partitioning strategy.
// Assigns contiguous blocks of location groups to reader tasks so each
// reader owns complete groups — no merge needed.
//
// Single-locale only.

module Strategy_LocGroupBlock {
  use ConverterArgs;
  use ConverterCommon;
  use ConverterDefReaders;
  use ConverterEvtReaders;
  use ConverterGroupMap;
  use ConverterWriters;
  use ConverterTimings;
  use FastOTF2;
  use Time;
  use List;
  use Map;
  use RangeChunk;

  proc run(conf: ConverterConfig) throws {
    var sw: stopwatch;
    var global_sw: stopwatch;
    global_sw.start();

    const defResult = readGlobalDefinitions(conf.trace);
    const ref defCtx = defResult.defCtx;
    const numberOfLocations = defResult.numberOfLocations;
    const evtArgs = buildEvtCallbackArgs(conf);
    sw.start();

    // Build output-group ownership map (resolves HIP contexts to parent MPI ranks)
    const groupLocationMap = buildGroupLocationMap(defCtx);
    const groupMapTime = sw.elapsed();
    sw.clear();

    const groupNames = orderedOutputGroups(defCtx, groupLocationMap);
    const totalGroups = groupNames.size;
    const numberOfReaders = min(here.maxTaskPar, totalGroups);
    logInfo("Using locgroup_block strategy with ", numberOfReaders,
            " reader tasks for ", totalGroups, " output groups");

    // Block-distribute output groups to readers
    var readerGroups: [0..<numberOfReaders] list(string);
    for (r, groupRange) in zip(0..<numberOfReaders, chunks(0..<totalGroups, numberOfReaders)) {
      for idx in groupRange {
        readerGroups[r].pushBack(groupNames[idx]);
      }
    }

    const groupDistributionTime = sw.elapsed();
    sw.clear();

    if log >= LogLevel.TRACE {
      logTrace("Reader group distribution:");

      for r in 0..<numberOfReaders {
        var assignedLocs = 0;
        for name in readerGroups[r] do assignedLocs += groupLocationMap[name].size;
        logTrace("  Reader ", r, ": ", readerGroups[r].size, " groups, ",
                 assignedLocs, " locations");
      }
    }

    // Prepare per-reader contexts
    var evtContexts = [0..<numberOfReaders] new EvtCallbackContext(evtArgs, defCtx);
    var totalEventsRead: c_uint64 = 0;
    var taskTimings: [0..<numberOfReaders] TaskTiming;

    logInfo("Writing ", conf.outputFormat: string, " files to directory: ",
            conf.outputDir, " as each reader completes (no merge needed)");

    coforall i in 0..<numberOfReaders
      with (+ reduce totalEventsRead, ref evtContexts, ref taskTimings) {

      // Collect locations for this reader's output groups
      const myGroupNames: [0..<readerGroups[i].size] string =
        for g in readerGroups[i] do g;
      const myLocs = locationsForOutputGroups(myGroupNames, groupLocationMap);

      logTrace("Reader ", i, " assigned ", readerGroups[i].size,
               " groups with ", myLocs.size, " total locations");

      var taskSw: stopwatch;
      taskSw.start();

      const readResult = readEventsForLocations(conf.trace, myLocs, evtContexts[i]);
      totalEventsRead += readResult.eventsRead;

      // Write immediately — each reader owns complete groups
      const writeResult = writeOutputForContext(evtContexts[i], conf.outputFormat, conf.outputDir);

      taskTimings[i] = new TaskTiming(
        taskId=i,
        locations=myLocs.size,
        eventsRead=readResult.eventsRead,
        openTime=readResult.openTime,
        setupTime=readResult.setupTime,
        readTime=readResult.readTime,
        writeTime=writeResult.writeTime,
        callgraphWriteTime=writeResult.callgraphTime,
        metricsWriteTime=writeResult.metricsTime,
        totalTime=taskSw.elapsed()
      );
    }

    const evtReadWriteTime = sw.elapsed();
    const totalConversionTime = global_sw.elapsed();
    logDebug("Time to setup + read events + write output: ", evtReadWriteTime, " seconds");

    logDebug("Total events read: ", totalEventsRead);
    logInfo("Finished converting trace in ", totalConversionTime, " seconds");

    if conf.timings {
      var report = new TimingReport();
      report.strategy = conf.strategy;
      report.totalTime = totalConversionTime;
      report.defOpenTime = defResult.openTime;
      report.defSetupTime = defResult.setupTime;
      report.defReadTime = defResult.readTime;
      report.groupMapTime = groupMapTime;
      report.groupDistributionTime = groupDistributionTime;
      report.eventReadWriteTime = evtReadWriteTime;
      report.setTaskTimings(taskTimings);
      report.print();
    }
  }
}
