// Copyright Hewlett Packard Enterprise Development LP.

module ReadEventsDistributed {
  // Mason example: mason run --example ReadEventsDistributed.chpl
  use FastOTF2;
  use Time;
  use List;
  use Sort;

  // Defs are read in serial, so only one instance of this needs to exist,
  // but copies will be made to make the tables available to each reader
  record DefCallbackContext {
    var locationIds: domain(OTF2_LocationRef);
    var locationTable: [locationIds] string;
    var regionIds: domain(OTF2_RegionRef);
    var regionTable: [regionIds] string;
    var stringIds: domain(OTF2_StringRef);
    var stringTable: [stringIds] string;
  }

  // --- Definition callback: register strings, locations and regions ---
  proc GlobDefString_Register(userData: c_ptr(void),
                               strRef: OTF2_StringRef,
                               strName: c_ptrConst(c_uchar)):
                               OTF2_CallbackCode {
    // Get the reference to the context record
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

  // --- Event data structures ---
  record EventInfo {
    var time: OTF2_TimeStamp;
    var locationName: string;
    var eventName: string;
    var regionName: string;
  }

  // Comparator for sorting EventInfo by timestamp
  operator <(a: EventInfo, b: EventInfo) {
    return a.time < b.time;
  }

  record AllEventsData {
    var enterCount: uint;
    var leaveCount: uint;
    var events: list(EventInfo);
  }

  // --- Context passed as userData ---
  // Each reader will have it's own instance of this record
  // we will have to merge the AllEventsData from all readers at the end
  record EvtCallbackContext {
    var defContext: DefCallbackContext;
    var eventData: AllEventsData;
  }

  // --- Event callbacks ---
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
    ref defContext = ctx.defContext;
    ref allEventsData = ctx.eventData;
    // Increment enter event count
    allEventsData.enterCount += 1;
    // Get location and region names
    const locname = if defContext.locationIds.contains(location) then defContext.locationTable[location] else "UnknownLocation";
    const regionname = if defContext.regionIds.contains(region) then defContext.regionTable[region] else "UnknownRegion";
    // Add event to allEventsData
    allEventsData.events.pushBack(new EventInfo(time, locname, "Enter", regionname));
    //writeln("Debug: Exiting Enter_store_and_count with enterCount=", allEventsData.enterCount);
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
    ref defContext = ctx.defContext;
    ref allEventsData = ctx.eventData;
    // Increment leave event count
    allEventsData.leaveCount += 1;
    // Get location and region names
    const locname = if defContext.locationIds.contains(location) then defContext.locationTable[location] else "UnknownLocation";
    const regionname = if defContext.regionIds.contains(region) then defContext.regionTable[region] else "UnknownRegion";
    // Add event to allEventsData
    allEventsData.events.pushBack(new EventInfo(time, locname, "Leave", regionname));
    //writeln("Debug: Exiting Leave_store_and_count with leaveCount=", allEventsData.leaveCount);
    return OTF2_CALLBACK_SUCCESS;
  }

  // Config constant for command-line argument
  // Usage: ./ReadEventsDistributed --tracePath=/path/to/traces.otf2
  config const tracePath: string = "sample-traces/frontier-hpl-run-using-2-ranks-with-craypm/traces.otf2";

  proc main() {
    //writeln("Debug: Starting main");
    var sw: stopwatch;

    sw.start();

    var initial_reader = OTF2_Reader_Open(tracePath.c_str());
    if initial_reader == nil {
      writeln("Failed to open trace file");
      return;
    }

    const openTime = sw.elapsed();
    writef("Time taken to open initial OTF2 archive: %.2dr seconds\n", openTime);

    OTF2_Reader_SetSerialCollectiveCallbacks(initial_reader);

    var numberOfLocations: c_uint64 = 0;
    OTF2_Reader_GetNumberOfLocations(initial_reader, c_ptrTo(numberOfLocations));
    writeln("Number of locations: ", numberOfLocations);

    // We create a single data context record for all readers
    // In order for this to work, the data structures within this record must be parSafe
    // I have set parSafe=true for the lists and domains.
    var defCtx = new DefCallbackContext();

    // Definition callbacks setup
    var globalDefReader : c_ptr(OTF2_GlobalDefReader) = OTF2_Reader_GetGlobalDefReader(initial_reader);
    var defCallbacks : c_ptr(OTF2_GlobalDefReaderCallbacks) = OTF2_GlobalDefReaderCallbacks_New();

    // Register string callbacks first since locations and regions depend on strings
    OTF2_GlobalDefReaderCallbacks_SetStringCallback(defCallbacks,
                                                    c_ptrTo(GlobDefString_Register): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetLocationCallback(defCallbacks,
                                                      c_ptrTo(GlobDefLocation_Register): c_fn_ptr);
    OTF2_GlobalDefReaderCallbacks_SetRegionCallback(defCallbacks,
                                                    c_ptrTo(GlobDefRegion_Register): c_fn_ptr);


    OTF2_Reader_RegisterGlobalDefCallbacks(initial_reader,
                                          globalDefReader,
                                          defCallbacks,
                                          c_ptrTo(defCtx): c_ptr(void));

    OTF2_GlobalDefReaderCallbacks_Delete(defCallbacks);

    var definitionsRead: c_uint64 = 0;
    OTF2_Reader_ReadAllGlobalDefinitions(initial_reader,
                                         globalDefReader,
                                         c_ptrTo(definitionsRead));
    writeln("Global definitions read: ", definitionsRead);

    const defReadTime = sw.elapsed();
    writef("Time taken to read global definitions: %.2dr seconds\n", defReadTime);
    sw.clear(); // Restart stopwatch for next timing

    // Convert associative domain to array for distribution
    // This can and should be optimized in some other way perhaps.
    const locationArray : [0..<numberOfLocations] uint = for l in defCtx.locationIds do l;
    const totalLocs = locationArray.size;
    writeln("Total locations: ", totalLocs);
    writeln("SANITY CHECK:", totalLocs == numberOfLocations);

    const locToArrayTime = sw.elapsed();
    writeln("Time taken to convert location IDs to array: ", locToArrayTime, " seconds");
    sw.clear();

    // Select locations to read definitions from, in this case, all
    for loc in locationArray {
      OTF2_Reader_SelectLocation(initial_reader, loc);
    }

    // Open files, read local defs per location
    const successfulOpenDefFiles =
                        OTF2_Reader_OpenDefFiles(initial_reader) == OTF2_SUCCESS;

    // Read all local definitions files
    for loc in locationArray {
      if successfulOpenDefFiles {
        var defReader = OTF2_Reader_GetDefReader(initial_reader, loc);
        if defReader != nil {
          var defReads: c_uint64 = 0;
          OTF2_Reader_ReadAllLocalDefinitions(initial_reader,
                                              defReader,
                                              c_ptrTo(defReads));

          OTF2_Reader_CloseDefReader(initial_reader, defReader);
        }
      }
      // No marking event files for reading as we're only doing def files for now
    }

    if successfulOpenDefFiles {
      OTF2_Reader_CloseDefFiles(initial_reader);
    }

    // Close the initial_reader now that we have the number of locations
    // and definitions
    OTF2_Reader_Close(initial_reader);

    // This is to use the most number of readers that makes sense
    // const numberOfReaders = 5;
    const numberOfReaders = numLocales;
    writeln("Number of readers: ", numberOfReaders);

    // Alternatively, we could also put this inside the coforall
    // and then each task would have its own context
    // And we can merge it back later
    var totalEventsReadAcrossReaders: c_uint64 = 0;

    // Allocate per-reader event contexts that we'll merge after parallel region
    var evtContexts: [0..<numberOfReaders] EvtCallbackContext;

    coforall i in 0..<numberOfReaders with (+ reduce totalEventsReadAcrossReaders, ref defCtx, ref evtContexts) do on Locales[i] {
      // Each task will have its own reader
      var reader = OTF2_Reader_Open(tracePath.c_str());

      if reader != nil {
        OTF2_Reader_SetSerialCollectiveCallbacks(reader);

        var sw_inner: stopwatch;
        sw_inner.start();

        var numLocationsToReadForThisTask = totalLocs / numberOfReaders;
        const low = i * numLocationsToReadForThisTask;
        const high = if i == numberOfReaders - 1 then totalLocs
                     else (i + 1) * numLocationsToReadForThisTask;

        // Select locations for this task
        for locIdx in low..<high {
          const loc = locationArray[locIdx];
          // writeln("Task ", i, " selecting location ", loc);
          OTF2_Reader_SelectLocation(reader, loc);
        }

        // Open files, read local defs per location
        // const successfulOpenDefFiles =
        //                     OTF2_Reader_OpenDefFiles(reader) == OTF2_SUCCESS;

        OTF2_Reader_OpenEvtFiles(reader);

        for locIdx in low..<high {
          const loc = locationArray[locIdx];
          // Mark file to be read by Global Reader later
          var _evtReader = OTF2_Reader_GetEvtReader(reader, loc);
        }

        const markTime = sw_inner.elapsed();
        writeln("Time taken to mark all local event files for reading: ", markTime, " seconds");
        sw_inner.clear();

        // if successfulOpenDefFiles {
        //   OTF2_Reader_CloseDefFiles(reader);
        // }

        var globalEvtReader = OTF2_Reader_GetGlobalEvtReader(reader);
        var evtCallbacks = OTF2_GlobalEvtReaderCallbacks_New();
        // Local context for this task; copied into shared array after reading events
        var localEvtCtx = new EvtCallbackContext(defCtx);
        ref evtCtx = localEvtCtx;

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
        totalEventsReadAcrossReaders += totalEventsRead;

        const evtReadTime = sw_inner.elapsed();
        writeln("Time taken to read events (task ", i, "): ", evtReadTime, " seconds");
        sw_inner.clear();
        OTF2_Reader_CloseGlobalEvtReader(reader, globalEvtReader);
        OTF2_Reader_CloseEvtFiles(reader);
        OTF2_Reader_Close(reader);
        const closeTime = sw_inner.elapsed();
        sw_inner.stop();
        sw_inner.clear();
        // Copy local context with accumulated events into global array slot
        evtContexts[i] = localEvtCtx;
      } else {
        writeln("Failed to open trace file");
      }
    }
    sw.stop();
    writeln("Total time: ", sw.elapsed(), " seconds");


    // --- Merge per-reader contexts into a single aggregated structure ---
    var aggEnterEvents : uint = 0;
    var aggLeaveEvents : uint = 0;
    var allEventDataList : list(EventInfo);
    for i in 0..<numberOfReaders {
      const ctx = evtContexts[i];
      aggEnterEvents += ctx.eventData.enterCount;
      aggLeaveEvents += ctx.eventData.leaveCount;
      allEventDataList.pushBack(ctx.eventData.events);
    }
    const totalMerged = allEventDataList.size;
    // TODO, write a comparator and sort the list

    // Report aggregated counts
    writeln("Event Summary:");
    writeln(" Total number of events: ", totalEventsReadAcrossReaders);
    writeln(" Event types and their counts:");
    writeln("  Aggregated Enter events: ", aggEnterEvents);
    writeln("  Aggregated Leave events: ", aggLeaveEvents);

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
