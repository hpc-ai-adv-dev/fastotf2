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
  use ConverterParams;
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
    const writeResult = if !noopCallbacks
      then writeOutputForContext(evtCtx, conf.outputFormat, conf.outputDir)
      else new WriteResult();
    if !noopCallbacks then
      logInfo("Finished writing to ", conf.outputDir, " in ", sw.elapsed(), " seconds");
    const taskTotalTime = taskSw.elapsed();
    const evtReadWriteTime = sw.elapsed();
    const totalConversionTime = global_sw.elapsed();
    logInfo("Finished converting trace in ", totalConversionTime, " seconds");

    if conf.timings || conf.timingsCSV != "" {
      var taskTimings: [0..0] TaskTiming;
      taskTimings[0] = new TaskTiming(
        taskId=0,
        localeId=here.id,
        locations=locationArray.size: uint,
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

      var report = new TimingReport();
      report.strategy = conf.strategy;
      report.tracePath = conf.trace;
      report.totalTime = totalConversionTime;
      report.defOpenTime = defResult.openTime;
      report.defSetupTime = defResult.setupTime;
      report.defReadTime = defResult.readTime;
      report.eventReadWriteTime = evtReadWriteTime;
      report.setTaskTimings(taskTimings);
      if conf.timings then report.print();
      if conf.timingsCSV != "" then report.writeCSV(conf.timingsCSV);
    }
  }
}
