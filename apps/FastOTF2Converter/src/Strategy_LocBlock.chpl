// Copyright Hewlett Packard Enterprise Development LP.
//
// Location-based block partitioning strategy.
// Partitions trace locations into contiguous blocks across reader tasks,
// then merges all event contexts at the end.
//
// Single-locale only.

module Strategy_LocBlock {
  use ConverterDefReaders;
  use ConverterCommon;
  use FastOTF2;
  use Time;

  proc run(conf: ConverterConfig) throws {
    var sw: stopwatch;
    var global_sw: stopwatch;
    sw.start();
    global_sw.start();

    const (defCtx, numberOfLocations) = readGlobalDefinitions(conf.trace);
    const evtArgs = buildEvtCallbackArgs(conf);

    const defReadTime = sw.elapsed();
    sw.clear();

    // Convert locationIds to array for partitioning
    const locationArray: [0..<numberOfLocations] OTF2_LocationRef =
      for l in defCtx.locationIds do l;
    const totalLocs = locationArray.size;
    const numberOfReaders = min(here.maxTaskPar, totalLocs);
    logInfo("Using loc_block strategy with ", numberOfReaders, " reader tasks");

    // Prepare per-reader contexts
    var evtContexts = [0..<numberOfReaders] new EvtCallbackContext(evtArgs, defCtx);
    var totalEventsRead: c_uint64 = 0;

    coforall i in 0..<numberOfReaders
      with (+ reduce totalEventsRead, ref evtContexts) {
      // Block partition: contiguous ranges
      const locsPerReader = totalLocs / numberOfReaders;
      const remainder = totalLocs % numberOfReaders;
      const low = i * locsPerReader + min(i, remainder);
      const high = low + locsPerReader + (if i < remainder then 1 else 0);

      logTrace("Reader ", i, " assigned locations [", low, "..", high, ")");

      const myLocs: [0..<(high - low)] OTF2_LocationRef =
        for idx in low..<high do locationArray[idx];

      totalEventsRead += readEventsForLocations(conf.trace, myLocs, evtContexts[i]);
    }

    const evtReadTime = sw.elapsed();
    logDebug("Time taken to read events: ", evtReadTime, " seconds");
    sw.clear();

    logDebug("Total events read: ", totalEventsRead);

    // Merge contexts (required for location partitioning)
    logDebug("Merging event contexts...");
    var mergedCtx = mergeEvtContexts(evtContexts);
    const mergeTime = sw.elapsed();
    logDebug("Time taken to merge contexts: ", mergeTime, " seconds");
    sw.clear();

    logInfo("Trace loaded in ", global_sw.elapsed(), " seconds");
    logInfo("Writing ", conf.outputFormat: string, " files to directory: ", conf.outputDir);
    writeOutputForContext(mergedCtx, conf.outputFormat, conf.outputDir);
    logInfo("Finished writing to ", conf.outputDir, " in ", sw.elapsed(), " seconds");
    logInfo("Finished converting trace in ", global_sw.elapsed(), " seconds");
  }
}
