// Copyright Hewlett Packard Enterprise Development LP.

module OTF2_GlobalEvtReaderCallbacks_Mod {
  use CTypes;
  use OTF2_ErrorCodes;
  use OTF2_GeneralDefinitions;
  require "otf2/OTF2_GlobalEvtReaderCallbacks.h";

  extern record OTF2_GlobalEvtReaderCallbacks { }

  extern proc OTF2_GlobalEvtReaderCallbacks_New() : c_ptr(OTF2_GlobalEvtReaderCallbacks);

  extern proc OTF2_GlobalEvtReaderCallbacks_Delete(
    globalEvtReaderCallbacks: c_ptr(OTF2_GlobalEvtReaderCallbacks)
  );

  extern proc OTF2_GlobalEvtReaderCallbacks_SetEnterCallback(
    globalEvtReaderCallbacks: c_ptr(OTF2_GlobalEvtReaderCallbacks),
    enterCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_GlobalEvtReaderCallbacks_SetLeaveCallback(
    globalEvtReaderCallbacks: c_ptr(OTF2_GlobalEvtReaderCallbacks),
    leaveCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_GlobalEvtReaderCallbacks_SetUnknownCallback(
    globalEvtReaderCallbacks: c_ptr(OTF2_GlobalEvtReaderCallbacks),
    unknownCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_GlobalEvtReaderCallbacks_SetMpiSendCallback(
    globalEvtReaderCallbacks: c_ptr(OTF2_GlobalEvtReaderCallbacks),
    mpiSendCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_GlobalEvtReaderCallbacks_SetMpiRecvCallback(
    globalEvtReaderCallbacks: c_ptr(OTF2_GlobalEvtReaderCallbacks),
    mpiRecvCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_GlobalEvtReaderCallbacks_SetMpiCollectiveEndCallback(
    globalEvtReaderCallbacks: c_ptr(OTF2_GlobalEvtReaderCallbacks),
    mpiCollectiveEndCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_GlobalEvtReaderCallbacks_SetBufferFlushCallback(
    globalEvtReaderCallbacks: c_ptr(OTF2_GlobalEvtReaderCallbacks),
    bufferFlushCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_GlobalEvtReaderCallbacks_SetMeasurementOnOffCallback(
    globalEvtReaderCallbacks: c_ptr(OTF2_GlobalEvtReaderCallbacks),
    measurementOnOffCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_GlobalEvtReaderCallbacks_SetMetricCallback(
    globalEvtReaderCallbacks: c_ptr(OTF2_GlobalEvtReaderCallbacks),
    metricCallback: c_fn_ptr
  ): OTF2_ErrorCode;
}