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
    sw.start();

    // Build output-group ownership map (resolves HIP contexts to parent MPI ranks)
    const groupLocationMap = buildGroupLocationMap(defCtx);
    const groupMapTime = sw.elapsed();
    sw.clear();

    const groupNames = orderedOutputGroups(defCtx, groupLocationMap);
    const totalGroups = groupNames.size;
    logInfo("Using locgroup_dist_block strategy with ", numLocales,
            " locales for ", totalGroups, " output groups");

    // Block-distribute group indices across locales
    const groupDom = blockDist.createDomain(0..<totalGroups);
    var totalEventsRead: c_uint64 = 0;

    const groupDistributionTime = sw.elapsed();
    sw.clear();

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
          taskSw.start();

          const localTraceName = conf.trace;
          const readResult = readEventsForLocations(localTraceName, myLocs, evtContexts[i]);
          localeEventsRead += readResult.eventsRead;

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

        totalEventsRead += localeEventsRead;
        report.setTaskTimings(taskTimings);

      }
    }


    const evtReadWriteTime = sw.elapsed();
    const totalConversionTime = global_sw.elapsed();
    logInfo("Time to setup + read events + write output: ", evtReadWriteTime, " seconds");

    logDebug("Total events read: ", totalEventsRead);
    logInfo("Finished converting trace in ", totalConversionTime, " seconds");


    if conf.timings {
      report.strategy = conf.strategy;
      report.totalTime = totalConversionTime;
      report.defOpenTime = defResult.openTime;
      report.defSetupTime = defResult.setupTime;
      report.defReadTime = defResult.readTime;
      report.groupMapTime = groupMapTime;
      report.groupMapTime = groupMapTime;
      report.groupDistributionTime = groupDistributionTime;
      report.eventReadWriteTime = evtReadWriteTime;

      report.print();
    }
  }
}
