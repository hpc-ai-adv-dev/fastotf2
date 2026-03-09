// Copyright Hewlett Packard Enterprise Development LP.

module OTF2_EvtReaderCallbacks_Mod {
  use CTypes;
  use OTF2_ErrorCodes;
  use OTF2_GeneralDefinitions;
  require "otf2/OTF2_EvtReaderCallbacks.h";

  extern record OTF2_EvtReaderCallbacks { }

  extern proc OTF2_EvtReaderCallbacks_New() : c_ptr(OTF2_EvtReaderCallbacks);
  extern proc OTF2_EvtReaderCallbacks_Delete(evtReaderCallbacks: c_ptr(OTF2_EvtReaderCallbacks)) : OTF2_ErrorCode;
  extern proc OTF2_EvtReaderCallbacks_Clear(evtReaderCallbacks: c_ptr(OTF2_EvtReaderCallbacks)) : OTF2_ErrorCode;

  extern proc OTF2_EvtReaderCallbacks_SetEnterCallback(
    callbacks: c_ptr(OTF2_EvtReaderCallbacks),
    enterCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_EvtReaderCallbacks_SetLeaveCallback(
    callbacks: c_ptr(OTF2_EvtReaderCallbacks),
    leaveCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_EvtReaderCallbacks_SetUnknownCallback(
    evtReaderCallbacks: c_ptr(OTF2_EvtReaderCallbacks),
    unknownCallback: c_fn_ptr
  ): OTF2_ErrorCode;


  extern proc OTF2_EvtReaderCallbacks_SetBufferFlushCallback(
    evtReaderCallbacks: c_ptr(OTF2_EvtReaderCallbacks),
    bufferFlushCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_EvtReaderCallbacks_SetMeasurementOnOffCallback(
    evtReaderCallbacks: c_ptr(OTF2_EvtReaderCallbacks),
    measurementOnOffCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_EvtReaderCallbacks_SetMpiSendCallback(
    evtReaderCallbacks: c_ptr(OTF2_EvtReaderCallbacks),
    mpiSendCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_EvtReaderCallbacks_SetMpiIsendCallback(
    evtReaderCallbacks: c_ptr(OTF2_EvtReaderCallbacks),
    mpiIsendCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_EvtReaderCallbacks_SetMpiIsendCompleteCallback(
    evtReaderCallbacks: c_ptr(OTF2_EvtReaderCallbacks),
    mpiIsendCompleteCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_EvtReaderCallbacks_SetMpiIrecvRequestCallback(
    evtReaderCallbacks: c_ptr(OTF2_EvtReaderCallbacks),
    mpiIrecvRequestCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_EvtReaderCallbacks_SetMpiRecvCallback(
    evtReaderCallbacks: c_ptr(OTF2_EvtReaderCallbacks),
    mpiRecvCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_EvtReaderCallbacks_SetMpiIrecvCallback(
    evtReaderCallbacks: c_ptr(OTF2_EvtReaderCallbacks),
    mpiIrecvCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_EvtReaderCallbacks_SetMpiRequestTestCallback(
    evtReaderCallbacks: c_ptr(OTF2_EvtReaderCallbacks),
    mpiRequestTestCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_EvtReaderCallbacks_SetMpiRequestCancelledCallback(
    evtReaderCallbacks: c_ptr(OTF2_EvtReaderCallbacks),
    mpiRequestCancelledCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_EvtReaderCallbacks_SetMpiCollectiveBeginCallback(
    evtReaderCallbacks: c_ptr(OTF2_EvtReaderCallbacks),
    mpiCollectiveBeginCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_EvtReaderCallbacks_SetMpiCollectiveEndCallback(
    evtReaderCallbacks: c_ptr(OTF2_EvtReaderCallbacks),
    mpiCollectiveEndCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  /// There's like 200 more TODO callbacks to add
}