// Copyright Hewlett Packard Enterprise Development LP.

module ReadEventsSerial {
  // Mason example: mason run --example ReadEventsSerial.chpl
  use FastOTF2;
  use Time;
  use List;

  // --- Definition context (mirrors parallel version) ---
  record DefCallbackContext {
    var locationIds: domain(OTF2_LocationRef);
    var locationTable: [locationIds] string;
    var regionIds: domain(OTF2_RegionRef);
    var regionTable: [regionIds] string;
    var stringIds: domain(OTF2_StringRef);
    var stringTable: [stringIds] string;
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
    ctx.locationTable[location] = locName;
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

  // --- Event data structures (aligned with parallel implementation) ---
  record EventInfo {
    var time: OTF2_TimeStamp;
    var locationName: string;
    var eventName: string;
    var regionName: string;
  }

  record AllEventsData {
    var enterCount: uint;
    var leaveCount: uint;
    var events: list(EventInfo); // serial: no need for parSafe
  }

  record EvtCallbackContext {
    var defContext: DefCallbackContext;
    var eventData: AllEventsData;
  }

  // --- Event callbacks (now operate on EvtCallbackContext) ---
  proc Enter_store_and_count(location: OTF2_LocationRef,
                            time: OTF2_TimeStamp,
                            userData: c_ptr(void),
                            attributes: c_ptr(OTF2_AttributeList),
                            region: OTF2_RegionRef): OTF2_CallbackCode {
    // Get pointers to the context and event data
    var ctxPtr = userData: c_ptr(EvtCallbackContext);
    if ctxPtr == nil then return OTF2_CALLBACK_ERROR;
    ref ctx = ctxPtr.deref();
    ref defCtx = ctx.defContext;
    ref evd = ctx.eventData;
    // Increment enter count
    evd.enterCount += 1;
    // Get location and region names
    const locname = if defCtx.locationIds.contains(location) then defCtx.locationTable[location] else "UnknownLocation";
    const regionname = if defCtx.regionIds.contains(region) then defCtx.regionTable[region] else "UnknownRegion";
    // Add event to all_event_data
    evd.events.pushBack(new EventInfo(time, locname, "Enter", regionname));
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
    const locname = if defCtx.locationIds.contains(location) then defCtx.locationTable[location] else "UnknownLocation";
    const regionname = if defCtx.regionIds.contains(region) then defCtx.regionTable[region] else "UnknownRegion";
    evd.events.pushBack(new EventInfo(time, locname, "Leave", regionname));
    return OTF2_CALLBACK_SUCCESS;
  }
  // Config constant for command-line argument
  // Usage: ./ReadEventsSerial --tracePath=/path/to/traces.otf2
  config const tracePath: string = "sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2";

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
    OTF2_GlobalDefReaderCallbacks_SetStringCallback(defCallbacks, c_ptrTo(GlobDefString_Register): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetLocationCallback(defCallbacks, c_ptrTo(GlobDefLocation_Register): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetRegionCallback(defCallbacks, c_ptrTo(GlobDefRegion_Register): c_fn_ptr);

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

    // Print the stats for unique locations
    printUniqueLocationAndRegionStats(defCtx, false);
  }


  proc printUniqueLocationAndRegionStats(defCtx: DefCallbackContext, verbose: bool) {
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

    // Print the stats for unique regions
    writeln("Total Unique Regions: ", defCtx.regionIds.size);
    if verbose {
      writeln("Unique Regions:");
      for regionId in defCtx.regionIds {
        writeln(defCtx.regionTable[regionId]);
      }
    }
  }
}
