module FastOtf2ReadArchive {
  use FastOTF2;

  var enterCount: atomic int;
  var leaveCount: atomic int;

  proc EnterPrint(location: OTF2_LocationRef,
                  time: OTF2_TimeStamp,
                  userData: c_ptr(void),
                  attributes: c_ptr(OTF2_AttributeList),
                  region: OTF2_RegionRef): OTF2_CallbackCode {
    enterCount.add(1);
    return OTF2_CALLBACK_SUCCESS;
  }

  proc LeavePrint(location: OTF2_LocationRef,
                  time: OTF2_TimeStamp,
                  userData: c_ptr(void),
                  attributes: c_ptr(OTF2_AttributeList),
                  region: OTF2_RegionRef): OTF2_CallbackCode {
    leaveCount.add(1);
    return OTF2_CALLBACK_SUCCESS;
  }

  record LocationVector {
    var capacity: uint;
    var size: uint;
    var members: [0..<capacity] OTF2_LocationRef;
  }

  proc GlobDefLocationRegister(userData: c_ptr(void),
                               location: OTF2_LocationRef,
                               name: OTF2_StringRef,
                               locationType: OTF2_LocationType,
                               numberOfEvents: c_uint64,
                               locationGroup: OTF2_LocationGroupRef): OTF2_CallbackCode {
    var locationsPtr = userData: c_ptr(LocationVector);
    if locationsPtr == nil {
      return OTF2_CALLBACK_ERROR;
    }

    ref locations = locationsPtr.deref();
    if locations.size == locations.capacity {
      return OTF2_CALLBACK_INTERRUPT;
    }

    locations.members[locations.size] = location;
    locations.size += 1;
    return OTF2_CALLBACK_SUCCESS;
  }

  config const tracePath = "sample-traces/simple-mi300-example-run/traces.otf2";

  proc main() {
    var reader = OTF2_Reader_Open(tracePath.c_str());
    if reader == nil {
      writeln("Failed to open trace file: ", tracePath);
      return;
    }

    OTF2_Reader_SetSerialCollectiveCallbacks(reader);

    var numberOfLocations: c_uint64 = 0;
    OTF2_Reader_GetNumberOfLocations(reader, c_ptrTo(numberOfLocations));
    writeln("Number of locations: ", numberOfLocations);

    var locations = new LocationVector(capacity=numberOfLocations);
    var globalDefReader = OTF2_Reader_GetGlobalDefReader(reader);
    var globalDefCallbacks = OTF2_GlobalDefReaderCallbacks_New();
    OTF2_GlobalDefReaderCallbacks_SetLocationCallback(
      globalDefCallbacks,
      c_ptrTo(GlobDefLocationRegister): c_fn_ptr
    );

    OTF2_Reader_RegisterGlobalDefCallbacks(
      reader,
      globalDefReader,
      globalDefCallbacks,
      c_ptrTo(locations): c_ptr(void)
    );
    OTF2_GlobalDefReaderCallbacks_Delete(globalDefCallbacks);

    var definitionsRead: c_uint64 = 0;
    OTF2_Reader_ReadAllGlobalDefinitions(
      reader,
      globalDefReader,
      c_ptrTo(definitionsRead)
    );
    writeln("Number of definitions read: ", definitionsRead);

    for member in locations.members {
      OTF2_Reader_SelectLocation(reader, member);
    }

    const openedDefFiles = OTF2_Reader_OpenDefFiles(reader) == OTF2_SUCCESS;
    OTF2_Reader_OpenEvtFiles(reader);

    for i in 0..#locations.size {
      if openedDefFiles {
        var defReader = OTF2_Reader_GetDefReader(reader, locations.members[i]);
        if defReader != nil {
          var defReads: c_uint64 = 0;
          OTF2_Reader_ReadAllLocalDefinitions(reader, defReader, c_ptrTo(defReads));
          OTF2_Reader_CloseDefReader(reader, defReader);
        }
      }

      var evtReader = OTF2_Reader_GetEvtReader(reader, locations.members[i]);
    }

    if openedDefFiles {
      OTF2_Reader_CloseDefFiles(reader);
    }

    var globalEvtReader = OTF2_Reader_GetGlobalEvtReader(reader);
    var eventCallbacks = OTF2_GlobalEvtReaderCallbacks_New();
    OTF2_GlobalEvtReaderCallbacks_SetEnterCallback(
      eventCallbacks,
      c_ptrTo(EnterPrint): c_fn_ptr
    );
    OTF2_GlobalEvtReaderCallbacks_SetLeaveCallback(
      eventCallbacks,
      c_ptrTo(LeavePrint): c_fn_ptr
    );

    OTF2_Reader_RegisterGlobalEvtCallbacks(
      reader,
      globalEvtReader,
      eventCallbacks,
      nil
    );
    OTF2_GlobalEvtReaderCallbacks_Delete(eventCallbacks);

    var eventsRead: c_uint64 = 0;
    OTF2_Reader_ReadAllGlobalEvents(reader, globalEvtReader, c_ptrTo(eventsRead));
    OTF2_Reader_CloseGlobalEvtReader(reader, globalEvtReader);
    OTF2_Reader_CloseEvtFiles(reader);
    OTF2_Reader_Close(reader);

    writeln("Events read: ", eventsRead);
    writeln("Enter callbacks: ", enterCount.read());
    writeln("Leave callbacks: ", leaveCount.read());
  }
}
