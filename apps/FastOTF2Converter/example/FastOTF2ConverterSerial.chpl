// Copyright Hewlett Packard Enterprise Development LP.

module FastOTF2ConverterSerial {
  use FastOTF2;
  use ConverterCommon;
  use ConverterWriters;
  use CallGraphModule;
  use Time;
  use List;
  use Map;
  use IO;
  use Path;
  use FileSystem;
  use ArgumentParser;

  var trace: string = "../../sample-traces/simple-mi300-example-run/traces.otf2";
  var metrics: string = "";
  var processes: string = "";
  var excludeMPI: bool = false;
  var excludeHIP: bool = false;
  var outputDir: string = ".";
  var outputFormat: OutputFormat = OutputFormat.CSV;

  proc main(args: [] string) {
    try {
      var parser = new argumentParser(
        addHelp=true
      );

      var traceArg = parser.addArgument(
        name="trace",
        defaultValue="../../sample-traces/simple-mi300-example-run/traces.otf2",
        help="Path to the OTF2 trace file"
      );

      var metricsArg = parser.addOption(
        name="metrics",
        defaultValue="",
        numArgs=1,
        help="Metrics to track (comma-separated, empty = all)"
      );

      var processesArg = parser.addOption(
        name="processes",
        defaultValue="",
        numArgs=1,
        help="Processes to track (comma-separated, empty = all)"
      );

      var outputDirArg = parser.addOption(
        name="outputDir",
        defaultValue="./",
        numArgs=1,
        help="Directory to write output files to"
      );

      var formatArg = parser.addOption(
        name="format",
        defaultValue="CSV",
        numArgs=1,
        help="Output format: CSV or PARQUET"
      );

      var excludeMPIArg = parser.addFlag(
        name="excludeMPI",
        defaultValue=false,
        numArgs=0,
        help="Exclude MPI functions from the callgraph output"
      );

      var excludeHIPArg = parser.addFlag(
        name="excludeHIP",
        defaultValue=false,
        numArgs=0,
        help="Exclude HIP functions from the callgraph output"
      );

      var logArg = parser.addOption(
        name="log",
        defaultValue="INFO",
        numArgs=1,
        help="Logging level (NONE, ERROR, WARN, INFO, DEBUG, TRACE)"
      );

      parser.parseArgs(args);
      trace = traceArg.value();
      metrics = metricsArg.value();
      processes = processesArg.value();
      outputDir = outputDirArg.value();

      excludeMPI = excludeMPIArg.valueAsBool();
      excludeHIP = excludeHIPArg.valueAsBool();

      try {
        log = logArg.value(): LogLevel;
      } catch e {
        logError("Invalid log level: ", logArg.value(), ". Use one of: NONE, ERROR, WARN, INFO, DEBUG, or TRACE.");
        halt("invalid log level");
      }

      try {
        outputFormat = parseOutputFormat(formatArg.value());
      } catch e {
        logError(e.message());
        halt("invalid output format");
      }

      if excludeMPI {
        logInfo("Excluding MPI functions from callgraph output");
      }
      if excludeHIP {
        logInfo("Excluding HIP functions from callgraph output");
      }
    } catch e {
      logError("Error parsing arguments: ", e);
      halt("argument parsing failed");
    }

    try {
      if !exists(trace) { logError("Trace file does not exist: ", trace); halt("trace file not found"); }
    } catch e { logError("Error checking trace file existence: ", e); halt("trace file check failed"); }

    try {
      if !exists(outputDir) {
        logInfo("Output directory does not exist, creating: ", outputDir);
        mkdir(outputDir);
      }
    } catch e { logError("Error checking/creating output directory: ", e); halt("output directory check failed"); }

    var sw: stopwatch;
    var global_sw: stopwatch;
    sw.start();
    global_sw.start();

    var reader = OTF2_Reader_Open(trace.c_str());
    if reader == nil {
      logError("Failed to open trace");
      halt("failed to open trace");
    }

    const openTime = sw.elapsed();
    logTrace("Time taken to open OTF2 archive: %.2dr seconds\n", openTime);
    sw.clear();

    OTF2_Reader_SetSerialCollectiveCallbacks(reader);

    var numberOfLocations: c_uint64 = 0;
    OTF2_Reader_GetNumberOfLocations(reader, c_ptrTo(numberOfLocations));
    logTrace("Number of locations: ", numberOfLocations);
    logInfo("Reading OTF2 trace ", trace, " serially.");

    var defCtx = new DefCallbackContext();
    var globalDefReader = OTF2_Reader_GetGlobalDefReader(reader);
    var defCallbacks = OTF2_GlobalDefReaderCallbacks_New();
    OTF2_GlobalDefReaderCallbacks_SetClockPropertiesCallback(defCallbacks,
                                                        c_ptrTo(registerClockProperties): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetStringCallback(defCallbacks, c_ptrTo(GlobDefString_Register): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetLocationGroupCallback(defCallbacks, c_ptrTo(GlobDefLocationGroup_Register): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetLocationCallback(defCallbacks, c_ptrTo(GlobDefLocation_Register): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetRegionCallback(defCallbacks, c_ptrTo(GlobDefRegion_Register): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetMetricMemberCallback(defCallbacks, c_ptrTo(GlobDefMetricMember_Register): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetMetricClassCallback(defCallbacks, c_ptrTo(GlobDefMetricClass_Register): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetMetricInstanceCallback(defCallbacks, c_ptrTo(GlobDefMetricInstance_Register): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetMetricClassRecorderCallback(defCallbacks, c_ptrTo(GlobDefMetricClassRecorder_Register): c_fn_ptr);

    OTF2_Reader_RegisterGlobalDefCallbacks(reader,
                                           globalDefReader,
                                           defCallbacks,
                                           c_ptrTo(defCtx): c_ptr(void));
    OTF2_GlobalDefReaderCallbacks_Delete(defCallbacks);

    var definitionsRead: c_uint64 = 0;
    OTF2_Reader_ReadAllGlobalDefinitions(reader, globalDefReader, c_ptrTo(definitionsRead));
    logTrace("Global definitions read: ", definitionsRead);

    const defReadTime = sw.elapsed();
    logTrace("Time taken to read global definitions: %.2dr seconds\n", defReadTime);
    sw.clear();

    // Select all locations
    for loc in defCtx.locationIds {
      OTF2_Reader_SelectLocation(reader, loc);
    }

    // Open files, read local defs per location
    const successfulOpenDefFiles =
                        OTF2_Reader_OpenDefFiles(reader) == OTF2_SUCCESS;

    OTF2_Reader_OpenEvtFiles(reader);

    for loc in defCtx.locationIds {
      if successfulOpenDefFiles {
        var defReader = OTF2_Reader_GetDefReader(reader, loc);
        if defReader != nil {
          var defReads: c_uint64 = 0;
          OTF2_Reader_ReadAllLocalDefinitions(reader,
                                              defReader,
                                              c_ptrTo(defReads));

          OTF2_Reader_CloseDefReader(reader, defReader);
        }
      }
      // Mark file to be read by Global Reader later
      var _evtReader = OTF2_Reader_GetEvtReader(reader, loc);
    }
    const markTime = sw.elapsed();
    logTrace("Time taken to read local definitions and mark event files: %.2dr seconds\n", markTime);
    sw.clear();
    if successfulOpenDefFiles then OTF2_Reader_CloseDefFiles(reader);

    // Parse metrics to track from argument
    var metricsToTrack: domain(string);
    if metrics != "" {
      var metricsArray = metrics.split(",");
      for metric in metricsArray {
        metricsToTrack += metric.strip();
      }
    }

    // Parse processes to track from argument
    var processesToTrack: domain(string);
    if processes != "" {
      var processesArray = processes.split(",");
      for process in processesArray {
        processesToTrack += process.strip();
      }
    }

    var evtArgs = new EvtCallbackArgs(processesToTrack=processesToTrack,
                                      metricsToTrack=metricsToTrack,
                                      excludeMPI=excludeMPI,
                                      excludeHIP=excludeHIP);

    // Create event callback context
    var evtCtx = new EvtCallbackContext(evtArgs, defCtx);

    var globalEvtReader = OTF2_Reader_GetGlobalEvtReader(reader);
    var evtCallbacks = OTF2_GlobalEvtReaderCallbacks_New();
    OTF2_GlobalEvtReaderCallbacks_SetEnterCallback(evtCallbacks,
                                                   c_ptrTo(Enter_callback): c_fn_ptr);
    OTF2_GlobalEvtReaderCallbacks_SetLeaveCallback(evtCallbacks,
                                                   c_ptrTo(Leave_callback): c_fn_ptr);
    OTF2_GlobalEvtReaderCallbacks_SetMetricCallback(evtCallbacks,
                                                    c_ptrTo(Metric_callback): c_fn_ptr);

    OTF2_Reader_RegisterGlobalEvtCallbacks(reader,
                                           globalEvtReader,
                                           evtCallbacks,
                                           c_ptrTo(evtCtx): c_ptr(void));
    OTF2_GlobalEvtReaderCallbacks_Delete(evtCallbacks);

    var totalEventsRead: c_uint64 = 0;
    OTF2_Reader_ReadAllGlobalEvents(reader,
                                    globalEvtReader,
                                    c_ptrTo(totalEventsRead));

    const evtReadTime = sw.elapsed();
    logDebug("Time taken to read events: ", evtReadTime, " seconds");
    sw.clear();

    logDebug("Total events read: ", totalEventsRead);

    OTF2_Reader_CloseGlobalEvtReader(reader, globalEvtReader);
    OTF2_Reader_CloseEvtFiles(reader);
    OTF2_Reader_Close(reader);

    logInfo("Trace loaded in ", global_sw.elapsed(), " seconds");
    logInfo("Writing ", outputFormat:string, " files to directory: ", outputDir);
    writeCallGraphsAndMetrics(evtCtx, outputFormat);
    logInfo("Finished writing to ", outputDir, " in ", sw.elapsed(), " seconds");
    logInfo("Finished converting trace in ", global_sw.elapsed(), " seconds");
  }

  proc writeCallGraphsAndMetrics(ref evtCtx: EvtCallbackContext, format: OutputFormat) {
    for (group, threads) in evtCtx.callGraphs.toArray() {
      if !evtCtx.evtArgs.processesToTrack.isEmpty() && !evtCtx.evtArgs.processesToTrack.contains(group) {
        logInfo("Skipping group ", group, " as it is not in the processes to track.");
      } else {
        for thread in threads.keysToArray() {
          const callGraph = try! threads[thread];
          ConverterCommon.writeCallgraph(callGraph, group, thread, format, outputDir);
        }
      }
    }

    for (group, threadMetrics) in evtCtx.metrics.toArray() {
      if !evtCtx.evtArgs.processesToTrack.isEmpty() && !evtCtx.evtArgs.processesToTrack.contains(group) {
        logInfo("Skipping group ", group, " as it is not in the processes to track.");
      } else {
        ConverterCommon.writeMetrics(group, threadMetrics, format, outputDir);
      }
    }
  }
}
