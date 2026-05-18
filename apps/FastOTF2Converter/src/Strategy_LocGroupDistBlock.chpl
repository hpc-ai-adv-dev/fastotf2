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
    var totalEventsRead: c_uint64 = 0;

    const groupDistributionTime = if enableTimers then sw.elapsed() else 0.0;
    if enableTimers then sw.clear();

    logInfo("Writing ", conf.outputFormat: string, " files to directory: ",
            conf.outputDir, " as each reader completes (no merge needed)");

    var report = new TimingReport();

    coforall loc in Locales with (+ reduce totalEventsRead, ref report) do on loc {
      // Find which group indices are local to this locale
      const mySubDom = groupDom.localSubdomain();
      const nGroups = mySubDom.size;
      if nGroups == 0 {
        logTrace("Locale ", loc.id, " has no groups assigned");
      } else {
        const numberOfReaders = min(here.maxTaskPar, nGroups);
        logTrace("Locale ", loc.id, " processing ", nGroups,
                  " groups with ", numberOfReaders, " reader tasks");

        // Block-partition local output groups across reader tasks
        var readerGroups: [0..<numberOfReaders] list(string);
        const localGroupIndices: [0..<nGroups] int = for i in mySubDom do i;
        for (r, groupRange) in zip(0..<numberOfReaders, chunks(0..<nGroups, numberOfReaders)) {
          for idx in groupRange {
            readerGroups[r].pushBack(groupNames[localGroupIndices[idx]]);
          }
        }

        var evtContexts = [0..<numberOfReaders] new EvtCallbackContext(evtArgs, defCtx);
        var localeEventsRead: c_uint64 = 0;
        var taskTimings: [0..<numberOfReaders] TaskTiming;

        coforall i in 0..<numberOfReaders
          with (+ reduce localeEventsRead, ref evtContexts, ref taskTimings) {

          const myGroupNames: [0..<readerGroups[i].size] string =
            for g in readerGroups[i] do g;
          const myLocs = locationsForOutputGroups(myGroupNames, groupLocationMap);

          logTrace("Locale ", loc.id, " reader ", i, " assigned ",
                    readerGroups[i].size, " groups with ", myLocs.size, " locations");

          var taskSw: stopwatch;
          if enableTimers then taskSw.start();

          const localTraceName = conf.trace;
          const readResult = readEventsForLocations(localTraceName, myLocs, evtContexts[i]);
          localeEventsRead += readResult.eventsRead;
          const totalCallbackTime = evtContexts[i].totalCallbackTime();

          logDebug("Task ", i, " on locale ", loc.id,
                   ": readTime=", readResult.readTime,
                   " metricTime=", evtContexts[i].metricCallbackTime,
                   " enterTime=", evtContexts[i].enterCallbackTime,
                   " leaveTime=", evtContexts[i].leaveCallbackTime,
                   " callbackTotal=", totalCallbackTime,
                   " otf2Time=", readResult.readTime - totalCallbackTime,
                   " cbPct=", if readResult.readTime > 0
                              then (100.0 * totalCallbackTime / readResult.readTime)
                              else 0.0, "%");

          // Write immediately — each reader owns complete groups
          const writeResult = if !noopCallbacks
            then writeOutputForContext(evtContexts[i], conf.outputFormat, conf.outputDir)
            else new WriteResult();

          const taskTotalTime = if enableTimers then taskSw.elapsed() else 0.0;

          taskTimings[i] = new TaskTiming(
            taskId=i,
            localeId=loc.id,
            locations=myLocs.size,
            eventsRead=readResult.eventsRead,
            openTime=readResult.openTime,
            setupTime=readResult.setupTime,
            readTime=readResult.readTime,
            enterCallbackTime=evtContexts[i].enterCallbackTime,
            leaveCallbackTime=evtContexts[i].leaveCallbackTime,
            metricCallbackTime=evtContexts[i].metricCallbackTime,
            writeTime=writeResult.writeTime,
            callgraphWriteTime=writeResult.callgraphTime,
            metricsWriteTime=writeResult.metricsTime,
            totalTime=taskTotalTime
          );

        }

        totalEventsRead += localeEventsRead;
        report.setTaskTimings(taskTimings);

      }
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
