// Copyright Hewlett Packard Enterprise Development LP.

module OTF2_Events {
  use CTypes;
  use MoreCTypes;
  require "otf2/OTF2_Events.h";

  extern type OTF2_MeasurementMode = c_uint8;
  extern const OTF2_MEASUREMENT_ON: OTF2_MeasurementMode;
  extern const OTF2_MEASUREMENT_OFF: OTF2_MeasurementMode;

  extern type OTF2_CollectiveOp = c_uint8;
  // Define collective operations
  // Todo

  extern union OTF2_MetricValue {
    var signed_int: c_int64;
    var unsigned_int: c_uint64;
    var floating_point: c_double;
  }

  operator !=(a: OTF2_MetricValue, b: OTF2_MetricValue): bool {
    // Compare based on the type of value
    return a.signed_int != b.signed_int;
  }
}