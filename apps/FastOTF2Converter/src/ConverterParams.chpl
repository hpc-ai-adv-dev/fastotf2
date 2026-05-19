// Copyright Hewlett Packard Enterprise Development LP.
//
// Compile-time configuration knobs for the converter.
// All config params live here so they have a single source of truth.
// Any module that needs a param adds: use ConverterParams;

module ConverterParams {

  // When true, event callback bodies are no-ops (return SUCCESS immediately).
  // Callbacks are still registered and called by OTF2 — this measures raw
  // C-library read + dispatch overhead without any Chapel processing.
  config param noopCallbacks: bool = false;

  // When false, phase and per-task stopwatch instrumentation is compiled out.
  // The single global_sw per strategy (total program wall-clock time) is exempt.
  config param enableTimers: bool = true;

  // When false, logDebug and logTrace calls are compiled out.
  // logError, logWarn, and logInfo are always available.
  config param enableVerboseLogging: bool = true;

}
