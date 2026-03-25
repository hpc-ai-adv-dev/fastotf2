// Copyright Hewlett Packard Enterprise Development LP.
//
// Shared types, callbacks, and helpers used by both the parallel and serial
// converter implementations.

module FastOTF2ConverterCommon {
  use FastOTF2;
  use List;
  use Map;
  use CallGraphModule;
  use IO;

  // ---------------------------------------------------------------------------
  // Logging infrastructure
  // ---------------------------------------------------------------------------

  enum LogLevel {
    NONE,
    ERROR,
    WARN,
    INFO,
    DEBUG,
    TRACE
  }

  var log: LogLevel = LogLevel.INFO;

  const BLUE = "\x1b[94m";
  const GREEN = "\x1b[92m";
  const YELLOW = "\x1b[93m";
  const RED = "\x1b[91m";
  const ENDC = "\x1b[0m";

  proc logError(args ...?n) {
    if log >= LogLevel.ERROR {
      writeln(RED, "[ERROR] ", ENDC, (...args));
    }
  }

  proc logWarn(args ...?n) {
    if log >= LogLevel.WARN {
      writeln(YELLOW, "[WARN] ", ENDC, (...args));
    }
  }

  proc logInfo(args ...?n) {
    if log >= LogLevel.INFO {
      writeln(GREEN, "[INFO] ", ENDC, (...args));
    }
  }

  proc logDebug(args ...?n) {
    if log >= LogLevel.DEBUG {
      writeln(BLUE, "[DEBUG] ", ENDC, (...args));
    }
  }

  proc logTrace(args ...?n) {
    if log >= LogLevel.TRACE {
      writeln(RED, "[TRACE] ", ENDC, (...args));
    }
  }

  // ---------------------------------------------------------------------------
  // Record types
  // ---------------------------------------------------------------------------

  // TODO(refactor): Move ClockProperties into the FastOTF2 library package.
  record ClockProperties {
    // See https://perftools.pages.jsc.fz-juelich.de/cicd/otf2/tags/latest/html/group__records__definition.html#ClockProperties
    var timerResolution: uint(64);
    var globalOffset: uint(64);
    var traceLength: uint(64);
    var realtimeTimestamp: uint(64);
  }

  // TODO(refactor): Move definition records into the FastOTF2 library package.
  record LocationGroup {
    var name: string;
    var creatingLocationGroup: string;
  }
  record Location {
    var name: string;
    var group: OTF2_LocationGroupRef;
  }

  record MetricMember {
    var name: string;
    var unit: string;
  }

  // TODO(refactor): Unify MetricClass and MetricInstance under a common base.
  record MetricClass {
    var numberOfMetrics: c_uint8;
    var firstMemberID: OTF2_MetricMemberRef;  // Store just the first member ID directly
  }

  record MetricInstance {
    var metricClass: OTF2_MetricRef;
    var recorder: OTF2_LocationRef;
  }

  record MetricDefContext {
    var metricClassIds: domain(OTF2_MetricRef);
    var metricClassTable: [metricClassIds] MetricClass;
    var metricInstanceIds: domain(OTF2_MetricRef);
    var metricInstanceTable: [metricInstanceIds] MetricInstance;
    var metricMemberIds: domain(OTF2_MetricMemberRef);
    var metricMemberTable: [metricMemberIds] MetricMember;
    var metricClassRecorderIds: domain(OTF2_MetricRef);
    var metricClassRecorderTable: [metricClassRecorderIds] OTF2_LocationRef;
  }

  record DefCallbackContext {
    var locationGroupIds: domain(OTF2_LocationGroupRef);
    var locationGroupTable: [locationGroupIds] LocationGroup;
    var locationIds: domain(OTF2_LocationRef);
    var locationTable: [locationIds] Location;
    var regionIds: domain(OTF2_RegionRef);
    var regionTable: [regionIds] string;
    var stringIds: domain(OTF2_StringRef);
    var stringTable: [stringIds] string;
    var clockProps: ClockProperties;
    var metricDefContext: MetricDefContext;
  }

  record EvtCallbackArgs {
    const processesToTrack: domain(string);
    const metricsToTrack: domain(string);
    const excludeMPI: bool = false;
    const excludeHIP: bool = false;
    const crayTimeOffset: real(64) = 0.0;
  }

  record EvtCallbackContext {
    const evtArgs: EvtCallbackArgs;
    var defContext: DefCallbackContext;
    var seenGroups: map(string, domain(string));
    // Call Graphs are per location group and per location (thread)
    var callGraphs: map(string, map(string, shared CallGraph));
    // Metrics recorded per location group and per location (thread)
    var metrics: map(string, map(string, list((real(64), OTF2_Type, OTF2_MetricValue))));

    proc init(evtArgs: EvtCallbackArgs,
              defContext: DefCallbackContext) {
      this.evtArgs = evtArgs;
      this.defContext = defContext;
      this.seenGroups = new map(string, domain(string));
      this.callGraphs = new map(string, map(string, shared CallGraph));
      this.metrics = new map(string, map(string, list((real(64), OTF2_Type, OTF2_MetricValue))));
    }
  }

  // ---------------------------------------------------------------------------
  // Definition callbacks
  // ---------------------------------------------------------------------------

  proc registerClockProperties(userData: c_ptr(void),
                              timerResolution: uint(64),
                              globalOffset: uint(64),
                              traceLength: uint(64),
                              realtimeTimestamp: uint(64)): OTF2_CallbackCode {
    var defContextPtr = userData: c_ptr(DefCallbackContext);
    if defContextPtr == nil then return OTF2_CALLBACK_ERROR;
    ref defContext = defContextPtr.deref();
    ref clockProps = defContext.clockProps;
    clockProps.timerResolution = timerResolution;
    clockProps.globalOffset = globalOffset;
    clockProps.traceLength = traceLength;
    clockProps.realtimeTimestamp = realtimeTimestamp;
    logTrace("Trace Clock Properties:");
    logTrace(" Timer Resolution. : ", clockProps.timerResolution);
    logTrace(" Global Offset     : ", clockProps.globalOffset);
    logTrace(" Trace Length      : ", clockProps.traceLength);
    logTrace(" Realtime Timestamp: ", clockProps.realtimeTimestamp);
    return OTF2_CALLBACK_SUCCESS;
  }

  proc GlobDefString_Register(userData: c_ptr(void),
                              strRef: OTF2_StringRef,
                              strName: c_ptrConst(c_uchar)):
                              OTF2_CallbackCode {
    var ctxPtr = userData: c_ptr(DefCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;
    ref ctx = ctxPtr.deref();
    // Add string to the lookup table
    ctx.stringIds += strRef;
    if strName != nil {
      try! ctx.stringTable[strRef] = string.createCopyingBuffer(strName);
    } else {
      ctx.stringTable[strRef] = "UnknownString";
    }
    logTrace("Registered string: ", ctx.stringTable[strRef]);
    return OTF2_CALLBACK_SUCCESS;
  }

  proc GlobDefLocationGroup_Register(userData: c_ptr(void),
                                     self : OTF2_LocationGroupRef,
                                     name : OTF2_StringRef,
                                     locationGroupType : OTF2_LocationGroupType,
                                     systemTreeParent : OTF2_SystemTreeNodeRef,
                                     creatingLocationGroup : OTF2_LocationGroupRef): OTF2_CallbackCode {
    // Get the reference to the context record
    var ctxPtr = userData: c_ptr(DefCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;
    ref ctx = ctxPtr.deref();
    // Lookup name in string table
    const groupName = if ctx.stringIds.contains(name) && ctx.stringTable[name] != "" then ctx.stringTable[name] else "UnknownGroup";
    // Check if this location has a creating group
    if creatingLocationGroup != 0 then
      logTrace("Location group ", groupName, " created by group ID ", creatingLocationGroup);
    else
      logTrace("Location group ", groupName, " has no creating group");
    const creatingGroupName = if ctx.locationGroupIds.contains(creatingLocationGroup) then ctx.locationGroupTable[creatingLocationGroup].name else "None";
    // Add location group to the lookup table
    ctx.locationGroupIds += self;
    ctx.locationGroupTable[self] = new LocationGroup(name=groupName, creatingLocationGroup=creatingGroupName);
    logTrace("Registered location group: ", ctx.locationGroupTable[self]);
    return OTF2_CALLBACK_SUCCESS;
  }

  proc GlobDefLocation_Register(userData: c_ptr(void),
                                location: OTF2_LocationRef,
                                name: OTF2_StringRef,
                                locationType: OTF2_LocationType,
                                numberOfEvents: c_uint64,
                                locationGroup: OTF2_LocationGroupRef):
                                OTF2_CallbackCode {
    // Get the reference to the context record
    var ctxPtr = userData: c_ptr(DefCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;
    ref ctx = ctxPtr.deref();
    // Lookup name in string table
    const locName = if ctx.stringIds.contains(name) && ctx.stringTable[name] != "" then ctx.stringTable[name] else "UnknownLocation";
    ctx.locationIds += location;
    var loc = new Location(name=locName, group=locationGroup);
    ctx.locationTable[location] = loc;
    logTrace("Registered location ID=", location, ": ", ctx.locationTable[location], " in group ID ", locationGroup, " (", if ctx.locationGroupIds.contains(locationGroup) then ctx.locationGroupTable[locationGroup].name else "UnknownGroup", ")");
    return OTF2_CALLBACK_SUCCESS;
  }

  proc GlobDefRegion_Register(userData: c_ptr(void),
                              region: OTF2_RegionRef,
                              name: OTF2_StringRef,
                              canonicalName: OTF2_StringRef,
                              description: OTF2_StringRef,
                              regionRole: OTF2_RegionRole,
                              paradigm: OTF2_Paradigm,
                              regionFlags: OTF2_RegionFlag,
                              sourceFile: OTF2_StringRef,
                              beginLineNumber: c_uint32,
                              endLineNumber: c_uint32):
                              OTF2_CallbackCode {
    // Get the reference to the context record
    var ctxPtr = userData: c_ptr(DefCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;
    ref ctx = ctxPtr.deref();
    // Lookup name in string table
    const regionName = if ctx.stringIds.contains(name) && ctx.stringTable[name] != "" then ctx.stringTable[name] else "UnknownRegion";
    // Add region to the lookup table
    ctx.regionIds += region;
    ctx.regionTable[region] = regionName;
    logTrace("Registered region: ", regionName);
    return OTF2_CALLBACK_SUCCESS;
  }

  proc GlobDefMetricMember_Register(userData: c_ptr(void),
                                    self: OTF2_MetricMemberRef,
                                    name: OTF2_StringRef,
                                    description: OTF2_StringRef,
                                    metricType: OTF2_MetricType,
                                    mode: OTF2_MetricMode,
                                    valueType: OTF2_Type,
                                    base: OTF2_Base,
                                    exponent: c_int64,
                                    unit: OTF2_StringRef): OTF2_CallbackCode {
    var ctxPtr = userData: c_ptr(DefCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;
    ref ctx = ctxPtr.deref();
    ref mctx = ctx.metricDefContext;
    mctx.metricMemberIds += self;
    const memberName = if ctx.stringIds.contains(name) && ctx.stringTable[name] != "" then ctx.stringTable[name] else "UnknownMetricMember";
    const unitName = if ctx.stringIds.contains(unit) && ctx.stringTable[unit] != "" then ctx.stringTable[unit] else "UnknownUnit";
    mctx.metricMemberTable[self] = new MetricMember(name=memberName, unit=unitName);
    logTrace("Registered metric member: ", mctx.metricMemberTable[self]);
    return OTF2_CALLBACK_SUCCESS;
  }

  proc GlobDefMetricClass_Register(userData: c_ptr(void),
                                   self: OTF2_MetricRef,
                                   numberOfMetrics: c_uint8,
                                   metricMembers: c_ptrConst(OTF2_MetricMemberRef),
                                   metricOccurrence: OTF2_MetricOccurrence,
                                   recorderKind: OTF2_RecorderKind): OTF2_CallbackCode {
    var ctxPtr = userData: c_ptr(DefCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;
    ref ctx = ctxPtr.deref();
    ref mctx = ctx.metricDefContext;
    mctx.metricClassIds += self;
    const firstMember = if numberOfMetrics > 0 then metricMembers[0] else 0;
    mctx.metricClassTable[self] = new MetricClass(numberOfMetrics=numberOfMetrics, firstMemberID=firstMember);
    return OTF2_CALLBACK_SUCCESS;
  }

  proc GlobDefMetricInstance_Register(userData: c_ptr(void),
                                      self: OTF2_MetricRef,
                                      metricClass: OTF2_MetricRef,
                                      recorder: OTF2_LocationRef,
                                      metricScope: OTF2_MetricScope,
                                      scope: c_uint64): OTF2_CallbackCode {
    var ctxPtr = userData: c_ptr(DefCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;
    ref ctx = ctxPtr.deref();
    ref mctx = ctx.metricDefContext;
    mctx.metricInstanceIds += self;
    mctx.metricInstanceTable[self] = new MetricInstance(metricClass=metricClass, recorder=recorder);
    logTrace("Registered metric instance ID=", self, " with class=", metricClass, " recorder=", recorder);
    return OTF2_CALLBACK_SUCCESS;
  }

  proc GlobDefMetricClassRecorder_Register(userData: c_ptr(void),
                                           metric: OTF2_MetricRef,
                                           recorder: OTF2_LocationRef): OTF2_CallbackCode {
    var ctxPtr = userData: c_ptr(DefCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;
    ref ctx = ctxPtr.deref();
    ref mctx = ctx.metricDefContext;
    mctx.metricClassRecorderIds += metric;
    mctx.metricClassRecorderTable[metric] = recorder;
    logTrace("Registered metric class recorder: metric=", metric, " recorder=", recorder);
    return OTF2_CALLBACK_SUCCESS;
  }

  // ---------------------------------------------------------------------------
  // Helper procs
  // ---------------------------------------------------------------------------

  proc timestampToSeconds(ts: OTF2_TimeStamp, clockProps: ClockProperties): real(64) {
    if clockProps.timerResolution == 0 then
      return 0.0;
    // We use this start_time to normalize timestamps to start from zero
    // We don't use a ProgramBegin event because each MPI rank will have it's own
    // and we want a global start time
    const start_time = clockProps.globalOffset;
    if ts < start_time {
      return -1.0 * ((start_time - ts):real(64) / clockProps.timerResolution);
    }
    return (ts - start_time):real(64) / clockProps.timerResolution;
  }

  proc getLocationAndRegionInfo(defCtx: DefCallbackContext,
                       location: OTF2_LocationRef,
                       region: OTF2_RegionRef) : (string, string, string) {
    const locName = if defCtx.locationIds.contains(location) then defCtx.locationTable[location].name else "UnknownLocation";
    var locGroup = "UnknownLocationGroup";
    if defCtx.locationIds.contains(location) {
      const lgid = defCtx.locationTable[location].group;
      if defCtx.locationGroupIds.contains(lgid) {
        const locationGroup = defCtx.locationGroupTable[lgid];
        // Use creating_location_group if it exists (matching Python behavior)
        locGroup = if locationGroup.creatingLocationGroup != "None" && locationGroup.creatingLocationGroup != "" 
                   then locationGroup.creatingLocationGroup
                   else locationGroup.name;
      }
    }
    const regionName = if defCtx.regionIds.contains(region) then defCtx.regionTable[region] else "UnknownRegion";
    return (locName, locGroup, regionName);
  }

  proc updateMaps(ref ctx: EvtCallbackContext, locGroup: string, location: string) {
    // Update seen groups
    try! {
      ref seenGroups = ctx.seenGroups;
      if !seenGroups.contains(locGroup) {
        seenGroups[locGroup] = {location};
        logDebug("New group and thread: ", location, " in group ", locGroup);
      } else if !seenGroups[locGroup].contains(location) {
        seenGroups[locGroup] += location;
        logDebug("New thread: ", location, " in existing group ", locGroup);
      }
    }

    try! {
    // Update call graphs
    ref callGraphs = ctx.callGraphs;
    if !callGraphs.contains(locGroup) {
      logDebug("New call graph group: ", locGroup);
      callGraphs[locGroup] = new map(string, shared CallGraph);
    }
    if !callGraphs[locGroup].contains(location) {
      logDebug("New call graph for thread: ", location, " in group ", locGroup);
      // TODO(chapel-bug): map[key] = new shared CallGraph() triggers an
      // ownership issue in the Chapel compiler. Using add() works around it.
      callGraphs[locGroup].add(location, new shared CallGraph());
    }
    }

    // Update metrics
    ref metrics = ctx.metrics;
    if !metrics.contains(locGroup) {
      metrics[locGroup] = new map(string, list((real(64), OTF2_Type, OTF2_MetricValue)));
      for metric in ctx.evtArgs.metricsToTrack {
        metrics[locGroup][metric] = new list((real(64), OTF2_Type, OTF2_MetricValue));
        logDebug("New metric list for metric: ", metric, " in group ", locGroup);
      }
    }
  }

  proc getMetricInfo(defCtx: DefCallbackContext,
                     location: OTF2_LocationRef,
                     metric: OTF2_MetricRef): (string, string, string) {
    var metricName: string;
    var metricUnit: string;
    var metricRecorder: string;

    ref metricCtx = defCtx.metricDefContext;
    var metricClassRef: OTF2_MetricRef;
    // This metric can be a metric class or a metric instance, check both
    // If it is a metric instance, it will also have a recorder location
    // Otherwise the recorder is the same as the location of the event
    if metricCtx.metricInstanceIds.contains(metric) {
      const mInstance = metricCtx.metricInstanceTable[metric];
      metricRecorder = if defCtx.locationIds.contains(mInstance.recorder) then defCtx.locationTable[mInstance.recorder].name else "UnknownLocation";
      metricClassRef = mInstance.metricClass;
    } else {
      metricClassRef = metric;
      (metricRecorder, _, _) = getLocationAndRegionInfo(defCtx, location, 0);
    }
    if metricCtx.metricClassIds.contains(metricClassRef) {
      const metricClass = metricCtx.metricClassTable[metricClassRef];
      if metricClass.numberOfMetrics == 1 { // We only handle single metric members for now
        const metricMemberRef = metricClass.firstMemberID;
        if metricCtx.metricMemberIds.contains(metricMemberRef) {
          const metricMember = metricCtx.metricMemberTable[metricMemberRef];
          metricName = metricMember.name;
          metricUnit = metricMember.unit;
        } else {
          metricName = "UnknownMetricMember";
          metricUnit = "UnknownUnit";
        }
      } else {
        logWarn("Metric class with ", metricClass.numberOfMetrics, " members - only processing first member");
        // Instead of halting, just process the first member
        const metricMemberRef = metricClass.firstMemberID;
        if metricCtx.metricMemberIds.contains(metricMemberRef) {
          const metricMember = metricCtx.metricMemberTable[metricMemberRef];
          metricName = metricMember.name;
          metricUnit = metricMember.unit;
        } else {
          metricName = "UnknownMetricMember";
          metricUnit = "UnknownUnit";
        }
      }
    } else {
      metricName = "UnknownMetricClass";
      metricUnit = "UnknownUnit";
    }
    return (metricName, metricUnit, metricRecorder);
  }

  proc checkEnterLeaveSkipConditions(const ref ctx: EvtCallbackContext,
                                     locGroup: string,
                                     regionName: string): bool {
    // Skip events for processes not in the tracking list (empty = track all)
    if (ctx.evtArgs.processesToTrack.size > 0) &&
      (!ctx.evtArgs.processesToTrack.contains(locGroup)) {
      return true; // Skip this event
    }
    if (!ctx.evtArgs.excludeHIP && !ctx.evtArgs.excludeMPI) {
      return false; // Do not skip
    }
    const regionNameLower = regionName.toLower();
    if regionNameLower.size >= 3 {
      const prefix = regionNameLower[0..2];
      if prefix == "mpi" && ctx.evtArgs.excludeMPI {
        logTrace("Skipping MPI region: ", regionName, " in group ", locGroup);
        return true;
      }
      if prefix == "hip" && ctx.evtArgs.excludeHIP {
        logTrace("Skipping HIP region: ", regionName, " in group ", locGroup);
        return true;
      }
    }
    return false; // Do not skip
  }

  // ---------------------------------------------------------------------------
  // Event callbacks
  // ---------------------------------------------------------------------------

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
    var currentTime = timestampToSeconds(time, defCtx.clockProps);
    // Apply CrayPM time offset if configured
    if ctx.evtArgs.crayTimeOffset != 0.0 && metricName.toLower().find("cray") >= 0 {
      currentTime -= ctx.evtArgs.crayTimeOffset;
    }
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
  // Context merging (used by parallel reader)
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
