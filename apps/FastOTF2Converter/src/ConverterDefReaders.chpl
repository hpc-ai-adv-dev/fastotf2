// Copyright Hewlett Packard Enterprise Development LP.
//
// Global definition reading for the converter.
// Opens the OTF2 archive, registers definition callbacks, reads all
// global definitions, and returns the populated DefCallbackContext.

module ConverterDefReaders {
  use FastOTF2;
  use ConverterCommon;
  use Time;

  // -------------------------------------------------------------------------
  // DefReadResult — returned by readGlobalDefinitions with timing breakdown
  // -------------------------------------------------------------------------

  record DefReadResult {
    var defCtx: DefCallbackContext;
    var numberOfLocations: c_uint64;
    var openTime: real;   // time to open OTF2 archive
    var setupTime: real;  // time to set up callbacks and context
    var readTime: real;   // time to read all global definitions
  }

  // -------------------------------------------------------------------------
  // readGlobalDefinitions — open reader, register callbacks, read defs, close
  // -------------------------------------------------------------------------

  proc readGlobalDefinitions(trace: string): DefReadResult {
    var sw: stopwatch;
    sw.start();

    var reader = OTF2_Reader_Open(trace.c_str());
    if reader == nil {
      logError("Failed to open trace");
      halt("failed to open trace");
    }

    const openTime = sw.elapsed();
    logDebug("Time to open OTF2 archive: ", openTime, " seconds");
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
    const setupTime = sw.elapsed();
    logDebug("Time to set up definition callbacks and context: ", setupTime, " seconds");

    sw.clear();
    var definitionsRead: c_uint64 = 0;
    OTF2_Reader_ReadAllGlobalDefinitions(
      reader, globalDefReader, c_ptrTo(definitionsRead));
    const defReadTime = sw.elapsed();

    logTrace("Global definitions read: ", definitionsRead);
    logDebug("Time to read global definitions: ", defReadTime, " seconds");

    OTF2_Reader_Close(reader);

    return new DefReadResult(defCtx, numberOfLocations, openTime, setupTime, defReadTime);
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
}
