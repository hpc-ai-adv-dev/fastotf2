// Copyright Hewlett Packard Enterprise Development LP.

module SimpleReadParallelLocalEvents {
  // Mason example: mason run --example SimpleReadParallelLocalEvents.chpl
  use OTF2;

  // Callback: print on enter
  proc EnterPrint(location: OTF2_LocationRef,
                  time: OTF2_TimeStamp,
                  userData: c_ptr(void),
                  attributes: c_ptr(OTF2_AttributeList),
                  region: OTF2_RegionRef): OTF2_CallbackCode {
    writeln("Entering region ", region, " at location ", location, " at time ", time, ".");
    return OTF2_CALLBACK_SUCCESS;
  }

  // Callback: print on leave
  proc LeavePrint(location: OTF2_LocationRef,
                  time: OTF2_TimeStamp,
                  userData: c_ptr(void),
                  attributes: c_ptr(OTF2_AttributeList),
                  region: OTF2_RegionRef): OTF2_CallbackCode {
    writeln("Leaving region ", region, " at location ", location, " at time ", time, ".");
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
  // Usage: ./SimpleReadParallelLocalEvents --tracePath=/path/to/traces.otf2
  config const tracePath: string = "sample-traces/simple-mi300-example-run/traces.otf2";

  proc main() {

    var initial_reader = OTF2_Reader_Open(tracePath.c_str());
    if initial_reader == nil {
      writeln("Failed to open trace file");
      return;
    }

    var number_of_locations: c_uint64 = 0;
    OTF2_Reader_GetNumberOfLocations(initial_reader, c_ptrTo(number_of_locations));
    writeln("Number of locations: ", number_of_locations);

    // const numberOfReaders = number_of_locations / here.maxTaskPar; // This is to use the most number of readers that makes sense
    const numberOfReaders = 2; // Force two readers for now


    coforall i in 0..numberOfReaders {
      // Each task will have its own reader
      var reader = OTF2_Reader_Open(tracePath.c_str());
      if reader != nil {
        // Perform reading operations with reader
        var locations = new LocationVector(capacity=number_of_locations);
        var locations_ptr = c_ptrTo(locations);

        var global_def_reader = OTF2_Reader_GetGlobalDefReader(reader);

        var global_def_callbacks = OTF2_GlobalDefReaderCallbacks_New();
        var loc_cb_ptr: c_fn_ptr = c_ptrTo(GlobDefLocationRegister): c_fn_ptr;

        OTF2_GlobalDefReaderCallbacks_SetLocationCallback(global_def_callbacks,
                                                          loc_cb_ptr);

        OTF2_Reader_RegisterGlobalDefCallbacks(reader,
                                              global_def_reader,
                                              global_def_callbacks,
                                              locations_ptr: c_ptr(void));

        OTF2_GlobalDefReaderCallbacks_Delete(global_def_callbacks);

        var definitions_read: c_uint64 = 0;
        OTF2_Reader_ReadAllGlobalDefinitions(reader, global_def_reader, c_ptrTo(definitions_read));
        writeln("Number of definitions read: ", definitions_read);


        var numLocsToReadForThisTask = number_of_locations / numberOfReaders;
        const low = i * numLocsToReadForThisTask;
        const high = min((i + 1) * numLocsToReadForThisTask, number_of_locations);

        for member in locations.members[low..<high] {
          OTF2_Reader_SelectLocation(reader, member);
        }

        var successful_open_def_files = OTF2_Reader_OpenDefFiles(reader) == OTF2_SUCCESS;
        OTF2_Reader_OpenEvtFiles(reader);

        for j in low..<high {
          if successful_open_def_files {
            var def_reader = OTF2_Reader_GetDefReader(reader,
                                                      locations.members[j]);
            if def_reader != nil {
              var def_reads: c_uint64 = 0;
              OTF2_Reader_ReadAllLocalDefinitions(reader,
                                                  def_reader,
                                                  c_ptrTo(def_reads));

              OTF2_Reader_CloseDefReader(reader, def_reader);
            }
          }
          // We don't open the reader here in this version
        }
        if successful_open_def_files {
          OTF2_Reader_CloseDefFiles(reader);
        }

        var event_callbacks: c_ptr(OTF2_EvtReaderCallbacks) =
                                      OTF2_EvtReaderCallbacks_New();

        var enter_cb_ptr: c_fn_ptr = c_ptrTo(EnterPrint): c_fn_ptr;
        OTF2_EvtReaderCallbacks_SetEnterCallback(event_callbacks,
                                                 enter_cb_ptr);

        var leave_cb_ptr: c_fn_ptr = c_ptrTo(LeavePrint): c_fn_ptr;
        OTF2_EvtReaderCallbacks_SetLeaveCallback(event_callbacks,
                                                 leave_cb_ptr);


        // Making this parallel is also a possibility, but we need the locking mechanisms for that
        for member in locations.members[low..<high] {
          var evt_reader = OTF2_Reader_GetEvtReader(reader, member);
          if evt_reader != nil {
            OTF2_Reader_RegisterEvtCallbacks(reader,
                                             evt_reader,
                                             event_callbacks,
                                             nil);

            // Read all local events
            var events_read : c_uint64 = 0;
            OTF2_Reader_ReadAllLocalEvents(reader,
                                           evt_reader,
                                           c_ptrTo(events_read));

            OTF2_Reader_CloseEvtReader(reader, evt_reader);
          }
        }

        OTF2_Reader_CloseEvtFiles(reader);
        // Close the reader
        OTF2_Reader_Close(reader);
      } else {
        writeln("Failed to open trace file");
      }

    }




    // No need to free locations, Chapel handles memory
  }
}
