// Copyright Hewlett Packard Enterprise Development LP.
//
// Shared read-side pipeline for all converter strategies.
// Provides argument parsing, global definition reading, event callback
// argument construction, per-task event reading, and output writing.
//
// This is the read-side analog to ConverterWriters (the write-side).
// Strategy modules import this and control only how work is distributed.

module ConverterDefReaders {
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

  // -------------------------------------------------------------------------
  // ConverterConfig — holds all parsed command-line arguments
  // -------------------------------------------------------------------------

  record ConverterConfig {
    var strategy: string;
    var trace: string;
    var metrics: string;
    var processes: string;
    var outputDir: string;
    var outputFormat: OutputFormat;
    var excludeMPI: bool;
    var excludeHIP: bool;
  }

  // -------------------------------------------------------------------------
  // parseConverterArgs — full ArgumentParser for all common flags
  // -------------------------------------------------------------------------

  proc parseConverterArgs(programArgs: [] string): ConverterConfig throws {
    var conf: ConverterConfig;

    var parser = new argumentParser(addHelp=true);

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

    const defaultStrategy = if numLocales > 1
      then "locgroup_dist_balanced"
      else "locgroup_dynamic";
    var strategyArg = parser.addOption(
      name="strategy",
      defaultValue=defaultStrategy,
      numArgs=1,
      help="Partition strategy: serial, loc_block, loc_dynamic, "
           + "locgroup_block, locgroup_dynamic, locgroup_dist_block, "
           + "locgroup_blockdist_dynamic, locgroup_dist_balanced"
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

    conf.strategy = strategyArg.value();
    conf.trace = traceArg.value();
    conf.metrics = metricsArg.value();
    conf.processes = processesArg.value();
    conf.outputDir = outputDirArg.value();
    conf.excludeMPI = excludeMPIArg.valueAsBool();
    conf.excludeHIP = excludeHIPArg.valueAsBool();

    try {
      log = logArg.value(): LogLevel;
    } catch e {
      logError("Invalid log level: ", logArg.value(),
               ". Use one of: NONE, ERROR, WARN, INFO, DEBUG, or TRACE.");
      halt("invalid log level");
    }

    try {
      conf.outputFormat = parseOutputFormat(formatArg.value());
    } catch e {
      logError(e.message());
      halt("invalid output format");
    }

    if conf.excludeMPI then
      logInfo("Excluding MPI functions from callgraph output");
    if conf.excludeHIP then
      logInfo("Excluding HIP functions from callgraph output");

    return conf;
  }

  // -------------------------------------------------------------------------
  // validatePaths — check trace exists, create outputDir if needed
  // -------------------------------------------------------------------------

  proc validatePaths(const ref conf: ConverterConfig) throws {
    if !exists(conf.trace) {
      logError("Trace file does not exist: ", conf.trace);
      halt("trace file not found");
    }
    if !exists(conf.outputDir) {
      logInfo("Output directory does not exist, creating: ", conf.outputDir);
      mkdir(conf.outputDir);
    }
  }

  // -------------------------------------------------------------------------
  // readGlobalDefinitions — open reader, register callbacks, read defs, close
  // -------------------------------------------------------------------------

  proc readGlobalDefinitions(trace: string): (DefCallbackContext, c_uint64) {
    var sw: stopwatch;
    sw.start();

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

    var defCtx = new DefCallbackContext();
    var globalDefReader = OTF2_Reader_GetGlobalDefReader(reader);
    var defCallbacks = OTF2_GlobalDefReaderCallbacks_New();

    OTF2_GlobalDefReaderCallbacks_SetClockPropertiesCallback(
      defCallbacks, c_ptrTo(registerClockProperties): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetStringCallback(
      defCallbacks, c_ptrTo(GlobDefString_Register): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetLocationGroupCallback(
      defCallbacks, c_ptrTo(GlobDefLocationGroup_Register): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetLocationCallback(
      defCallbacks, c_ptrTo(GlobDefLocation_Register): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetRegionCallback(
      defCallbacks, c_ptrTo(GlobDefRegion_Register): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetMetricMemberCallback(
      defCallbacks, c_ptrTo(GlobDefMetricMember_Register): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetMetricClassCallback(
      defCallbacks, c_ptrTo(GlobDefMetricClass_Register): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetMetricInstanceCallback(
      defCallbacks, c_ptrTo(GlobDefMetricInstance_Register): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetMetricClassRecorderCallback(
      defCallbacks, c_ptrTo(GlobDefMetricClassRecorder_Register): c_fn_ptr);

    OTF2_Reader_RegisterGlobalDefCallbacks(
      reader, globalDefReader, defCallbacks, c_ptrTo(defCtx): c_ptr(void));
    OTF2_GlobalDefReaderCallbacks_Delete(defCallbacks);

    var definitionsRead: c_uint64 = 0;
    OTF2_Reader_ReadAllGlobalDefinitions(
      reader, globalDefReader, c_ptrTo(definitionsRead));
    logTrace("Global definitions read: ", definitionsRead);

    const defReadTime = sw.elapsed();
    logTrace("Time taken to read global definitions: %.2dr seconds\n", defReadTime);

    OTF2_Reader_Close(reader);

    return (defCtx, numberOfLocations);
  }

  // -------------------------------------------------------------------------
  // buildEvtCallbackArgs — parse metrics/processes strings into EvtCallbackArgs
  // -------------------------------------------------------------------------

  proc buildEvtCallbackArgs(const ref conf: ConverterConfig): EvtCallbackArgs {
    var metricsToTrack: domain(string);
    if conf.metrics != "" {
      for metric in conf.metrics.split(",") {
        metricsToTrack += metric.strip();
      }
    }

    var processesToTrack: domain(string);
    if conf.processes != "" {
      for process in conf.processes.split(",") {
        processesToTrack += process.strip();
      }
    }

    return new EvtCallbackArgs(
      processesToTrack=processesToTrack,
      metricsToTrack=metricsToTrack,
      excludeMPI=conf.excludeMPI,
      excludeHIP=conf.excludeHIP
    );
  }

  // -------------------------------------------------------------------------
  // readEventsForLocations — the key abstraction
  //
  // Opens a fresh OTF2 reader, selects the given locations, registers
  // Enter/Leave/Metric callbacks, reads all events, then closes.
  // Returns the number of events read.
  // -------------------------------------------------------------------------

  proc readEventsForLocations(
    trace: string,
    locations: [] OTF2_LocationRef,
    ref evtCtx: EvtCallbackContext
  ): c_uint64 {
    var reader = OTF2_Reader_Open(trace.c_str());
    if reader == nil {
      logError("Failed to open trace file for event reading");
      return 0;
    }

    OTF2_Reader_SetSerialCollectiveCallbacks(reader);

    // Select locations
    for loc in locations {
      OTF2_Reader_SelectLocation(reader, loc);
    }

    OTF2_Reader_OpenEvtFiles(reader);

    // Mark event files for reading
    for loc in locations {
      var _evtReader = OTF2_Reader_GetEvtReader(reader, loc);
    }

    var eventsRead: c_uint64 = 0;

    var globalEvtReader = OTF2_Reader_GetGlobalEvtReader(reader);
    if globalEvtReader != nil {
      var evtCallbacks = OTF2_GlobalEvtReaderCallbacks_New();

      OTF2_GlobalEvtReaderCallbacks_SetEnterCallback(
        evtCallbacks, c_ptrTo(Enter_callback): c_fn_ptr);
      OTF2_GlobalEvtReaderCallbacks_SetLeaveCallback(
        evtCallbacks, c_ptrTo(Leave_callback): c_fn_ptr);
      OTF2_GlobalEvtReaderCallbacks_SetMetricCallback(
        evtCallbacks, c_ptrTo(Metric_callback): c_fn_ptr);

      OTF2_Reader_RegisterGlobalEvtCallbacks(
        reader, globalEvtReader, evtCallbacks,
        c_ptrTo(evtCtx): c_ptr(void));
      OTF2_GlobalEvtReaderCallbacks_Delete(evtCallbacks);

      OTF2_Reader_ReadAllGlobalEvents(
        reader, globalEvtReader, c_ptrTo(eventsRead));

      OTF2_Reader_CloseGlobalEvtReader(reader, globalEvtReader);
    } else {
      logError("Failed to create global event reader");
    }

    OTF2_Reader_CloseEvtFiles(reader);
    OTF2_Reader_Close(reader);

    return eventsRead;
  }

  // -------------------------------------------------------------------------
  // writeOutputForContext — write callgraphs and metrics for one EvtCallbackContext
  // -------------------------------------------------------------------------

  proc writeOutputForContext(
    ref evtCtx: EvtCallbackContext,
    format: OutputFormat,
    outputDir: string
  ) {
    for (group, threads) in evtCtx.callGraphs.toArray() {
      if !evtCtx.evtArgs.processesToTrack.isEmpty() &&
         !evtCtx.evtArgs.processesToTrack.contains(group) {
        logTrace("Skipping group ", group, " (not in processes to track)");
      } else {
        for thread in threads.keysToArray() {
          const callGraph = try! threads[thread];
          ConverterCommon.writeCallgraph(callGraph, group, thread, format, outputDir);
        }
      }
    }

    for (group, threadMetrics) in evtCtx.metrics.toArray() {
      if !evtCtx.evtArgs.processesToTrack.isEmpty() &&
         !evtCtx.evtArgs.processesToTrack.contains(group) {
        logTrace("Skipping group ", group, " (not in processes to track)");
      } else {
        ConverterCommon.writeMetrics(group, threadMetrics, format, outputDir);
      }
    }
  }

  // -------------------------------------------------------------------------
  // buildGroupLocationMap — build location-group ownership map
  // -------------------------------------------------------------------------

  proc buildGroupLocationMap(
    const ref defCtx: DefCallbackContext
  ): map(OTF2_LocationGroupRef, list(OTF2_LocationRef)) throws {
    var groupLocationMap: map(OTF2_LocationGroupRef, list(OTF2_LocationRef));
    for locId in defCtx.locationIds {
      const loc = defCtx.locationTable[locId];
      const gid = loc.group;
      groupLocationMap[gid].pushBack(locId);
    }

    logDebug("Found ", groupLocationMap.size, " location groups");
    for gid in groupLocationMap.keys() {
      logDebug("  Group ", gid, " (",
               if defCtx.locationGroupIds.contains(gid)
                 then defCtx.locationGroupTable[gid].name
                 else "UnknownGroup",
               "): ", groupLocationMap[gid].size, " locations");
    }

    return groupLocationMap;
  }

  // -------------------------------------------------------------------------
  // orderedGroupIds — deterministic ordering of group IDs
  // -------------------------------------------------------------------------

  proc orderedGroupIds(
    const ref defCtx: DefCallbackContext,
    const ref groupLocationMap: map(OTF2_LocationGroupRef, list(OTF2_LocationRef))
  ): [] OTF2_LocationGroupRef {
    const totalGroups = groupLocationMap.size;
    var groupIds: [0..<totalGroups] OTF2_LocationGroupRef;
    var idx = 0;

    // First pass: add groups in definition order
    for gid in defCtx.locationGroupIds {
      if groupLocationMap.contains(gid) {
        groupIds[idx] = gid;
        idx += 1;
      }
    }

    // Second pass: pick up any groups not in locationGroupIds (safety)
    if idx < totalGroups {
      for gid in groupLocationMap.keys() {
        var seen = false;
        for j in 0..<idx {
          if groupIds[j] == gid { seen = true; break; }
        }
        if !seen {
          groupIds[idx] = gid;
          idx += 1;
          if idx == totalGroups then break;
        }
      }
    }

    return groupIds;
  }

  // -------------------------------------------------------------------------
  // locationsForGroups — collect all locations for a list of group IDs
  // -------------------------------------------------------------------------

  proc locationsForGroups(
    const ref groupIds: [] OTF2_LocationGroupRef,
    const ref groupLocationMap: map(OTF2_LocationGroupRef, list(OTF2_LocationRef))
  ): [] OTF2_LocationRef throws {
    var totalLocs = 0;
    for gid in groupIds do totalLocs += groupLocationMap[gid].size;

    var locs: [0..<totalLocs] OTF2_LocationRef;
    var idx = 0;
    for gid in groupIds {
      for loc in groupLocationMap[gid] {
        locs[idx] = loc;
        idx += 1;
      }
    }
    return locs;
  }
}
