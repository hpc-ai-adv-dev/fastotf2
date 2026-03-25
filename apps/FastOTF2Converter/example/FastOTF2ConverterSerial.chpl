// Copyright Hewlett Packard Enterprise Development LP.

module FastOTF2ConverterSerial {
  use FastOTF2;
  use FastOTF2ConverterCommon;
  use FastOTF2ConverterWriters;
  use CallGraphModule;
  use Time;
  use List;
  use Map;
  use IO;

  // Config constants for command-line arguments
  // Usage examples:
  //   ./FastOTF2ConverterSerial --tracePath=/path/to/traces.otf2
  //   ./FastOTF2ConverterSerial --crayTimeOffsetArg=2.5
  //   ./FastOTF2ConverterSerial --metricsToTrackArg="metric1,metric2,metric3"
  //   ./FastOTF2ConverterSerial --processesToTrackArg="process1,process2"
  //   ./FastOTF2ConverterSerial --outputFormatArg=CSV
  //   ./FastOTF2ConverterSerial --tracePath=/path/to/traces.otf2 --crayTimeOffsetArg=1.5 --metricsToTrackArg="metric1,metric2"

  config const tracePath: string = "../../sample-traces/simple-mi300-example-run/traces.otf2";
  config const crayTimeOffsetArg: real(64) = 1.0;
  config const metricsToTrackArg: string = "A2rocm_smi:::energy_count:device=0,A2rocm_smi:::energy_count:device=2,A2rocm_smi:::energy_count:device=4,A2rocm_smi:::energy_count:device=6,A2coretemp:::craypm:accel0_energy,A2coretemp:::craypm:accel1_energy,A2coretemp:::craypm:accel2_energy,A2coretemp:::craypm:accel3_energy";
  config const processesToTrackArg: string = ""; // Empty string means track all processes
  config const outputFormatArg: string = "CSV";

  proc main(args: [] string) {
    var outputFormat: OutputFormat;
    try {
      outputFormat = parseOutputFormat(outputFormatArg);
    } catch e {
      logError(e.message());
      return;
    }

    var sw: stopwatch;
    sw.start();

    var reader = OTF2_Reader_Open(tracePath.c_str());
    if reader == nil {
      logError("Failed to open trace");
      return;
    }

    const openTime = sw.elapsed();
    logInfo("Time taken to open OTF2 archive: ", openTime, " seconds");
    sw.clear(); // Restart stopwatch for next timing

    OTF2_Reader_SetSerialCollectiveCallbacks(reader);

    var numberOfLocations: c_uint64 = 0;
    OTF2_Reader_GetNumberOfLocations(reader, c_ptrTo(numberOfLocations));
    logInfo("Number of locations: ", numberOfLocations);

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
    logInfo("Global definitions read: ", definitionsRead);

    const defReadTime = sw.elapsed();
    logInfo("Time taken to read global definitions: ", defReadTime, " seconds");
    sw.clear(); // Restart stopwatch for next timing

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
    logInfo("Time taken to read local definitions and mark event files: ", markTime, " seconds");
    sw.clear();
    if successfulOpenDefFiles then OTF2_Reader_CloseDefFiles(reader);

    // Event reading setup with new event context

    // Parse metrics to track from config argument
    var metricsToTrack: domain(string);
    if metricsToTrackArg != "" {
      var metricsArray = metricsToTrackArg.split(",");
      for metric in metricsArray {
        metricsToTrack += metric.strip();
      }
    }

    // Parse processes to track from config argument
    var processesToTrack: domain(string);
    if processesToTrackArg != "" {
      var processesArray = processesToTrackArg.split(",");
      for process in processesArray {
        processesToTrack += process.strip();
      }
    }

    var evtArgs = new EvtCallbackArgs(processesToTrack=processesToTrack,
                                      metricsToTrack=metricsToTrack,
                                      excludeMPI=true,
                                      excludeHIP=true,
                                      crayTimeOffset=crayTimeOffsetArg);

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
    logInfo("Time taken to read events: ", evtReadTime, " seconds");
    sw.clear();

    OTF2_Reader_CloseGlobalEvtReader(reader, globalEvtReader);
    OTF2_Reader_CloseEvtFiles(reader);
    OTF2_Reader_Close(reader);
    const closeTime = sw.elapsed();
    sw.stop();
    logInfo("Total time: ", openTime + defReadTime + markTime + evtReadTime + closeTime, " seconds");
    writeCallGraphsAndMetrics(evtCtx, outputFormat);
  }

  proc writeCallgraph(callGraph: shared CallGraph, group: string, thread: string, format: OutputFormat) {
    const filename = callgraphFilename(group, thread, format);
    logInfo("Writing to file: ", filename);

    select format {
      when OutputFormat.CSV {
        try {
          FastOTF2ConverterWriters.writeCallgraphCSV(callGraph, group, thread, filename);
        } catch e {
          logError("Error writing callgraph to CSV: ", e);
        }
      }
      when OutputFormat.PARQUET {
        try {
          FastOTF2ConverterWriters.writeCallgraphParquet(callGraph, group, thread, filename);
        } catch e {
          logError("Error writing callgraph to PARQUET: ", e);
          exit(1);
        }
      }
    }
  }

  proc writeMetrics(group: string, threadMetrics: map(string, list((real(64), OTF2_Type, OTF2_MetricValue))), format: OutputFormat) {
    const filename = metricsFilename(group, format);
    logInfo("Writing to file: ", filename);

    select format {
      when OutputFormat.CSV {
        try {
          FastOTF2ConverterWriters.writeMetricsCSV(group, threadMetrics, filename);
        } catch e {
          logError("Error writing metrics to CSV: ", e);
        }
      }
      when OutputFormat.PARQUET {
        try {
          FastOTF2ConverterWriters.writeMetricsParquet(group, threadMetrics, filename);
        } catch e {
          logError("Error writing metrics to PARQUET: ", e);
          exit(1);
        }
      }
    }
  }

  proc writeCallGraphsAndMetrics(ref evtCtx: EvtCallbackContext, format: OutputFormat) {
    for (group, threads) in evtCtx.callGraphs.toArray() {
      if !evtCtx.evtArgs.processesToTrack.isEmpty() && !evtCtx.evtArgs.processesToTrack.contains(group) {
        logInfo("Skipping group ", group, " as it is not in the processes to track.");
      } else {
        for thread in threads.keysToArray() {
          const callGraph = try! threads[thread];
          writeCallgraph(callGraph, group, thread, format);
        }
      }
    }

    for (group, threadMetrics) in evtCtx.metrics.toArray() {
      if !evtCtx.evtArgs.processesToTrack.isEmpty() && !evtCtx.evtArgs.processesToTrack.contains(group) {
        logInfo("Skipping group ", group, " as it is not in the processes to track.");
      } else {
        writeMetrics(group, threadMetrics, format);
      }
    }
  }

  proc printCallGraphAndMetrics(ref evtCtx: EvtCallbackContext, verbose: bool = false) {
    // Output call graphs and metrics summary to console
    logDebug("\n--- Call Graphs ---");
    logDebug("Total location groups with call graphs: ", evtCtx.callGraphs.size);
    for locGroup in evtCtx.callGraphs.keys() {
      logDebug("Location Group: ", locGroup);
      const locMap = evtCtx.callGraphs[locGroup];
      for locName in locMap.keys() {
        logDebug("  Thread: ", locName);
      }
    }

    logDebug("\n--- Metrics Summary ---");
    var totalMetricsStored: int = 0;
    for locGroup in evtCtx.metrics.keys() {
      logDebug("Location Group: ", locGroup);
      const metricMap = evtCtx.metrics[locGroup];
      for metricName in metricMap.keys() {
        const values = metricMap[metricName];
        logDebug("  Metric: ", metricName, ", Count: ", values.size);
        if values.size > 0 {
          logDebug("First Value: ", values[0]);
        }
        totalMetricsStored += values.size;
      }
    }
    logDebug("Total metrics stored: ", totalMetricsStored);
  }
}
