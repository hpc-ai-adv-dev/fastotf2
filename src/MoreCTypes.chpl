// Copyright Hewlett Packard Enterprise Development LP.

module MoreCTypes {
  use CTypes;

  type c_uint8 = c_uchar;
  type c_uint16 = c_ushort;
  type c_uint32 = c_uint;
  type c_uint64 = c_ulonglong;

  type c_int8 = c_schar;
  type c_int16 = c_short;
  type c_int32 = c_int;
  type c_int64 = c_longlong;
}