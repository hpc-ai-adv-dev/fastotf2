// Copyright Hewlett Packard Enterprise Development LP.
//
// Location-group block partitioning strategy.
// Assigns contiguous blocks of location groups to reader tasks so each
// reader owns complete groups — no merge needed.
//
// Single-locale only.

module Strategy_LocGroupBlock {
  use ConverterDefReaders;
  use ConverterCommon;
  use FastOTF2;
  use Time;
  use List;
  use Map;
  use RangeChunk;

  proc run(conf: ConverterConfig) throws {
    var sw: stopwatch;
    var global_sw: stopwatch;
    sw.start();
    global_sw.start();

    const (defCtx, numberOfLocations) = readGlobalDefinitions(conf.trace);
    const evtArgs = buildEvtCallbackArgs(conf);

    const defReadTime = sw.elapsed();
    sw.clear();

    // Build output-group ownership map (resolves HIP contexts to parent MPI ranks)
    const groupLocationMap = buildGroupLocationMap(defCtx);
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

    logTrace("Reader group distribution:");
    for r in 0..<numberOfReaders {
      var assignedLocs = 0;
      for name in readerGroups[r] do assignedLocs += groupLocationMap[name].size;
      logTrace("  Reader ", r, ": ", readerGroups[r].size, " groups, ",
               assignedLocs, " locations");
    }

    // Prepare per-reader contexts
    var evtContexts = [0..<numberOfReaders] new EvtCallbackContext(evtArgs, defCtx);
    var totalEventsRead: c_uint64 = 0;

    logInfo("Writing ", conf.outputFormat: string, " files to directory: ",
            conf.outputDir, " as each reader completes (no merge needed)");

    coforall i in 0..<numberOfReaders
      with (+ reduce totalEventsRead, ref evtContexts) {

      // Collect locations for this reader's output groups
      const myGroupNames: [0..<readerGroups[i].size] string =
        for g in readerGroups[i] do g;
      const myLocs = locationsForOutputGroups(myGroupNames, groupLocationMap);

      logTrace("Reader ", i, " assigned ", readerGroups[i].size,
               " groups with ", myLocs.size, " total locations");

      totalEventsRead += readEventsForLocations(conf.trace, myLocs, evtContexts[i]);

      // Write immediately — each reader owns complete groups
      writeOutputForContext(evtContexts[i], conf.outputFormat, conf.outputDir);
    }

    const evtReadTime = sw.elapsed();
    logDebug("Time taken to read events and write output: ", evtReadTime, " seconds");

    logDebug("Total events read: ", totalEventsRead);
    logInfo("Trace loaded in ", global_sw.elapsed(), " seconds");
    logInfo("Finished converting trace in ", global_sw.elapsed(), " seconds");
  }
}
