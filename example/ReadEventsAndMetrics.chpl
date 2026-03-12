// Copyright Hewlett Packard Enterprise Development LP.

module ReadEventsAndMetrics {
  // Mason example: mason run --example ReadEventsAndMetrics.chpl
  use OTF2;
  use Time;
  use List;


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
    var members: [0..<numberOfMetrics] OTF2_MetricMemberRef;
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
    const groupName = if ctx.stringIds.contains(name) then ctx.stringTable[name] else "UnknownGroup";
    // Check if this location has a creating group
    if creatingLocationGroup != 0 then
      writeln("Location group ", groupName, " created by group ID ", creatingLocationGroup);
    else
      writeln("Location group ", groupName, " has no creating group");
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
    const locName = if ctx.stringIds.contains(name) then ctx.stringTable[name] else "UnknownLocation";
    ctx.locationIds += location;
    var loc = new Location(name=locName, group=locationGroup);
    ctx.locationTable[location] = loc;
    // writeln("Registered location: ", ctx.locationTable[location]);
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
    const regionName = if ctx.stringIds.contains(name) then ctx.stringTable[name] else "UnknownRegion";
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
    const memberName = if ctx.stringIds.contains(name) then ctx.stringTable[name] else "UnknownMetricMember";
    const unitName = if ctx.stringIds.contains(unit) then ctx.stringTable[unit] else "UnknownUnit";
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
    var members: [0..<numberOfMetrics] OTF2_MetricMemberRef;
    for i in 0..<numberOfMetrics {
      members[i] = metricMembers[i];
    }
    mctx.metricClassTable[self] = new MetricClass(numberOfMetrics=numberOfMetrics, members=members);
    // writeln("Registered metric class: ", mctx.metricClassTable[self]);
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
    // writeln("Registered metric instance: ", mctx.metricInstanceTable[self]);
    return OTF2_CALLBACK_SUCCESS;
  }

  // --- Event data structures (aligned with parallel implementation) ---
  record EventInfo {
    var time: OTF2_TimeStamp;
    var eventName: string;
    var locationName: string;
    var locationGroup: string;
    var regionName: string;
    var isMetric: bool = false;
    var metricValue: real(64);
    var metricUnit: string;
    var metricRecorder: string;
  }

  record AllEventsData {
    var enterCount: uint;
    var leaveCount: uint;
    var metricCount: uint;
    var events: list(EventInfo);
  }

  record EvtCallbackContext {
    var defContext: DefCallbackContext;
    var eventData: AllEventsData;
  }

  proc getLocationAndRegionInfo(defCtx: DefCallbackContext,
                       location: OTF2_LocationRef,
                       region: OTF2_RegionRef) : (string, string, string) {
    const locName = if defCtx.locationIds.contains(location) then defCtx.locationTable[location].name else "UnknownLocation";
    const locGroup = if defCtx.locationIds.contains(location) then
                 let lgid = defCtx.locationTable[location].group in
                 if defCtx.locationGroupIds.contains(lgid) then defCtx.locationGroupTable[lgid].name else "UnknownLocationGroup"
               else "UnknownLocationGroup";
    const regionName = if defCtx.regionIds.contains(region) then defCtx.regionTable[region] else "UnknownRegion";
    return (locName, locGroup, regionName);
  }

  // --- Event callbacks (now operate on EvtCallbackContext) ---
  proc Enter_store_and_count(location: OTF2_LocationRef,
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
    ref evd = ctx.eventData;
    evd.enterCount += 1;
    const (locName, locGroup, regionName) = getLocationAndRegionInfo(defCtx, location, region);
    evd.events.pushBack(new EventInfo(time, "Enter", locName, locGroup, regionName));
    return OTF2_CALLBACK_SUCCESS;
  }

  proc Leave_store_and_count(location: OTF2_LocationRef,
                             time: OTF2_TimeStamp,
                             userData: c_ptr(void),
                             attributes: c_ptr(OTF2_AttributeList),
                             region: OTF2_RegionRef): OTF2_CallbackCode {
    //writeln("Debug: Entering Leave_store_and_count with location=", location, ", region=", region);
    // Get pointers to the context and event data
    var ctxPtr = userData: c_ptr(EvtCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;
    ref ctx = ctxPtr.deref();
    ref defCtx = ctx.defContext;
    ref evd = ctx.eventData;
    evd.leaveCount += 1;
    const (locName, locGroup, regionName) = getLocationAndRegionInfo(defCtx, location, region=0);
    evd.events.pushBack(new EventInfo(time, "Leave", locName, locGroup, regionName));
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
        const metricMemberRef = metricClass.members[0];
        if metricCtx.metricMemberIds.contains(metricMemberRef) {
          const metricMember = metricCtx.metricMemberTable[metricMemberRef];
          metricName = metricMember.name;
          metricUnit = metricMember.unit;
        } else {
          metricName = "UnknownMetricMember";
          metricUnit = "UnknownUnit";
        }
      } else {
        halt("Metric class with multiple members not supported yet");
      }
    } else {
      metricName = "UnknownMetricClass";
      metricUnit = "UnknownUnit";
    }
    return (metricName, metricUnit, metricRecorder);
  }

  proc Metric_store_and_count(location: OTF2_LocationRef,
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
    ref evd = ctx.eventData;
    evd.metricCount += 1;
    // Get metric info like name, unit, value, recorder location
    const (locName, locGroup, _) = getLocationAndRegionInfo(defCtx, location, 0);
    // We only handle single metric members for now
    if numberOfMetrics != 1 then
      halt("Metric event with multiple metrics not supported yet");

    const (metricName, metricUnit, metricRecorder) = getMetricInfo(defCtx, location, metric);

    const metricValue = metricValues[0].floating_point;
    // Add this to the event list
    evd.events.pushBack(new EventInfo(time, metricName, locName, locGroup, "N/A", true, metricValue, metricUnit, metricRecorder));
    return OTF2_CALLBACK_SUCCESS;
  }

  // Config constant for command-line argument
  // Usage: ./ReadEventsAndMetrics --tracePath=/path/to/traces.otf2
  config const tracePath: string = "sample-traces/simple-mi300-example-run/traces.otf2";

  proc main() {
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

    // Definition context & callbacks
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
    var evtCtx = new EvtCallbackContext(defCtx);
    var globalEvtReader = OTF2_Reader_GetGlobalEvtReader(reader);
    var evtCallbacks = OTF2_GlobalEvtReaderCallbacks_New();
    OTF2_GlobalEvtReaderCallbacks_SetEnterCallback(evtCallbacks,
                                                   c_ptrTo(Enter_store_and_count): c_fn_ptr);
    OTF2_GlobalEvtReaderCallbacks_SetLeaveCallback(evtCallbacks,
                                                   c_ptrTo(Leave_store_and_count): c_fn_ptr);
    OTF2_GlobalEvtReaderCallbacks_SetMetricCallback(evtCallbacks,
                                                   c_ptrTo(Metric_store_and_count): c_fn_ptr);

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


    // Print event summary
    ref data = evtCtx.eventData;
    writeln("Event Summary:");
    writeln(" Total number of events: ", totalEventsRead);
    writeln(" Event types and their counts:");
    writeln("  Enter: ", data.enterCount, " events");
    writeln("  Leave: ", data.leaveCount, " events");
    writeln("  Metric: ", data.metricCount, " events");
    writeln(" Total events stored in list: ", data.events.size);

    // Print the stats for unique locations
    printUniqueLocationAndRegionStats(defCtx, false);
    printMetricStats(defCtx, data, false);
  }


  proc printUniqueLocationAndRegionStats(defCtx: DefCallbackContext, verbose: bool) {
    // Print the stats for unique location groups
    writeln("Total Unique Location Groups: ", defCtx.locationGroupIds.size);
    if verbose {
      writeln("Unique Location Groups:");
      for lgId in defCtx.locationGroupIds {
        const lgName = defCtx.locationGroupTable[lgId].name;
        if lgName != "" {
          writeln(lgName);
        }
      }
    }

    writeln("Total Unique Locations: ", defCtx.locationIds.size);
    if verbose {
      writeln("Unique Locations:");
      for locId in defCtx.locationIds {
        const locName = defCtx.locationTable[locId].name;
        if locName != "" {
          writeln(locName);
          // Optionally, print the location group as well
          const lgId = defCtx.locationTable[locId].group;
          if defCtx.locationGroupIds.contains(lgId) {
            const lgName = defCtx.locationGroupTable[lgId].name;
            writeln("  In Location Group: ", lgName);
          }
        }
      }
    }

    // Print the stats for unique regions
    writeln("Total Unique Regions: ", defCtx.regionIds.size);
    if verbose {
      writeln("Unique Regions:");
      for regionId in defCtx.regionIds {
        writeln(defCtx.regionTable[regionId]);
      }
    }

  }

  proc printMetricStats(defCtx: DefCallbackContext, data: AllEventsData, verbose: bool) {
    ref mctx = defCtx.metricDefContext;
    writeln("Total Unique Metric Members: ", mctx.metricMemberIds.size);
    writeln("Total Unique Metric Classes: ", mctx.metricClassIds.size);
    writeln("Total Unique Metric Instances: ", mctx.metricInstanceIds.size);

    // Print the stats for unique metric members
    if mctx.metricMemberIds.size > 0 {
      writeln("Unique Metric Members:");
      for mmId in mctx.metricMemberIds {
        const mm = mctx.metricMemberTable[mmId];
        writeln(" Metric Member Name: ", mm.name, ", Unit: ", mm.unit);
      }
    }

    // Print the stats for unique metric classes
    if mctx.metricClassIds.size > 0 {
      writeln("Unique Metric Classes:");
      for mcId in mctx.metricClassIds {
        const mc = mctx.metricClassTable[mcId];
        write(" Metric Class ID: ", mcId, ", Number of Members: ", mc.numberOfMetrics, ", Members: ");
        for i in 0..<mc.numberOfMetrics {
          const mmId = mc.members[i];
          if mctx.metricMemberIds.contains(mmId) {
            const mm = mctx.metricMemberTable[mmId];
            write(mm.name, " (", mm.unit, ")");
            if i < mc.numberOfMetrics - 1 then write(", ");
          }
        }
        writeln();
      }
    }

    // Print the stats for unique metric instances
    if mctx.metricInstanceIds.size > 0 {
      writeln("Unique Metric Instances:");
      for miId in mctx.metricInstanceIds {
        const mi = mctx.metricInstanceTable[miId];
        const recorderName = if defCtx.locationIds.contains(mi.recorder) then defCtx.locationTable[mi.recorder].name else "UnknownLocation";
        var metricClassName = "UnknownMetricClass";
        if mctx.metricClassIds.contains(mi.metricClass) {
          const mc = mctx.metricClassTable[mi.metricClass];
          if mc.numberOfMetrics > 0 {
            const mmId = mc.members[0];
            if mctx.metricMemberIds.contains(mmId) {
              const mm = mctx.metricMemberTable[mmId];
              metricClassName = mm.name;
            }
          }
        }
        writeln(" Metric Instance ID: ", miId, ", Metric Class: ", metricClassName, ", Recorder Location: ", recorderName);
      }
    }
    // Print the stats for metrics recorded in events
    writeln("Total Metric Events Recorded: ", data.metricCount);
    writeln("Metric Events Details:");
    for event in data.events {
      if verbose && event.isMetric then
        writeln(" Time: ", event.time, ", Metric: ", event.eventName, ", Value: ", event.metricValue, " ", event.metricUnit, ", Recorder: ", event.metricRecorder, ", Location: ", event.locationName, ", Location Group: ", event.locationGroup);
    }
  }
}
