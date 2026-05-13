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
  use ConverterTimings;
  use FastOTF2;
  use Time;

  proc run(conf: ConverterConfig) throws {
    var sw: stopwatch;
    var global_sw: stopwatch;
    global_sw.start();

    const defResult = readGlobalDefinitions(conf.trace);
    const ref defCtx = defResult.defCtx;
    const numberOfLocations = defResult.numberOfLocations;
    const evtArgs = buildEvtCallbackArgs(conf);
    sw.start();

    const locationArray: [0..<numberOfLocations] OTF2_LocationRef =
      for l in defCtx.locationIds do l;
    logInfo("Using serial strategy with ", locationArray.size, " locations");

    var evtCtx = new EvtCallbackContext(evtArgs, defCtx);
    var taskSw: stopwatch;
    taskSw.start();
    const readResult = readEventsForLocations(conf.trace, locationArray, evtCtx);
    const totalEventsRead = readResult.eventsRead;

    logDebug("Total events read: ", totalEventsRead);
    logInfo("Writing ", conf.outputFormat: string, " files to directory: ", conf.outputDir);
    const writeResult = writeOutputForContext(evtCtx, conf.outputFormat, conf.outputDir);
    logInfo("Finished writing to ", conf.outputDir, " in ", sw.elapsed(), " seconds");
    const taskTotalTime = taskSw.elapsed();
    const evtReadWriteTime = sw.elapsed();
    const totalConversionTime = global_sw.elapsed();
    logInfo("Finished converting trace in ", totalConversionTime, " seconds");

    if conf.timings {
      var taskTimings: [0..0] TaskTiming;
      taskTimings[0] = new TaskTiming(
        taskId=0,
        locations=locationArray.size: int,
        eventsRead=readResult.eventsRead,
        openTime=readResult.openTime,
        setupTime=readResult.setupTime,
        readTime=readResult.readTime,
        writeTime=writeResult.writeTime,
        callgraphWriteTime=writeResult.callgraphTime,
        metricsWriteTime=writeResult.metricsTime,
        totalTime=taskTotalTime
      );

      var report = new TimingReport();
      report.strategy = conf.strategy;
      report.totalTime = totalConversionTime;
      report.defOpenTime = defResult.openTime;
      report.defSetupTime = defResult.setupTime;
      report.defReadTime = defResult.readTime;
      report.eventReadWriteTime = evtReadWriteTime;
      report.setTaskTimings(taskTimings);
      report.print();
    }
  }
}
