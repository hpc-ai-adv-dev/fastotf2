// Copyright Hewlett Packard Enterprise Development LP.

module OTF2_GlobalDefReaderCallbacks_Mod {
  use CTypes;
  use OTF2_ErrorCodes;
  use OTF2_GeneralDefinitions;
  require "otf2/OTF2_GlobalDefReaderCallbacks.h";

  extern record OTF2_GlobalDefReaderCallbacks { }

  extern proc OTF2_GlobalDefReaderCallbacks_New() : c_ptr(OTF2_GlobalDefReaderCallbacks);

  extern proc OTF2_GlobalDefReaderCallbacks_Delete(
    globalDefReaderCallbacks: c_ptr(OTF2_GlobalDefReaderCallbacks)
  );

  /*
  I would like to be able to do the following:

  // Callback function pointer type
  // However, at present, there is no way to specify the types of the arguments and returns of a c_fn_ptr
  extern type OTF2_GlobalDefReaderCallback_String =
      c_fn_ptr(fn(userData: c_ptr(void),
                  self: OTF2_StringRef,
                  string: c_ptrConst(c_char)): OTF2_CallbackCode);

  // The main function declaration
  extern proc OTF2_GlobalDefReaderCallbacks_SetStringCallback(
      globalDefReaderCallbacks: c_ptr(OTF2_GlobalDefReaderCallbacks),
      stringCallback: OTF2_GlobalDefReaderCallback_String
  ): OTF2_ErrorCode;

  // Example callback implementation
  proc myStringCallback(userData: c_ptr(void),
                      self: OTF2_StringRef,
                      string: c_ptrConst(c_char)): OTF2_CallbackCode {
      // Convert C string to Chapel string
      var chapelString = createStringWithNewBuffer(string);
      writeln("String definition: ID=", self, " value='", chapelString, "'");

      return OTF2_CALLBACK_SUCCESS;
  }

  // Usage example
  proc setupCallbacks(callbacks: c_ptr(OTF2_GlobalDefReaderCallbacks)) {
      // Get function pointer to your callback
      var callbackPtr: OTF2_GlobalDefReaderCallback_String =
          c_ptrTo(myStringCallback): OTF2_GlobalDefReaderCallback_String;

      // Set the callback
      var result = OTF2_GlobalDefReaderCallbacks_SetStringCallback(callbacks, callbackPtr);

      if result != OTF2_SUCCESS {
          writeln("Failed to set string callback");
      }
  }
  */

  extern proc OTF2_GlobalDefReaderCallbacks_SetClockPropertiesCallback(
    globalDefReaderCallbacks: c_ptr(OTF2_GlobalDefReaderCallbacks),
    clockPropertiesCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_GlobalDefReaderCallbacks_SetStringCallback(
    globalDefReaderCallbacks: c_ptr(OTF2_GlobalDefReaderCallbacks),
    stringCallback: c_fn_ptr
    ): OTF2_ErrorCode;

  extern proc OTF2_GlobalDefReaderCallbacks_SetLocationGroupCallback(
    globalDefReaderCallbacks: c_ptr(OTF2_GlobalDefReaderCallbacks),
    locationGroupCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_GlobalDefReaderCallbacks_SetLocationCallback(
    globalDefReaderCallbacks: c_ptr(OTF2_GlobalDefReaderCallbacks),
    locationCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_GlobalDefReaderCallbacks_SetRegionCallback(
    globalDefReaderCallbacks: c_ptr(OTF2_GlobalDefReaderCallbacks),
    regionCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_GlobalDefReaderCallbacks_SetMetricMemberCallback(
    globalDefReaderCallbacks: c_ptr(OTF2_GlobalDefReaderCallbacks),
    metricMemberCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_GlobalDefReaderCallbacks_SetMetricClassCallback(
    globalDefReaderCallbacks: c_ptr(OTF2_GlobalDefReaderCallbacks),
    metricClassCallback: c_fn_ptr
  ): OTF2_ErrorCode;

  extern proc OTF2_GlobalDefReaderCallbacks_SetMetricInstanceCallback(
    globalDefReaderCallbacks: c_ptr(OTF2_GlobalDefReaderCallbacks),
    metricInstanceCallback: c_fn_ptr
  ): OTF2_ErrorCode;
  
  extern proc OTF2_GlobalDefReaderCallbacks_SetMetricClassRecorderCallback(
    globalDefReaderCallbacks: c_ptr(OTF2_GlobalDefReaderCallbacks),
    metricClassRecorderCallback: c_fn_ptr
  ): OTF2_ErrorCode;
}