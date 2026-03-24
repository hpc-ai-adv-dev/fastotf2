// Copyright Hewlett Packard Enterprise Development LP.

module FastOTF2ConverterSerial {
  use FastOTF2;
  use FastOTF2ConverterWriters;
  use Time;
  use List;
  use Map;
  use CallGraphModule;
  use IO;
  import Math.inf;

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
    writeln("Trace Clock Properties:");
    writeln(" Timer Resolution. : ", clockProps.timerResolution);
    writeln(" Global Offset     : ", clockProps.globalOffset);
    writeln(" Trace Length      : ", clockProps.traceLength);
    writeln(" Realtime Timestamp: ", clockProps.realtimeTimestamp);
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
    // writeln("Registered string: ", ctx.stringTable[str]);
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
    // if creatingLocationGroup != 0 then
    //   writeln("Location group ", groupName, " created by group ID ", creatingLocationGroup);
    // else
    //   writeln("Location group ", groupName, " has no creating group");
    const creatingGroupName = if ctx.locationGroupIds.contains(creatingLocationGroup) then ctx.locationGroupTable[creatingLocationGroup].name else "None";
    // Add location group to the lookup table
    ctx.locationGroupIds += self;
    ctx.locationGroupTable[self] = new LocationGroup(name=groupName, creatingLocationGroup=creatingGroupName);
    // writeln("Registered location group: ", ctx.locationGroupTable[self]);
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
    writeln("Registered location ID=", location, ": ", ctx.locationTable[location], " in group ID ", locationGroup, " (", if ctx.locationGroupIds.contains(locationGroup) then ctx.locationGroupTable[locationGroup].name else "UnknownGroup", ")");
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
    // writeln("Registered region: ", regionName);
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
    // writeln("Registered metric member: ", mctx.metricMemberTable[self]);
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
    // writeln("Registered metric instance ID=", self, " with class=", metricClass, " recorder=", recorder);
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
    // writeln("Registered metric class recorder: metric=", metric, " recorder=", recorder);
    return OTF2_CALLBACK_SUCCESS;
  }

  record EvtCallbackArgs {
    const processesToTrack: domain(string);
    const metricsToTrack: domain(string);
    const crayTimeOffset: real(64);
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
      writeln("New group and thread: ", location, " in group ", locGroup);
    } else if !seenGroups[locGroup].contains(location) {
      seenGroups[locGroup] += location;
      writeln("New thread: ", location, " in existing group ", locGroup);
    }
    }

    try! {
    // Update call graphs
    ref callGraphs = ctx.callGraphs;
    if !callGraphs.contains(locGroup) {
      writeln("New call graph group: ", locGroup);
      callGraphs[locGroup] = new map(string, shared CallGraph);
    }
    if !callGraphs[locGroup].contains(location) {
      writeln("New call graph for thread: ", location, " in group ", locGroup);
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
        writeln("New metric list for metric: ", metric, " in group ", locGroup);
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
    const regionNameLower = regionName.toLower();
    if regionNameLower.size >= 3 {
      const prefix = regionNameLower[0..2];
      if prefix == "mpi" || prefix == "hip" {
        return true; // Skip this event
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
    //writeln("Debug: Entering Enter_store_and_count with location=", location, ", region=", region);
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
    //writeln("Debug: Entering Leave_callback with location=", location, ", region=", region);
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
        writeln("WARNING: Metric class with ", metricClass.numberOfMetrics, " members - only processing first member");
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
    if numberOfMetrics != 1 then
      halt("Metric event with multiple metrics not supported yet");

    // Question: Should we check if this metric is one we want to track? Python version does not do that


    const (metricName, metricUnit, metricRecorder) = getMetricInfo(defCtx, location, metric);

    // If we are not tracking this metric, skip it
    if !ctx.evtArgs.metricsToTrack.contains(metricName) {
      return OTF2_CALLBACK_SUCCESS;
    }

    const metricType = typeIDs[0];
    const metricValue = metricValues[0];

    // Get the time for this metric in seconds
    var currentTime = timestampToSeconds(time, defCtx.clockProps);
    // Adjust for craypm metrics, as they are reported with a delay
    if metricName.toLower().find("cray") >= 0 && ctx.evtArgs.crayTimeOffset != 0.0 {
      currentTime -= ctx.evtArgs.crayTimeOffset;
    }
    // Update the seen groups, call graphs, and metrics maps
    updateMaps(ctx, locGroup, locName);

    ref metrics = ctx.metrics;

    // Store the metric value if this metric is one we want to track
    // If either the value has changed or if this is the first value for this metric
    // We append it to the list for this metric
    try {
      if metrics[locGroup][metricName].isEmpty() ||
         metrics[locGroup][metricName].last[2] != metricValue {
        metrics[locGroup][metricName].pushBack((currentTime, metricType, metricValue));
        // writeln("Stored metric value: ", metricValue, " for metric ", metricName, " in location ", locName, " of group ", locGroup, " at time ", currentTime);
      }
    } catch e {
      writeln("Error storing metric: ", e);
      writeln("  locGroup: ", locGroup);
      writeln("  metricName: ", metricName);
      writeln("  metrics.contains(locGroup): ", metrics.contains(locGroup));
      if metrics.contains(locGroup) {
        try! writeln("  metrics[locGroup].contains(metricName): ", metrics[locGroup].contains(metricName));
      }
    }

    return OTF2_CALLBACK_SUCCESS;
  }

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
      writeln(e.message());
      return;
    }

    var sw: stopwatch;
    sw.start();

    var reader = OTF2_Reader_Open(tracePath.c_str());
    if reader == nil {
      writeln("Failed to open trace");
      return;
    }

    const openTime = sw.elapsed();
    writef("Time taken to open OTF2 archive: %.2dr seconds\n", openTime);
    sw.clear(); // Restart stopwatch for next timing

    OTF2_Reader_SetSerialCollectiveCallbacks(reader);

    var numberOfLocations: c_uint64 = 0;
    OTF2_Reader_GetNumberOfLocations(reader, c_ptrTo(numberOfLocations));
    writeln("Number of locations: ", numberOfLocations);


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
    writeln("Global definitions read: ", definitionsRead);

    const defReadTime = sw.elapsed();
    writef("Time taken to read global definitions: %.2dr seconds\n", defReadTime);
    sw.clear(); // Restart stopwatch for next timing

    // Select all locations
    for loc in defCtx.locationIds {
      // writeln("Selecting location ", loc);
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
    writeln("Time taken to read local definition files and mark all local event files for reading: ", markTime, " seconds");
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

    // Use the config const for crayTimeOffset
    var crayPmOffset: real(64) = crayTimeOffsetArg;
    var evtArgs = new EvtCallbackArgs(processesToTrack=processesToTrack,
                                      metricsToTrack=metricsToTrack,
                                      crayTimeOffset=crayPmOffset);

    // Create event callaback context
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
    writeln("Time taken to read events: ", evtReadTime, " seconds");
    sw.clear();

    OTF2_Reader_CloseGlobalEvtReader(reader, globalEvtReader);
    OTF2_Reader_CloseEvtFiles(reader);
    OTF2_Reader_Close(reader);
    const closeTime = sw.elapsed();
    sw.stop();
    writeln("Total time: ", openTime + defReadTime + markTime + evtReadTime + closeTime, " seconds");
    writeCallGraphsAndMetrics(evtCtx, outputFormat);
  }

  proc failUnimplementedFormat(format: OutputFormat) {
    writeln(unimplementedFormatMessage(format));
    exit(1);
  }

  proc writeCallgraph(callGraph: shared CallGraph, group: string, thread: string, format: OutputFormat) {
    const filename = callgraphFilename(group, thread, format);
    writeln("Writing to file: ", filename);

    select format {
      when OutputFormat.CSV {
        try {
          FastOTF2ConverterWriters.writeCallgraphCSV(callGraph, group, thread, filename);
        } catch e {
          writeln("Error writing callgraph to CSV: ", e);
        }
      }
      when OutputFormat.PARQUET {
        try {
          FastOTF2ConverterWriters.writeCallgraphParquet(callGraph, filename);
        } catch e {
          writeln("Error writing callgraph to PARQUET: ", e);
          exit(1);
        }
      }
    }
  }

  proc writeMetrics(group: string, threadMetrics: map(string, list((real(64), OTF2_Type, OTF2_MetricValue))), format: OutputFormat) {
    const filename = metricsFilename(group, format);
    writeln("Writing to file: ", filename);

    select format {
      when OutputFormat.CSV {
        try {
          FastOTF2ConverterWriters.writeMetricsCSV(group, threadMetrics, filename);
        } catch e {
          writeln("Error writing metrics to CSV: ", e);
        }
      }
      when OutputFormat.PARQUET {
        try {
          FastOTF2ConverterWriters.writeMetricsParquet(threadMetrics, filename);
        } catch e {
          writeln("Error writing metrics to PARQUET: ", e);
          exit(1);
        }
      }
    }
  }

  proc writeCallGraphsAndMetrics(evtCtx: EvtCallbackContext, format: OutputFormat) {
    forall (group, threads) in evtCtx.callGraphs.toArray() {
      if !evtCtx.evtArgs.processesToTrack.isEmpty() && !evtCtx.evtArgs.processesToTrack.contains(group) {
        writeln("Skipping group ", group, " as it is not in the processes to track.");
        continue;
      }
      forall thread in threads.keysToArray() {
        const callGraph = try! threads[thread];
        writeCallgraph(callGraph, group, thread, format);
      }
    }

    forall (group, threadMetrics) in evtCtx.metrics.toArray() {
      if !evtCtx.evtArgs.processesToTrack.isEmpty() && !evtCtx.evtArgs.processesToTrack.contains(group) {
        writeln("Skipping group ", group, " as it is not in the processes to track.");
        continue;
      }
      writeMetrics(group, threadMetrics, format);
    }
  }

  proc printCallGraphAndMetrics(evtCtx: EvtCallbackContext, verbose: bool = false) {
    // Output call graphs and metrics summary to console
    writeln("\n--- Call Graphs ---");
    writeln("Total location groups with call graphs: ", evtCtx.callGraphs.size);
    for (locGroup, locMap) in evtCtx.callGraphs.items() {
      writeln("Location Group: ", locGroup);
      for (locName, callGraph) in locMap.items() {
        writeln("  Thread: ", locName);
      }
    }

    writeln("\n--- Metrics Summary ---");
    var totalMetricsStored: int = 0;
    for (locGroup, metricMap) in evtCtx.metrics.items() {
      writeln("Location Group: ", locGroup);
      for (metricName, values) in metricMap.items() {
        write("  Metric: ", metricName, ", Count: ", values.size);
        if values.size > 0 {
          writeln(", First Value: ", values[0]);
        } else {
          writeln();
        }
        totalMetricsStored += values.size;
      }
    }
    writeln("Total metrics stored: ", totalMetricsStored);

  }
}
