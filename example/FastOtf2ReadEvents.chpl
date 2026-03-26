// Copyright Hewlett Packard Enterprise Development LP.

module FastOtf2ReadEvents {
  use FastOTF2;
  use List;
  use Time;

  record DefCallbackContext {
    var locationIds: domain(OTF2_LocationRef);
    var locationTable: [locationIds] string;
    var regionIds: domain(OTF2_RegionRef);
    var regionTable: [regionIds] string;
    var stringIds: domain(OTF2_StringRef);
    var stringTable: [stringIds] string;
  }

  proc GlobDefStringRegister(userData: c_ptr(void),
                             strRef: OTF2_StringRef,
                             strName: c_ptrConst(c_uchar)): OTF2_CallbackCode {
    var ctxPtr = userData: c_ptr(DefCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;

    ref ctx = ctxPtr.deref();
    ctx.stringIds += strRef;
    if strName != nil {
      try! ctx.stringTable[strRef] = string.createCopyingBuffer(strName);
    } else {
      ctx.stringTable[strRef] = "UnknownString";
    }
    return OTF2_CALLBACK_SUCCESS;
  }

  proc GlobDefLocationRegister(userData: c_ptr(void),
                               location: OTF2_LocationRef,
                               name: OTF2_StringRef,
                               locationType: OTF2_LocationType,
                               numberOfEvents: c_uint64,
                               locationGroup: OTF2_LocationGroupRef): OTF2_CallbackCode {
    var ctxPtr = userData: c_ptr(DefCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;

    ref ctx = ctxPtr.deref();
    const locationName = if ctx.stringIds.contains(name) then ctx.stringTable[name] else "UnknownLocation";
    ctx.locationIds += location;
    ctx.locationTable[location] = locationName;
    return OTF2_CALLBACK_SUCCESS;
  }

  proc GlobDefRegionRegister(userData: c_ptr(void),
                             region: OTF2_RegionRef,
                             name: OTF2_StringRef,
                             canonicalName: OTF2_StringRef,
                             description: OTF2_StringRef,
                             regionRole: OTF2_RegionRole,
                             paradigm: OTF2_Paradigm,
                             regionFlags: OTF2_RegionFlag,
                             sourceFile: OTF2_StringRef,
                             beginLineNumber: c_uint32,
                             endLineNumber: c_uint32): OTF2_CallbackCode {
    var ctxPtr = userData: c_ptr(DefCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;

    ref ctx = ctxPtr.deref();
    const regionName = if ctx.stringIds.contains(name) then ctx.stringTable[name] else "UnknownRegion";
    ctx.regionIds += region;
    ctx.regionTable[region] = regionName;
    return OTF2_CALLBACK_SUCCESS;
  }

  record EventInfo {
    var time: OTF2_TimeStamp;
    var locationName: string;
    var eventName: string;
    var regionName: string;
  }

  record AllEventsData {
    var enterCount: uint;
    var leaveCount: uint;
    var events: list(EventInfo);
  }

  record EvtCallbackContext {
    var defContext: DefCallbackContext;
    var eventData: AllEventsData;
  }

  proc EnterStoreAndCount(location: OTF2_LocationRef,
                          time: OTF2_TimeStamp,
                          userData: c_ptr(void),
                          attributes: c_ptr(OTF2_AttributeList),
                          region: OTF2_RegionRef): OTF2_CallbackCode {
    var ctxPtr = userData: c_ptr(EvtCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;

    ref ctx = ctxPtr.deref();
    ref defCtx = ctx.defContext;
    ref eventData = ctx.eventData;

    eventData.enterCount += 1;
    const locationName = if defCtx.locationIds.contains(location) then defCtx.locationTable[location] else "UnknownLocation";
    const regionName = if defCtx.regionIds.contains(region) then defCtx.regionTable[region] else "UnknownRegion";
    eventData.events.pushBack(new EventInfo(time, locationName, "Enter", regionName));
    return OTF2_CALLBACK_SUCCESS;
  }

  proc LeaveStoreAndCount(location: OTF2_LocationRef,
                          time: OTF2_TimeStamp,
                          userData: c_ptr(void),
                          attributes: c_ptr(OTF2_AttributeList),
                          region: OTF2_RegionRef): OTF2_CallbackCode {
    var ctxPtr = userData: c_ptr(EvtCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;

    ref ctx = ctxPtr.deref();
    ref defCtx = ctx.defContext;
    ref eventData = ctx.eventData;

    eventData.leaveCount += 1;
    const locationName = if defCtx.locationIds.contains(location) then defCtx.locationTable[location] else "UnknownLocation";
    const regionName = if defCtx.regionIds.contains(region) then defCtx.regionTable[region] else "UnknownRegion";
    eventData.events.pushBack(new EventInfo(time, locationName, "Leave", regionName));
    return OTF2_CALLBACK_SUCCESS;
  }

  proc PrintUniqueLocationAndRegionStats(defCtx: DefCallbackContext, verbose: bool) {
    writeln("Total Unique Locations: ", defCtx.locationIds.size);
    if verbose {
      writeln("Unique Locations:");
      for locId in defCtx.locationIds {
        const locName = defCtx.locationTable[locId];
        if locName != "" {
          writeln(locName);
        }
      }
    }

    writeln("Total Unique Regions: ", defCtx.regionIds.size);
    if verbose {
      writeln("Unique Regions:");
      for regionId in defCtx.regionIds {
        writeln(defCtx.regionTable[regionId]);
      }
    }
  }

  config const tracePath = "sample-traces/simple-mi300-example-run/traces.otf2";
  config const verbose = false;

  proc main() {
    var timer: stopwatch;
    timer.start();

    var reader = OTF2_Reader_Open(tracePath.c_str());
    if reader == nil {
      writeln("Failed to open trace: ", tracePath);
      return;
    }

    const openTime = timer.elapsed();
    writef("Time taken to open OTF2 archive: %.2dr seconds\n", openTime);
    timer.clear();

    OTF2_Reader_SetSerialCollectiveCallbacks(reader);

    var numberOfLocations: c_uint64 = 0;
    OTF2_Reader_GetNumberOfLocations(reader, c_ptrTo(numberOfLocations));
    writeln("Number of locations: ", numberOfLocations);

    var defCtx = new DefCallbackContext();
    var globalDefReader = OTF2_Reader_GetGlobalDefReader(reader);
    var defCallbacks = OTF2_GlobalDefReaderCallbacks_New();
    OTF2_GlobalDefReaderCallbacks_SetStringCallback(defCallbacks, c_ptrTo(GlobDefStringRegister): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetLocationCallback(defCallbacks, c_ptrTo(GlobDefLocationRegister): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetRegionCallback(defCallbacks, c_ptrTo(GlobDefRegionRegister): c_fn_ptr);

    OTF2_Reader_RegisterGlobalDefCallbacks(
      reader,
      globalDefReader,
      defCallbacks,
      c_ptrTo(defCtx): c_ptr(void)
    );
    OTF2_GlobalDefReaderCallbacks_Delete(defCallbacks);

    var definitionsRead: c_uint64 = 0;
    OTF2_Reader_ReadAllGlobalDefinitions(reader, globalDefReader, c_ptrTo(definitionsRead));
    writeln("Global definitions read: ", definitionsRead);

    const defReadTime = timer.elapsed();
    writef("Time taken to read global definitions: %.2dr seconds\n", defReadTime);
    timer.clear();

    for loc in defCtx.locationIds {
      OTF2_Reader_SelectLocation(reader, loc);
    }

    const openedDefFiles = OTF2_Reader_OpenDefFiles(reader) == OTF2_SUCCESS;
    OTF2_Reader_OpenEvtFiles(reader);

    for loc in defCtx.locationIds {
      if openedDefFiles {
        var defReader = OTF2_Reader_GetDefReader(reader, loc);
        if defReader != nil {
          var defReads: c_uint64 = 0;
          OTF2_Reader_ReadAllLocalDefinitions(reader, defReader, c_ptrTo(defReads));
          OTF2_Reader_CloseDefReader(reader, defReader);
        }
      }

      var evtReader = OTF2_Reader_GetEvtReader(reader, loc);
    }

    const markTime = timer.elapsed();
    writeln("Time taken to read local definition files and mark all local event files for reading: ", markTime, " seconds");
    timer.clear();

    if openedDefFiles then OTF2_Reader_CloseDefFiles(reader);

    var evtCtx = new EvtCallbackContext(defCtx);
    var globalEvtReader = OTF2_Reader_GetGlobalEvtReader(reader);
    var evtCallbacks = OTF2_GlobalEvtReaderCallbacks_New();
    OTF2_GlobalEvtReaderCallbacks_SetEnterCallback(evtCallbacks, c_ptrTo(EnterStoreAndCount): c_fn_ptr);
    OTF2_GlobalEvtReaderCallbacks_SetLeaveCallback(evtCallbacks, c_ptrTo(LeaveStoreAndCount): c_fn_ptr);

    OTF2_Reader_RegisterGlobalEvtCallbacks(
      reader,
      globalEvtReader,
      evtCallbacks,
      c_ptrTo(evtCtx): c_ptr(void)
    );
    OTF2_GlobalEvtReaderCallbacks_Delete(evtCallbacks);

    var totalEventsRead: c_uint64 = 0;
    OTF2_Reader_ReadAllGlobalEvents(reader, globalEvtReader, c_ptrTo(totalEventsRead));

    const eventReadTime = timer.elapsed();
    writeln("Time taken to read events: ", eventReadTime, " seconds");
    timer.clear();

    OTF2_Reader_CloseGlobalEvtReader(reader, globalEvtReader);
    OTF2_Reader_CloseEvtFiles(reader);
    OTF2_Reader_Close(reader);

    const closeTime = timer.elapsed();
    timer.stop();
    writeln("Total time: ", openTime + defReadTime + markTime + eventReadTime + closeTime, " seconds");

    ref data = evtCtx.eventData;
    writeln("Event Summary:");
    writeln(" Total number of events: ", totalEventsRead);
    writeln(" Event types and their counts:");
    writeln("  Enter: ", data.enterCount, " events");
    writeln("  Leave: ", data.leaveCount, " events");
    PrintUniqueLocationAndRegionStats(defCtx, verbose);
  }
}
