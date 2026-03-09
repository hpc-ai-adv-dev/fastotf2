// Copyright Hewlett Packard Enterprise Development LP.

module OTF2_Archive {
  use CTypes;
  use OTF2_ErrorCodes;
  use OTF2_GeneralDefinitions;
  use OTF2_Callbacks;
  require "otf2/OTF2_Archive.h";

  extern record OTF2_Archive { }

  extern proc OTF2_Archive_SetFlushCallbacks(
    archive: c_ptr(OTF2_Archive),
    flushCallbacks: c_ptrConst(OTF2_FlushCallbacks),
    flushData: c_ptr(void)
  ): OTF2_ErrorCode;

  extern proc OTF2_Archive_SetMemoryCallbacks(
    archive: c_ptr(OTF2_Archive),
    memoryCallbacks: c_ptrConst(OTF2_MemoryCallbacks),
    memoryData: c_ptr(void)
  ): OTF2_ErrorCode;

  extern proc OTF2_Archive_SetCollectiveCallbacks(
    archive: c_ptr(OTF2_Archive),
    collectiveCallbacks: c_ptrConst(OTF2_CollectiveCallbacks),
    collectiveData: c_ptr(void),
    globalCommContext: c_ptr(OTF2_CollectiveContext),
    localCommContext: c_ptr(OTF2_CollectiveContext)
  ): OTF2_ErrorCode;

  extern proc OTF2_Archive_SetSerialCollectiveCallbacks(
    archive: c_ptr(OTF2_Archive)
  ): OTF2_ErrorCode;

  extern proc OTF2_Archive_SetLockingCallbacks(
    archive: c_ptr(OTF2_Archive),
    lockingCallbacks: c_ptrConst(OTF2_LockingCallbacks),
    lockingData: c_ptr(void)
  ): OTF2_ErrorCode;
}
