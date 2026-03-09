// Copyright Hewlett Packard Enterprise Development LP.

module OTF2_Reader {
  use CTypes;
  use MoreCTypes;
  use OTF2_ErrorCodes;
  use OTF2_GeneralDefinitions;
  use OTF2_Callbacks;
  use OTF2_EvtReaderCallbacks_Mod;
  use OTF2_GlobalDefReaderCallbacks_Mod;
  use OTF2_GlobalEvtReaderCallbacks_Mod;

  require "otf2/OTF2_Reader.h";
  require "otf2/OTF2_GlobalDefReaderCallbacks.h";
  require "otf2/OTF2_GlobalEvtReaderCallbacks.h";


  extern record OTF2_Reader {
    // We don't need to specify the fields
  }


  extern proc OTF2_Reader_Open(anchorFilePath: c_ptrConst(c_char)): c_ptr(OTF2_Reader);

  extern proc OTF2_Reader_Close(reader: c_ptr(OTF2_Reader)): OTF2_ErrorCode;

  extern proc OTF2_Reader_SetSerialCollectiveCallbacks(reader: c_ptr(OTF2_Reader)): OTF2_ErrorCode;

  extern proc OTF2_Reader_GetNumberOfLocations(reader: c_ptr(OTF2_Reader), numberOfLocations: c_ptr(c_uint64)): OTF2_ErrorCode;

  extern proc OTF2_Reader_GetGlobalDefReader(reader: c_ptr(OTF2_Reader)): c_ptr(OTF2_GlobalDefReader);

  extern proc OTF2_Reader_RegisterGlobalDefCallbacks(
    reader: c_ptr(OTF2_Reader),
    defReader: c_ptr(OTF2_GlobalDefReader),
    callbacks: c_ptrConst(OTF2_GlobalDefReaderCallbacks),
    userData: c_ptr(void)
  ): OTF2_ErrorCode;

  // Reader-level collective and locking callbacks
  extern proc OTF2_Reader_SetCollectiveCallbacks(
    reader: c_ptr(OTF2_Reader),
    collectiveCallbacks: c_ptrConst(OTF2_CollectiveCallbacks),
    collectiveData: c_ptr(void),
    globalCommContext: c_ptr(OTF2_CollectiveContext),
    localCommContext: c_ptr(OTF2_CollectiveContext)
  ): OTF2_ErrorCode;

  extern proc OTF2_Reader_SetLockingCallbacks(
    reader: c_ptr(OTF2_Reader),
    lockingCallbacks: c_ptrConst(OTF2_LockingCallbacks),
    lockingData: c_ptr(void)
  ): OTF2_ErrorCode;

  // Global definitions reading
  extern proc OTF2_Reader_ReadGlobalDefinitions(reader: c_ptr(OTF2_Reader),
                                               globalDefReader: c_ptr(OTF2_GlobalDefReader),
                                               definitionsToRead: c_ptr(c_uint64),
                                               definitionsRead: c_ptr(c_uint64)): OTF2_ErrorCode;
  extern proc OTF2_Reader_ReadAllGlobalDefinitions(reader: c_ptr(OTF2_Reader),
                                                   defReader: c_ptr(OTF2_GlobalDefReader),
                                                   definitionsRead: c_ptr(c_uint64)): OTF2_ErrorCode;


  // Selection and per-location readers
  extern proc OTF2_Reader_SelectLocation(reader: c_ptr(OTF2_Reader), location: OTF2_LocationRef): OTF2_ErrorCode;
  extern proc OTF2_Reader_OpenDefFiles(reader: c_ptr(OTF2_Reader)): OTF2_ErrorCode;
  extern proc OTF2_Reader_GetDefReader(reader: c_ptr(OTF2_Reader), location: OTF2_LocationRef): c_ptr(OTF2_DefReader);
  extern proc OTF2_Reader_ReadLocalDefinitions(reader: c_ptr(OTF2_Reader),
                                               defReader: c_ptr(OTF2_DefReader),
                                               definitionsToRead: c_ptr(c_uint64),
                                               definitionsRead: c_ptr(c_uint64)): OTF2_ErrorCode;
  extern proc OTF2_Reader_ReadAllLocalDefinitions(reader: c_ptr(OTF2_Reader),
                                                  defReader: c_ptr(OTF2_DefReader),
                                                  definitionsRead: c_ptr(c_uint64)): OTF2_ErrorCode;
  extern proc OTF2_Reader_CloseDefReader(reader: c_ptr(OTF2_Reader), defReader: c_ptr(OTF2_DefReader)): OTF2_ErrorCode;
  extern proc OTF2_Reader_CloseDefFiles(reader: c_ptr(OTF2_Reader)): OTF2_ErrorCode;

  // Event readers
  extern proc OTF2_Reader_OpenEvtFiles(reader: c_ptr(OTF2_Reader)): OTF2_ErrorCode;
  extern proc OTF2_Reader_GetEvtReader(reader: c_ptr(OTF2_Reader), location: OTF2_LocationRef): c_ptr(OTF2_EvtReader);
  extern proc OTF2_Reader_RegisterEvtCallbacks(reader: c_ptr(OTF2_Reader),
                                               evtReader: c_ptr(OTF2_EvtReader),
                                               callbacks: c_ptrConst(OTF2_EvtReaderCallbacks),
                                               userData: c_ptr(void)): OTF2_ErrorCode;
  extern proc OTF2_Reader_GetGlobalEvtReader(reader: c_ptr(OTF2_Reader)): c_ptr(OTF2_GlobalEvtReader);
  extern proc OTF2_Reader_RegisterGlobalEvtCallbacks(reader: c_ptr(OTF2_Reader),
                                                     globalEvtReader: c_ptr(OTF2_GlobalEvtReader),
                                                     callbacks: c_ptrConst(OTF2_GlobalEvtReaderCallbacks),
                                                     userData: c_ptr(void)): OTF2_ErrorCode;


  extern proc OTF2_Reader_ReadLocalEvents(reader: c_ptr(OTF2_Reader),
                                           evtReader: c_ptr(OTF2_EvtReader),
                                           eventsToRead: c_ptr(c_uint64),
                                           eventsRead: c_ptr(c_uint64)): OTF2_ErrorCode;
  extern proc OTF2_Reader_ReadAllLocalEvents(reader: c_ptr(OTF2_Reader),
                                              evtReader: c_ptr(OTF2_EvtReader),
                                              eventsRead: c_ptr(c_uint64)): OTF2_ErrorCode;
  extern proc OTF2_Reader_ReadLocalEventsBackward(reader: c_ptr(OTF2_Reader),
                                                  evtReader: c_ptr(OTF2_EvtReader),
                                                  eventsToRead: c_ptr(c_uint64),
                                                  eventsRead: c_ptr(c_uint64)): OTF2_ErrorCode;

  extern proc OTF2_Reader_ReadAllGlobalEvents(reader: c_ptr(OTF2_Reader),
                                              globalEvtReader: c_ptr(OTF2_GlobalEvtReader),
                                              eventsRead: c_ptr(c_uint64)): OTF2_ErrorCode;

  extern proc OTF2_Reader_CloseEvtReader(reader: c_ptr(OTF2_Reader), evtReader: c_ptr(OTF2_EvtReader)): OTF2_ErrorCode;
  extern proc OTF2_Reader_CloseGlobalEvtReader(reader: c_ptr(OTF2_Reader), globalEvtReader: c_ptr(OTF2_GlobalEvtReader)): OTF2_ErrorCode;
  extern proc OTF2_Reader_CloseEvtFiles(reader: c_ptr(OTF2_Reader)): OTF2_ErrorCode;
}