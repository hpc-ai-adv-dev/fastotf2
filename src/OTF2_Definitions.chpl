// Copyright Hewlett Packard Enterprise Development LP.

module OTF2_Definitions {
  use CTypes;
  use MoreCTypes;
  require "otf2/OTF2_Definitions.h";

  // Location group types (is a C enum )
  extern type OTF2_LocationGroupType = c_uint8;
  extern const OTF2_LOCATION_GROUP_TYPE_UNKNOWN: OTF2_LocationGroupType;
  extern const OTF2_LOCATION_GROUP_TYPE_PROCESS: OTF2_LocationGroupType;
  extern const OTF2_LOCATION_GROUP_TYPE_ACCELERATOR: OTF2_LocationGroupType;

  // Location types (is a C enum )
  extern type OTF2_LocationType = c_uint8;
  extern const OTF2_LOCATION_TYPE_UNKNOWN: OTF2_LocationType;
  extern const OTF2_LOCATION_TYPE_CPU_THREAD: OTF2_LocationType;
  extern const OTF2_LOCATION_TYPE_ACCELERATOR_STREAM: OTF2_LocationType;
  extern const OTF2_LOCATION_TYPE_METRIC: OTF2_LocationType;

  // Region roles (is a C enum )
  extern type OTF2_RegionRole = c_uint8;
  // Todo, define enum values

  // Region flags (is a C enum )
  extern type OTF2_RegionFlag = c_uint32; // flags bitset
  // Todo, define enum values

  // Metric types (is a C enum )
  extern type OTF2_MetricType = c_uint8;
  extern const OTF2_METRIC_TYPE_OTHER: OTF2_MetricType;
  extern const OTF2_METRIC_TYPE_PAPI: OTF2_MetricType;
  extern const OTF2_METRIC_TYPE_RUSAGE: OTF2_MetricType;
  extern const OTF2_METRIC_TYPE_USER: OTF2_MetricType;

  // Metric value base (is a C enum )
  extern type OTF2_Base = c_uint8;
  extern const OTF2_BASE_BINARY: OTF2_Base;
  extern const OTF2_BASE_DECIMAL: OTF2_Base;

  // Metric occurrence (is a C enum )
  extern type OTF2_MetricOccurrence = c_uint8;
  extern const OTF2_METRIC_SYNCHRONOUS_STRICT: OTF2_MetricOccurrence;
  extern const OTF2_METRIC_SYNCHRONOUS: OTF2_MetricOccurrence;
  extern const OTF2_METRIC_ASYNCHRONOUS: OTF2_MetricOccurrence;

  // Metric modes (is a C enum )
  extern type OTF2_MetricMode = c_uint8;
  extern const OTF2_METRIC_ACCUMULATED_START: OTF2_MetricMode;
  extern const OTF2_METRIC_ACCUMULATED_POINT: OTF2_MetricMode;
  extern const OTF2_METRIC_ACCUMULATED_LAST: OTF2_MetricMode;
  extern const OTF2_METRIC_ACCUMULATED_NEXT: OTF2_MetricMode;
  extern const OTF2_METRIC_ABSOLUTE_POINT: OTF2_MetricMode;
  extern const OTF2_METRIC_ABSOLUTE_LAST: OTF2_MetricMode;
  extern const OTF2_METRIC_ABSOLUTE_NEXT: OTF2_MetricMode;
  extern const OTF2_METRIC_RELATIVE_POINT: OTF2_MetricMode;
  extern const OTF2_METRIC_RELATIVE_LAST: OTF2_MetricMode;
  extern const OTF2_METRIC_RELATIVE_NEXT: OTF2_MetricMode;

  // Metric scope (is a C enum )
  extern type OTF2_MetricScope = c_uint8;
  extern const OTF2_SCOPE_LOCATION: OTF2_MetricScope;
  extern const OTF2_SCOPE_LOCATION_GROUP: OTF2_MetricScope;
  extern const OTF2_SCOPE_SYSTEM_TREE_NODE: OTF2_MetricScope;
  extern const OTF2_SCOPE_GROUP: OTF2_MetricScope;


  // Metric Recorder Kind (is a C enum )
  extern type OTF2_RecorderKind = c_uint8;
  extern const OTF2_RECORDER_KIND_UNKNOWN: OTF2_RecorderKind;
  extern const OTF2_RECORDER_KIND_ABSTRACT: OTF2_RecorderKind;
  extern const OTF2_RECORDER_KIND_CPU: OTF2_RecorderKind;
  extern const OTF2_RECORDER_KIND_GPU: OTF2_RecorderKind;
}