// Copyright Hewlett Packard Enterprise Development LP.
module TraceToCSVParallel {
  use OTF2;
  use Time;
  use List;
  use Map;
  use CallGraphModule;
  use IO;
  use Path;
  use FileSystem;
  use ArgumentParser;

  import Math.inf;

  enum LogLevel {
    NONE,
    ERROR,
    WARN,
    INFO,
    DEBUG,
    TRACE
  }

  var trace: string = "./traces.otf2";
  var metrics: string = ""; // Empty string means track all metrics
  var processes: string = ""; // Empty string means track all processes
  var excludeMPI: bool = false;
  var excludeHIP: bool = false;
  var outputDir: string = ".";
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


  // This record should be in a Chapel OTF2 module since it is common for all readers
  // but for simplicity, we keep it here for now.
  record ClockProperties {
    // See https://perftools.pages.jsc.fz-juelich.de/cicd/otf2/tags/latest/html/group__records__definition.html#ClockProperties
    var timerResolution: uint(64);
    var globalOffset: uint(64);
    var traceLength: uint(64);
    var realtimeTimestamp: uint(64);
  }

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

  // These records should be classes and moved into a proper Chapel OTF2 module
  // but for simplicity, we keep them here for now.
  // They are also not feature complete but sufficient for the current needs.
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

  // Metric class and instance should inherit from a common Metric base class
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

  // --- Definition callbacks ---
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

  record EvtCallbackArgs {
    const processesToTrack: domain(string);
    const metricsToTrack: domain(string);
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
      callGraphs[locGroup].add(location, new shared CallGraph());
      // For whatever reason
      // callGraphs[locGroup][location] = new shared CallGraph();
      // causes issues, so we use add() instead

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

  proc checkEnterLeaveSkipConditions(const ref ctx: EvtCallbackContext,
                                     locGroup: string,
                                     regionName: string): bool {
    // Check if we are tracking this process
    // I don't know how to get "all processes" in Chapel so we don't do this check for now
    // if !ctx.evtArgs.processesToTrack.contains(locGroup) then
    //   return true; // Skip this event

    // Check for other skip conditions
    if (ctx.evtArgs.processesToTrack.size > 0) &&
      (!ctx.evtArgs.processesToTrack.contains(locGroup)) {
      return true; // Skip this event
    }
    if (!excludeHIP && !excludeMPI) {
      return false; // Do not skip
    }
    const regionNameLower = regionName.toLower();
    if regionNameLower.size >= 3 {
      const prefix = regionNameLower[0..2];
      if prefix == "mpi" && excludeMPI {
        logTrace("Skipping MPI region: ", regionName, " in group ", locGroup);
        return true; // Skip this event if MPI exclusion is enabled and region starts with "mpi"
      }
      if prefix == "hip" && excludeHIP {
        logTrace("Skipping HIP region: ", regionName, " in group ", locGroup);
        return true; // Skip this event if HIP exclusion is enabled and region starts with "hip"
      }
    }
    return false; // Do not skip
  }

  // --- Event callbacks (now operate on EvtCallbackContext) ---
  proc Enter_callback(location: OTF2_LocationRef,
                      time: OTF2_TimeStamp,
                      userData: c_ptr(void),
                      attributes: c_ptr(OTF2_AttributeList),
                      region: OTF2_RegionRef): OTF2_CallbackCode {
    // Get pointers to the context and event data
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
    logTrace("Debug: Entering Leave_callback with location=", location, ", region=", region);
    // Get pointers to the context and event data
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

  proc Metric_callback(location: OTF2_LocationRef,
                       time: OTF2_TimeStamp,
                       userData: c_ptr(void),
                       attributeList: c_ptr(OTF2_AttributeList),
                       metric: OTF2_MetricRef,
                       numberOfMetrics: c_uint8,
                       typeIDs: c_ptrConst(OTF2_Type),
                       metricValues: c_ptrConst(OTF2_MetricValue)): OTF2_CallbackCode {

    // Get pointers to the context and event data
    var ctxPtr = userData: c_ptr(EvtCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;
    ref ctx = ctxPtr.deref();
    ref defCtx = ctx.defContext;
    // Get metric info like name, unit, value, recorder location
    const (locName, locGroup, _) = getLocationAndRegionInfo(defCtx, location, 0);
    // We only handle single metric members for now
    if numberOfMetrics != 1 then {
      logError("Metric event with multiple metrics not supported yet");
      exit(1);
    }

    // Question: Should we check if this metric is one we want to track? Python version does not do that


    const (metricName, metricUnit, metricRecorder) = getMetricInfo(defCtx, location, metric);

    // If we are not tracking this metric, skip it
    if !ctx.evtArgs.metricsToTrack.contains(metricName) && ctx.evtArgs.metricsToTrack.isEmpty() {
      logTrace("Skipping metric: ", metricName, " in group ", locGroup);
      return OTF2_CALLBACK_SUCCESS;
    }

    const metricType = typeIDs[0];
    const metricValue = metricValues[0];

    // Get the time for this metric in seconds
    var currentTime = timestampToSeconds(time, defCtx.clockProps);
    // Update the seen groups, call graphs, and metrics maps
    updateMaps(ctx, locGroup, locName);

    ref metrics = ctx.metrics;

    // Store the metric value if this metric is one we want to track
    // If either the value has changed or if this is the first value for this metric
    // We append it to the list for this metric
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

  proc mergeEvtContexts(const ref contexts: [] EvtCallbackContext): EvtCallbackContext throws{
    if contexts.size == 0 {
      logError("No contexts to merge");
      exit(1);
    }

    // Start with the first context
    // We assume all contexts have the same evtArgs and defContext
    var mergedCtx = new EvtCallbackContext(contexts[0].evtArgs, contexts[0].defContext);

    // Merge the rest
    for i in 0..<contexts.size {
      ref ctx = contexts[i];

      // Merge seenGroups
      for (group, threads) in ctx.seenGroups.items() {
        if !mergedCtx.seenGroups.contains(group) {
          mergedCtx.seenGroups[group] = threads;
        } else {
          mergedCtx.seenGroups[group] += threads;
        }
      }

      // Merge callGraphs
      for (group, threadMap) in ctx.callGraphs.items() {
        if !mergedCtx.callGraphs.contains(group) {
          mergedCtx.callGraphs[group] = threadMap;
        } else {
          for (thread, callGraph) in threadMap.items() {
            if mergedCtx.callGraphs[group].contains(thread) {
              logWarn("Duplicate thread ", thread, " in group ", group, " during merge.");
            }
             mergedCtx.callGraphs[group].add(thread, callGraph);
          }
        }
      }

      // Merge metrics
      for (group, threadMap) in ctx.metrics.items() {
        if !mergedCtx.metrics.contains(group) {
          mergedCtx.metrics[group] = threadMap;
        } else {
          for (metric, metricList) in threadMap.items() {
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

  proc main(programArgs: [] string) {
    try {
      var parser = new argumentParser(
        addHelp=true // Automatically add --help flag
      );

      var traceArg = parser.addArgument(
        name="trace",
        defaultValue="./traces.otf2",
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
        help="Directory to write output CSV files to"
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
        exit(1);
      }
      if excludeMPI {
        logInfo("Excluding MPI functions from callgraph output");
      }
      if excludeHIP {
        logInfo("Excluding HIP functions from callgraph output");
      }
    } catch e {
      logError("Error parsing arguments: ", e);
      exit(1);
    }

    try {
      if !exists(trace) { logError("Trace file does not exist: ", trace); exit(1); }
    } catch e { logError("Error checking trace file existence: ", e); exit(1); }

    try {
      if !exists(outputDir) {
        logInfo("Output directory does not exist, creating: ", outputDir);
        mkdir(outputDir);
      }
    } catch e { logError("Error checking/creating output directory: ", e); exit(1); }

    var sw: stopwatch;
    var global_sw: stopwatch;
    sw.start();
    global_sw.start();

    var reader = OTF2_Reader_Open(trace.c_str());
    if reader == nil {
      logError("Failed to open trace");
      exit(1);
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

    // Use the config const for crayTimeOffset
    var evtArgs = new EvtCallbackArgs(processesToTrack=processesToTrack,
                                      metricsToTrack=metricsToTrack);

    // Parallel Reading Setup
    const numberOfReaders = here.maxTaskPar;
    logTrace("Number of readers: ", numberOfReaders);

    // Convert locationIds to array for partitioning
    const locationArray : [0..<numberOfLocations] OTF2_LocationRef = for l in defCtx.locationIds do l;
    const totalLocs = locationArray.size;

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
         var numLocationsToReadForThisTask = totalLocs / numberOfReaders;
         const low = i * numLocationsToReadForThisTask;
         const high = if i == numberOfReaders - 1 then totalLocs
                      else (i + 1) * numLocationsToReadForThisTask;

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
    logInfo("Writing CSV files to directory: ", outputDir);
    // Write CSVs
    writeCallGraphsAndMetricsToCSV(mergedCtx);
    logInfo("Finished writing to ", outputDir, " in ", sw.elapsed(), " seconds");
    logInfo("Finished converting trace in ", global_sw.elapsed(), " seconds");
  }

  proc callgraphToCSV(callGraph: shared CallGraph, group: string, thread: string, filename: string) {
    // Convert a CallGraph to a CSV file
    try {
      var outfile = open(joinPath(outputDir, filename), ioMode.cw);
      var writer = outfile.writer(locking=false);

      writer.writeln("Thread,Group,Depth,Name,Start Time,End Time,Duration");

      const intervals = callGraph.getIntervalsBetween(-inf, inf);

      for iv in intervals {
        const start = iv.start;
        const end = if iv.hasEnd then iv.end else inf;
        const duration = end - start;
        const name = if iv.name != "" then iv.name else "Unknown";
        const depth = iv.depth;

        writer.writef("%s,%s,%i,\"%s\",%.15dr,%.15dr,%.15dr\n",
                      thread, group, depth, name, start, end, duration);
      }

      writer.close();
      outfile.close();
    } catch e {
      logError("Error writing callgraph to CSV: ", e);
    }
  }

  proc metricsToCSV(group: string, threadMetrics: map(string, list((real(64), OTF2_Type, OTF2_MetricValue))), filename: string) {
    // Convert metrics to a CSV file
    // Note: In the Python version, metrics are stored as List[Tuple[float, float]] (time, value)
    try {
      var outfile = open(joinPath(outputDir, filename), ioMode.cw);
      var writer = outfile.writer(locking=false);

      writer.writeln("Group,Metric Name,Time,Value");

      for (metricName, values) in threadMetrics.items() {
        for (time, valueType, value) in values {
          if valueType == OTF2_TYPE_INT64 then
            writer.writef("%s,%s,%.15dr,%i\n", group, metricName, time, value.signed_int);
          else if valueType == OTF2_TYPE_UINT64 then
            writer.writef("%s,%s,%.15dr,%u\n", group, metricName, time, value.unsigned_int);
          else if valueType == OTF2_TYPE_DOUBLE then
            writer.writef("%s,%s,%.15dr,%.15dr\n", group, metricName, time, value.floating_point);
        }
      }

      writer.close();
      outfile.close();
    } catch e {
      logError("Error writing metrics to CSV: ", e);
    }
  }

  proc writeCallGraphsAndMetricsToCSV(evtCtx: EvtCallbackContext) {
    // Write call graphs to CSV files

    // cobegin {
    coforall (group, threads) in evtCtx.callGraphs.toArray() {
      if !evtCtx.evtArgs.processesToTrack.isEmpty() && !evtCtx.evtArgs.processesToTrack.contains(group) {
        logInfo("Skipping group ", group, " as it is not in the processes to track.");
      } else {
        coforall thread in threads.keysToArray() {
          const callGraph = try! threads[thread];
          const filename = group + "_" + thread.replace(" ", "_") + "_callgraph.csv";
          logInfo("Writing to file: ", filename);
          callgraphToCSV(callGraph, group, thread, filename);
        }
      }
    }

    // Write metrics to CSV files
    coforall (group, threadMetrics) in evtCtx.metrics.toArray() {
      if !evtCtx.evtArgs.processesToTrack.isEmpty() && !evtCtx.evtArgs.processesToTrack.contains(group) {
        logInfo("Skipping group ", group, " as it is not in the processes to track.");
      } else {
        const filename = group + "_metrics.csv";
        logInfo("Writing to file: ", filename);
        metricsToCSV(group, threadMetrics, filename);
      }
    }
  }

  proc printCallGraphAndMetrics(evtCtx: EvtCallbackContext, verbose: bool = false) {
    // Output call graphs and metrics summary to console
    logDebug("\n--- Call Graphs ---");
    logDebug("Total location groups with call graphs: ", evtCtx.callGraphs.size);
    for (locGroup, locMap) in evtCtx.callGraphs.items() {
      logDebug("Location Group: ", locGroup);
      for (locName, callGraph) in locMap.items() {
        logDebug("  Thread: ", locName);
      }
    }

    logDebug("\n--- Metrics Summary ---");
    var totalMetricsStored: int = 0;
    for (locGroup, metricMap) in evtCtx.metrics.items() {
      logDebug("Location Group: ", locGroup);
      for (metricName, values) in metricMap.items() {
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
