// Copyright Hewlett Packard Enterprise Development LP.
//
// Event reading pipeline for the converter.
// Provides per-task event reading (readEventsForLocations), the OTF2
// event callbacks (Enter, Leave, Metric — global and local variants),
// and context merging for strategies that partition by location.

module ConverterEvtReaders {
  use FastOTF2;
  use ConverterCommon;
  use CallGraphModule;
  use List;
  use Map;

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
  // Event callbacks
  // -------------------------------------------------------------------------

  proc Enter_callback(location: OTF2_LocationRef,
                      time: OTF2_TimeStamp,
                      userData: c_ptr(void),
                      attributes: c_ptr(OTF2_AttributeList),
                      region: OTF2_RegionRef): OTF2_CallbackCode {
    var ctxPtr = userData: c_ptr(EvtCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;
    ref ctx = ctxPtr.deref();
    ref defCtx = ctx.defContext;

    const (locName, locGroup, regionName) = getLocationAndRegionInfo(defCtx, location, region);
    updateMaps(ctx, locGroup, locName);

    if checkEnterLeaveSkipConditions(ctx, locGroup, regionName) then
      return OTF2_CALLBACK_SUCCESS;

    // Get current time in seconds
    const currentTime = timestampToSeconds(time, defCtx.clockProps);

    // Enter Callgraph
    ref callGraph = try! ctx.callGraphs[locGroup][locName];
    callGraph.enter(currentTime, regionName);

    return OTF2_CALLBACK_SUCCESS;
  }

  proc Leave_callback(location: OTF2_LocationRef,
                      time: OTF2_TimeStamp,
                      userData: c_ptr(void),
                      attributes: c_ptr(OTF2_AttributeList),
                      region: OTF2_RegionRef): OTF2_CallbackCode {
    logTrace("Entering Leave_callback with location=", location, ", region=", region);
    var ctxPtr = userData: c_ptr(EvtCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;
    ref ctx = ctxPtr.deref();
    ref defCtx = ctx.defContext;

    const (locName, locGroup, regionName) = getLocationAndRegionInfo(defCtx, location, region);
    updateMaps(ctx, locGroup, locName);

    if checkEnterLeaveSkipConditions(ctx, locGroup, regionName) then
      return OTF2_CALLBACK_SUCCESS;

    // Get current time in seconds
    const currentTime = timestampToSeconds(time, defCtx.clockProps);

    // Leave Callgraph
    ref callGraph = try! ctx.callGraphs[locGroup][locName];
    callGraph.leave(currentTime); // We ignore regionName here

    return OTF2_CALLBACK_SUCCESS;
  }

  proc Metric_callback(location: OTF2_LocationRef,
                       time: OTF2_TimeStamp,
                       userData: c_ptr(void),
                       attributeList: c_ptr(OTF2_AttributeList),
                       metric: OTF2_MetricRef,
                       numberOfMetrics: c_uint8,
                       typeIDs: c_ptrConst(OTF2_Type),
                       metricValues: c_ptrConst(OTF2_MetricValue)): OTF2_CallbackCode {

    var ctxPtr = userData: c_ptr(EvtCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;
    ref ctx = ctxPtr.deref();
    ref defCtx = ctx.defContext;
    const (locName, locGroup, _) = getLocationAndRegionInfo(defCtx, location, 0);
    // We only handle single metric members for now
    if numberOfMetrics != 1 then {
      logError("Metric event with multiple metrics not supported yet");
      halt("unsupported: multiple metrics per event");
    }

    const (metricName, metricUnit, metricRecorder) = getMetricInfo(defCtx, location, metric);

    // If we are not tracking this metric, skip it (empty metricsToTrack = track all)
    if !ctx.evtArgs.metricsToTrack.isEmpty() && !ctx.evtArgs.metricsToTrack.contains(metricName) {
      logTrace("Skipping metric: ", metricName, " in group ", locGroup);
      return OTF2_CALLBACK_SUCCESS;
    }

    const metricType = typeIDs[0];
    const metricValue = metricValues[0];

    // Get the time for this metric in seconds
    const currentTime = timestampToSeconds(time, defCtx.clockProps);
    // Update the seen groups, call graphs, and metrics maps
    updateMaps(ctx, locGroup, locName);

    ref metrics = ctx.metrics;

    // Store the metric value if this metric is one we want to track.
    // If either the value has changed or if this is the first value for this metric
    // we append it to the list for this metric.
    try {
      // First confirm the metric list exists
      if !metrics[locGroup].contains(metricName) && (ctx.evtArgs.metricsToTrack.contains(metricName) || ctx.evtArgs.metricsToTrack.isEmpty()) {
        metrics[locGroup][metricName] = new list((real(64), OTF2_Type, OTF2_MetricValue));
      }

      if metrics[locGroup][metricName].isEmpty() ||
        metrics[locGroup][metricName].last[2] != metricValue {
        metrics[locGroup][metricName].pushBack((currentTime, metricType, metricValue));
      }
    } catch e {
      logError("Error storing metric: ", e);
      logError("  locGroup: ", locGroup);
      logError("  metricName: ", metricName);
      logError("  metrics.contains(locGroup): ", metrics.contains(locGroup));
      if metrics.contains(locGroup) {
        try! logError("  metrics[locGroup].contains(metricName): ", metrics[locGroup].contains(metricName));
      }
    }

    return OTF2_CALLBACK_SUCCESS;
  }

  // ---------------------------------------------------------------------------
  // Local event reader callbacks (for per-location reading)
  //
  // Same logic as the global callbacks above, but with the extra
  // `eventPosition` parameter required by OTF2_EvtReaderCallback_*.
  // ---------------------------------------------------------------------------

  proc Enter_local_callback(location: OTF2_LocationRef,
                            time: OTF2_TimeStamp,
                            eventPosition: uint(64),
                            userData: c_ptr(void),
                            attributes: c_ptr(OTF2_AttributeList),
                            region: OTF2_RegionRef): OTF2_CallbackCode {
    return Enter_callback(location, time, userData, attributes, region);
  }

  proc Leave_local_callback(location: OTF2_LocationRef,
                            time: OTF2_TimeStamp,
                            eventPosition: uint(64),
                            userData: c_ptr(void),
                            attributes: c_ptr(OTF2_AttributeList),
                            region: OTF2_RegionRef): OTF2_CallbackCode {
    return Leave_callback(location, time, userData, attributes, region);
  }

  proc Metric_local_callback(location: OTF2_LocationRef,
                             time: OTF2_TimeStamp,
                             eventPosition: uint(64),
                             userData: c_ptr(void),
                             attributeList: c_ptr(OTF2_AttributeList),
                             metric: OTF2_MetricRef,
                             numberOfMetrics: c_uint8,
                             typeIDs: c_ptrConst(OTF2_Type),
                             metricValues: c_ptrConst(OTF2_MetricValue)): OTF2_CallbackCode {
    return Metric_callback(location, time, userData, attributeList,
                           metric, numberOfMetrics, typeIDs, metricValues);
  }

  // ---------------------------------------------------------------------------
  // Context merging (used by parallel reader strategies that partition by location)
  // ---------------------------------------------------------------------------

  proc mergeEvtContexts(const ref contexts: [] EvtCallbackContext): EvtCallbackContext throws {
    if contexts.size == 0 {
      halt("No contexts to merge");
    }

    // Start with the first context
    // We assume all contexts have the same evtArgs and defContext
    var mergedCtx = new EvtCallbackContext(contexts[0].evtArgs, contexts[0].defContext);

    // Merge the rest
    for i in 0..<contexts.size {
      ref ctx = contexts[i];

      // Merge seenGroups
      for group in ctx.seenGroups.keys() {
        const threads = ctx.seenGroups[group];
        if !mergedCtx.seenGroups.contains(group) {
          mergedCtx.seenGroups[group] = threads;
        } else {
          mergedCtx.seenGroups[group] += threads;
        }
      }

      // Merge callGraphs
      for group in ctx.callGraphs.keys() {
        const threadMap = ctx.callGraphs[group];
        if !mergedCtx.callGraphs.contains(group) {
          mergedCtx.callGraphs[group] = threadMap;
        } else {
          for thread in threadMap.keys() {
            const callGraph = threadMap[thread];
            if mergedCtx.callGraphs[group].contains(thread) {
              logWarn("Duplicate thread ", thread, " in group ", group, " during merge.");
            }
            mergedCtx.callGraphs[group].add(thread, callGraph);
          }
        }
      }

      // Merge metrics
      for group in ctx.metrics.keys() {
        const threadMap = ctx.metrics[group];
        if !mergedCtx.metrics.contains(group) {
          mergedCtx.metrics[group] = threadMap;
        } else {
          for metric in threadMap.keys() {
            const metricList = threadMap[metric];
            if mergedCtx.metrics[group].contains(metric) {
              for entry in metricList {
                mergedCtx.metrics[group][metric].pushBack(entry);
              }
            } else {
              mergedCtx.metrics[group].add(metric, metricList);
            }
          }
        }
      }
    }

    return mergedCtx;
  }
}
