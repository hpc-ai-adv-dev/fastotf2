// Copyright Hewlett Packard Enterprise Development LP.

module SimpleReadParallel {
  // Mason example: mason run --example SimpleReadParallel.chpl
  use FastOTF2;

  // Callback: print on enter
  proc EnterPrint(location: OTF2_LocationRef,
                  time: OTF2_TimeStamp,
                  userData: c_ptr(void),
                  attributes: c_ptr(OTF2_AttributeList),
                  region: OTF2_RegionRef): OTF2_CallbackCode {
    //writeln("Entering region ", region, " at location ", location, " at time ", time, ".");
    return OTF2_CALLBACK_SUCCESS;
  }

  // Callback: print on leave
  proc LeavePrint(location: OTF2_LocationRef,
                  time: OTF2_TimeStamp,
                  userData: c_ptr(void),
                  attributes: c_ptr(OTF2_AttributeList),
                  region: OTF2_RegionRef): OTF2_CallbackCode {
    //writeln("Leaving region ", region, " at location ", location, " at time ", time, ".");
    return OTF2_CALLBACK_SUCCESS;
  }

  // Chapel version of the C struct vector
  record LocationVector {
    var capacity: uint;
    var size: uint;
    var members: [0..<capacity] OTF2_LocationRef;
  }

  // Callback: register location
  proc GlobDefLocationRegister(userData: c_ptr(void),
                               location: OTF2_LocationRef,
                               name: OTF2_StringRef,
                               locationType: OTF2_LocationType,
                               numberOfEvents: c_uint64,
                               locationGroup: OTF2_LocationGroupRef): OTF2_CallbackCode {
    //writeln("Inside GlobDefLocationRegister Callback");
    var locationsPtr = userData: c_ptr(LocationVector);
    if locationsPtr == nil {
      return OTF2_CALLBACK_ERROR;
    }
    ref loc = locationsPtr.deref();
    if loc.size == loc.capacity {
      return OTF2_CALLBACK_INTERRUPT;
    }
    loc.members[loc.size] = location;
    loc.size += 1;
    //writeln("Registered location ", location, " with name ", name, " and type ", locationType, ".");
    //writeln(loc);
    return OTF2_CALLBACK_SUCCESS;
  }

  // Config constant for command-line argument
  // Usage: ./SimpleReadParallel --tracePath=/path/to/traces.otf2
  config const tracePath: string = "sample-traces/simple-mi300-example-run/traces.otf2";

  proc main() {

    //writeln("Calling OTF2_Reader_Open");
    var reader = OTF2_Reader_Open(tracePath.c_str());
    if reader == nil {
      //writeln("Failed to open trace file");
      return;
    }

    //writeln("Calling OTF2_Reader_SetSerialCollectiveCallbacks");
    OTF2_Reader_SetSerialCollectiveCallbacks(reader);

    otf2ChplSyncReaderSetLockingCallbacks(reader);

    var number_of_locations: c_uint64 = 0;
    //writeln("Calling OTF2_Reader_GetNumberOfLocations");
    OTF2_Reader_GetNumberOfLocations(reader, c_ptrTo(number_of_locations));
    //writeln("Number of locations: ", number_of_locations);

    var locations = new LocationVector(capacity=number_of_locations);
    //writeln(locations);
    var locations_ptr = c_ptrTo(locations);

    //writeln("Calling OTF2_Reader_GetGlobalDefReader");
    var global_def_reader = OTF2_Reader_GetGlobalDefReader(reader);
    //writeln("Calling OTF2_GlobalDefReaderCallbacks_New");
    var global_def_callbacks = OTF2_GlobalDefReaderCallbacks_New();
    var loc_cb_ptr: c_fn_ptr = c_ptrTo(GlobDefLocationRegister): c_fn_ptr;
    //writeln("Calling OTF2_GlobalDefReaderCallbacks_SetLocationCallback");
    OTF2_GlobalDefReaderCallbacks_SetLocationCallback(global_def_callbacks, loc_cb_ptr);

    //writeln("Calling OTF2_Reader_RegisterGlobalDefCallbacks");
    OTF2_Reader_RegisterGlobalDefCallbacks(reader,
                                           global_def_reader,
                                           global_def_callbacks,
                                           locations_ptr: c_ptr(void));
    //writeln("Calling OTF2_GlobalDefReaderCallbacks_Delete");
    OTF2_GlobalDefReaderCallbacks_Delete(global_def_callbacks);
    var definitions_read: c_uint64 = 0;
    //writeln("Calling OTF2_Reader_ReadAllGlobalDefinitions");
    OTF2_Reader_ReadAllGlobalDefinitions(reader, global_def_reader, c_ptrTo(definitions_read));
    //writeln("Number of definitions read: ", definitions_read);
    //writeln(locations);
    for member in locations.members {
      //writeln("Calling OTF2_Reader_SelectLocation for location ", member);
      OTF2_Reader_SelectLocation(reader, member);
    }
    //writeln("Calling OTF2_Reader_OpenDefFiles");
    var successful_open_def_files = OTF2_Reader_OpenDefFiles(reader) == OTF2_SUCCESS;
    //writeln("Calling OTF2_Reader_OpenEvtFiles");
    OTF2_Reader_OpenEvtFiles(reader);
    for i in 0..#locations.size {
      if successful_open_def_files {
        //writeln("Calling OTF2_Reader_GetDefReader for location ", locations.members[i]);
        var def_reader = OTF2_Reader_GetDefReader(reader, locations.members[i]);
        if def_reader != nil {
          //writeln("Calling OTF2_Reader_ReadAllLocalDefinitions for location ", locations.members[i]);
          var def_reads: c_uint64 = 0;
          OTF2_Reader_ReadAllLocalDefinitions(reader, def_reader, c_ptrTo(def_reads));
          //writeln("Calling OTF2_Reader_CloseDefReader for location ", locations.members[i]);
          OTF2_Reader_CloseDefReader(reader, def_reader);
        }
      }
      // We don't open the reading in this version
    }
    if successful_open_def_files {
      //writeln("Calling OTF2_Reader_CloseDefFiles");
      OTF2_Reader_CloseDefFiles(reader);
    }

    //writeln("Calling OTF2_GlobalEvtReaderCallbacks_New");
    var event_callbacks: c_ptr(OTF2_EvtReaderCallbacks) = OTF2_EvtReaderCallbacks_New();
    var enter_cb_ptr: c_fn_ptr = c_ptrTo(EnterPrint): c_fn_ptr;
    var leave_cb_ptr: c_fn_ptr = c_ptrTo(LeavePrint): c_fn_ptr;
    //writeln("Calling OTF2_EvtReaderCallbacks_SetEnterCallback");
    OTF2_EvtReaderCallbacks_SetEnterCallback(event_callbacks, enter_cb_ptr);
    //writeln("Calling OTF2_EvtReaderCallbacks_SetLeaveCallback");
    OTF2_EvtReaderCallbacks_SetLeaveCallback(event_callbacks, leave_cb_ptr);

    for member in locations.members {
      //writeln("Calling OTF2_Reader_GetEvtReader for location ", member);
      var evt_reader = OTF2_Reader_GetEvtReader(reader, member);
      if evt_reader != nil {
        //writeln("Calling OTF2_Reader_RegisterEvtCallbacks");
        OTF2_Reader_RegisterEvtCallbacks(reader, evt_reader, event_callbacks, nil);

        // Read all local events
        var events_read : c_uint64 = 0;
        //writeln("Calling OTF2_Reader_ReadAllLocalEvents for location ", member);
        OTF2_Reader_ReadAllLocalEvents(reader, evt_reader, c_ptrTo(events_read));

        //writeln("Calling OTF2_Reader_CloseEvtReader");
        OTF2_Reader_CloseEvtReader(reader, evt_reader);
      }
    }

    //writeln("Calling OTF2_Reader_CloseEvtFiles");
    OTF2_Reader_CloseEvtFiles(reader);
    //writeln("Calling OTF2_Reader_Close");
    OTF2_Reader_Close(reader);
    // No need to free locations, Chapel handles memory
  }
}
