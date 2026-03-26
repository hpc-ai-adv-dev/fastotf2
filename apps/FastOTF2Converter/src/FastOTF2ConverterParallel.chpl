// Copyright Hewlett Packard Enterprise Development LP.
module FastOTF2ConverterParallel {
  use FastOTF2;
  use FastOTF2ConverterCommon;
  use FastOTF2ConverterWriters;
  use CallGraphModule;
  use Time;
  use List;
  use Map;
  use IO;
  use Path;
  use FileSystem;
  use ArgumentParser;

  var trace: string = "../../sample-traces/simple-mi300-example-run/traces.otf2";
  var metrics: string = ""; // Empty string means track all metrics
  var processes: string = ""; // Empty string means track all processes
  var excludeMPI: bool = false;
  var excludeHIP: bool = false;
  var outputDir: string = ".";
  var outputFormat: OutputFormat = OutputFormat.CSV;

  proc main(programArgs: [] string) {
    try {
      var parser = new argumentParser(
        addHelp=true // Automatically add --help flag
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

      parser.parseArgs(programArgs);
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
    sw.clear(); // Restart stopwatch for next timing

    OTF2_Reader_SetSerialCollectiveCallbacks(reader);

    var numberOfLocations: c_uint64 = 0;
    OTF2_Reader_GetNumberOfLocations(reader, c_ptrTo(numberOfLocations));
    logTrace("Number of locations: ", numberOfLocations);
    logInfo("Reading OTF2 trace ", trace, " with ", min(here.maxTaskPar, numberOfLocations), " threads.");

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
    sw.clear(); // Restart stopwatch for next timing

    // Close the initial reader
    OTF2_Reader_Close(reader);

    // Parse metrics to track from config argument
    var metricsToTrack: domain(string);
    if metrics != "" {
      var metricsArray = metrics.split(",");
      for metric in metricsArray {
        metricsToTrack += metric.strip();
      }
    }

    // Parse processes to track from config argument
    var processesToTrack: domain(string);
    if processes != "" {
      var processesArray = processes.split(",");
      for process in processesArray {
        processesToTrack += process.strip();
      }
    }

    // Use the parsed metrics and processes
    var evtArgs = new EvtCallbackArgs(processesToTrack=processesToTrack,
                                      metricsToTrack=metricsToTrack,
                                      excludeMPI=excludeMPI,
                                      excludeHIP=excludeHIP);

    // Parallel Reading Setup
    // Convert locationIds to array for partitioning
    const locationArray : [0..<numberOfLocations] OTF2_LocationRef = for l in defCtx.locationIds do l;
    const totalLocs = locationArray.size;
    const numberOfReaders = min(here.maxTaskPar, totalLocs);
    logTrace("Number of readers: ", numberOfReaders);

    // Prepare contexts array
    var evtContexts =  [0..<numberOfReaders] new EvtCallbackContext(evtArgs, defCtx);
    // for i in 0..<numberOfReaders {
    //    evtContexts[i] = new EvtCallbackContext(evtArgs, defCtx);
    // }

    var totalEventsReadAcrossReaders: c_uint64 = 0;

    coforall i in 0..<numberOfReaders with (+ reduce totalEventsReadAcrossReaders, ref evtContexts) {
       // Open reader
       var reader = OTF2_Reader_Open(trace.c_str());
       if reader != nil {
         OTF2_Reader_SetSerialCollectiveCallbacks(reader);

         // Partition locations
         const locationsPerReader = totalLocs / numberOfReaders;
         const remainder = totalLocs % numberOfReaders;
         const low = i * locationsPerReader + min(i, remainder);
         const high = low + locationsPerReader + (if i < remainder then 1 else 0);

         // Select locations
         for locIdx in low..<high {
           const loc = locationArray[locIdx];
           OTF2_Reader_SelectLocation(reader, loc);
         }

         OTF2_Reader_OpenEvtFiles(reader);

         // Mark files
         for locIdx in low..<high {
           const loc = locationArray[locIdx];
           var _evtReader = OTF2_Reader_GetEvtReader(reader, loc);
         }

         // Setup callbacks
         var globalEvtReader = OTF2_Reader_GetGlobalEvtReader(reader);
         if globalEvtReader != nil {
           var evtCallbacks = OTF2_GlobalEvtReaderCallbacks_New();

           // Use local context
           ref localCtx = evtContexts[i];

           OTF2_GlobalEvtReaderCallbacks_SetEnterCallback(evtCallbacks, c_ptrTo(Enter_callback): c_fn_ptr);
           OTF2_GlobalEvtReaderCallbacks_SetLeaveCallback(evtCallbacks, c_ptrTo(Leave_callback): c_fn_ptr);
           OTF2_GlobalEvtReaderCallbacks_SetMetricCallback(evtCallbacks, c_ptrTo(Metric_callback): c_fn_ptr);

           OTF2_Reader_RegisterGlobalEvtCallbacks(reader, globalEvtReader, evtCallbacks, c_ptrTo(localCtx): c_ptr(void));
           OTF2_GlobalEvtReaderCallbacks_Delete(evtCallbacks);

           var totalEventsRead: c_uint64 = 0;
           OTF2_Reader_ReadAllGlobalEvents(reader, globalEvtReader, c_ptrTo(totalEventsRead));
           totalEventsReadAcrossReaders += totalEventsRead;

           OTF2_Reader_CloseGlobalEvtReader(reader, globalEvtReader);
         } else {
           logError("Failed to create global event reader in task ", i);
         }

         OTF2_Reader_CloseEvtFiles(reader);
         OTF2_Reader_Close(reader);
       } else {
         logError("Failed to open trace file in task ", i);
       }
    }

    const evtReadTime = sw.elapsed();
    logDebug("Time taken to read events: ", evtReadTime, " seconds");
    sw.clear();

    logDebug("Total events read: ", totalEventsReadAcrossReaders);

    // Merge contexts
    logDebug("Merging contexts...");
    var mergedCtx = try! mergeEvtContexts(evtContexts);
    const mergeTime = sw.elapsed();
    logDebug("Time taken to merge contexts: ", mergeTime, " seconds");
    sw.clear();

    logInfo("Trace loaded in ", global_sw.elapsed(), " seconds");
    logInfo("Writing ", outputFormat:string, " files to directory: ", outputDir);
    writeCallGraphsAndMetrics(mergedCtx, outputFormat);
    logInfo("Finished writing to ", outputDir, " in ", sw.elapsed(), " seconds");
    logInfo("Finished converting trace in ", global_sw.elapsed(), " seconds");
  }

  proc writeCallGraphsAndMetrics(evtCtx: EvtCallbackContext, format: OutputFormat) {
    coforall (group, threads) in evtCtx.callGraphs.toArray() {
      if !evtCtx.evtArgs.processesToTrack.isEmpty() && !evtCtx.evtArgs.processesToTrack.contains(group) {
        logInfo("Skipping group ", group, " as it is not in the processes to track.");
      } else {
        coforall thread in threads.keysToArray() {
          const callGraph = try! threads[thread];
          FastOTF2ConverterCommon.writeCallgraph(callGraph, group, thread, format, outputDir);
        }
      }
    }

    coforall (group, threadMetrics) in evtCtx.metrics.toArray() {
      if !evtCtx.evtArgs.processesToTrack.isEmpty() && !evtCtx.evtArgs.processesToTrack.contains(group) {
        logInfo("Skipping group ", group, " as it is not in the processes to track.");
      } else {
        FastOTF2ConverterCommon.writeMetrics(group, threadMetrics, format, outputDir);
      }
    }
  }
}
