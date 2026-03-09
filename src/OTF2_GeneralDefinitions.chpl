// Copyright Hewlett Packard Enterprise Development LP.

module OTF2_GeneralDefinitions {
  use CTypes;
  use MoreCTypes;
  require "otf2/OTF2_GeneralDefinitions.h";

  // --- Opaque/handle types used across OTF2 ---
  extern record OTF2_GlobalDefReader { }

  // Time stamp and common refs
  extern type OTF2_TimeStamp = c_uint64;
  extern type OTF2_LocationRef = c_uint64;
  extern type OTF2_StringRef = c_uint32;
  extern type OTF2_RegionRef = c_uint32;
  extern type OTF2_LocationGroupRef = c_uint32;
  extern type OTF2_SystemTreeNodeRef = c_uint32;
  extern type OTF2_MetricMemberRef = c_uint32;
  extern type OTF2_MetricRef = c_uint32;

  // Callback result code
  extern type OTF2_CallbackCode = c_int;
  extern const OTF2_CALLBACK_SUCCESS: OTF2_CallbackCode;
  extern const OTF2_CALLBACK_INTERRUPT: OTF2_CallbackCode;
  extern const OTF2_CALLBACK_ERROR: OTF2_CallbackCode;

  // Flush type
  extern type OTF2_FlushType = c_uint8;
  extern const OTF2_NO_FLUSH: OTF2_FlushType;
  extern const OTF2_FLUSH: OTF2_FlushType;

  // File types
  extern type OTF2_FileType = c_uint8;
  extern const OTF2_FILETYPE_ANCHOR: OTF2_FileType;
  extern const OTF2_FILETYPE_GLOBAL_DEFS: OTF2_FileType;
  extern const OTF2_FILETYPE_LOCAL_DEFS: OTF2_FileType;
  extern const OTF2_FILETYPE_EVENTS: OTF2_FileType;
  extern const OTF2_FILETYPE_SNAPSHOTS: OTF2_FileType;
  extern const OTF2_FILETYPE_THUMBNAIL: OTF2_FileType;
  extern const OTF2_FILETYPE_MARKER: OTF2_FileType;
  extern const OTF2_FILETYPE_SIONRANKMAP: OTF2_FileType;

  // OTF2 Data types
  extern type OTF2_Type = c_uint8;
  extern const OTF2_TYPE_NONE: OTF2_Type;
  extern const OTF2_TYPE_UINT8: OTF2_Type;
  extern const OTF2_TYPE_UINT16: OTF2_Type;
  extern const OTF2_TYPE_UINT32: OTF2_Type;
  extern const OTF2_TYPE_UINT64: OTF2_Type;
  extern const OTF2_TYPE_INT8: OTF2_Type;
  extern const OTF2_TYPE_INT16: OTF2_Type;
  extern const OTF2_TYPE_INT32: OTF2_Type;
  extern const OTF2_TYPE_INT64: OTF2_Type;
  extern const OTF2_TYPE_FLOAT: OTF2_Type;
  extern const OTF2_TYPE_DOUBLE: OTF2_Type;
  extern const OTF2_TYPE_STRING: OTF2_Type;
  extern const OTF2_TYPE_ATTRIBUTE: OTF2_Type;
  extern const OTF2_TYPE_LOCATION: OTF2_Type;
  extern const OTF2_TYPE_REGION: OTF2_Type;
  extern const OTF2_TYPE_GROUP: OTF2_Type;
  extern const OTF2_TYPE_METRIC: OTF2_Type;
  extern const OTF2_TYPE_COMM: OTF2_Type;
  extern const OTF2_TYPE_PARAMETER: OTF2_Type;
  extern const OTF2_TYPE_RMA_WIN: OTF2_Type;
  extern const OTF2_TYPE_SOURCE_CODE_LOCATION: OTF2_Type;
  extern const OTF2_TYPE_CALLING_CONTEXT: OTF2_Type;
  extern const OTF2_TYPE_INTERRUPT_GENERATOR: OTF2_Type;
  extern const OTF2_TYPE_IO_FILE: OTF2_Type;
  extern const OTF2_TYPE_IO_HANDLE: OTF2_Type;
  extern const OTF2_TYPE_LOCATION_GROUP: OTF2_Type;

  // Paradigms
  extern type OTF2_Paradigm = c_uint8;

  // Comm refs
  extern type OTF2_CommRef = c_uint32;

  extern record OTF2_DefReader { }
  extern record OTF2_EvtReader { }
  extern record OTF2_GlobalEvtReader { }

}