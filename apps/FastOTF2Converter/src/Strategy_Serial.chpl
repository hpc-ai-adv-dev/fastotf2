// Copyright Hewlett Packard Enterprise Development LP.
//
// Serial strategy.
// Reads all locations sequentially in a single reader task.
// No parallelism, no merge needed. Useful as a baseline and example.
//
// Single-locale only.

module Strategy_Serial {
  use ConverterArgs;
  use ConverterCommon;
  use ConverterDefReaders;
  use ConverterEvtReaders;
  use ConverterWriters;
  use FastOTF2;
  use Time;

  proc run(conf: ConverterConfig) throws {
    var sw: stopwatch;
    var global_sw: stopwatch;
    global_sw.start();

    const (defCtx, numberOfLocations) = readGlobalDefinitions(conf.trace);
    const evtArgs = buildEvtCallbackArgs(conf);
    sw.start();

    const locationArray: [0..<numberOfLocations] OTF2_LocationRef =
      for l in defCtx.locationIds do l;
    logInfo("Using serial strategy with ", locationArray.size, " locations");

    var evtCtx = new EvtCallbackContext(evtArgs, defCtx);
    const totalEventsRead = readEventsForLocations(conf.trace, locationArray, evtCtx);

    const evtReadTime = sw.elapsed();
    logInfo("Time to setup + read events: ", evtReadTime, " seconds");
    sw.clear();

    logDebug("Total events read: ", totalEventsRead);
    logInfo("Writing ", conf.outputFormat: string, " files to directory: ", conf.outputDir);
    writeOutputForContext(evtCtx, conf.outputFormat, conf.outputDir);
    logInfo("Finished writing to ", conf.outputDir, " in ", sw.elapsed(), " seconds");
    logInfo("Finished converting trace in ", global_sw.elapsed(), " seconds");
  }
}
