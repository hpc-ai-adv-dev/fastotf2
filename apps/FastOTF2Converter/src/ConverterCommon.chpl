// Copyright Hewlett Packard Enterprise Development LP.
//
// Shared types and helpers used by all converter modules.
// Provides logging, record types, and common helper procs.

module ConverterCommon {
  use FastOTF2;
  use List;
  use Map;
  use CallGraphModule;
  use IO;

  // ---------------------------------------------------------------------------
  // Logging infrastructure
  // ---------------------------------------------------------------------------

  enum LogLevel {
    NONE,
    ERROR,
    WARN,
    INFO,
    DEBUG,
    TRACE
  }

  var log: LogLevel = LogLevel.INFO;

  const BLUE = "\x1b[94m";
  const GREEN = "\x1b[92m";
  const YELLOW = "\x1b[93m";
  const RED = "\x1b[91m";
  const ENDC = "\x1b[0m";

  proc logError(args ...?n) {
    if log >= LogLevel.ERROR {
      writeln(RED, "[ERROR] ", ENDC, (...args));
    }
  }

  proc logWarn(args ...?n) {
    if log >= LogLevel.WARN {
      writeln(YELLOW, "[WARN] ", ENDC, (...args));
    }
  }

  proc logInfo(args ...?n) {
    if log >= LogLevel.INFO {
      writeln(GREEN, "[INFO] ", ENDC, (...args));
    }
  }

  proc logDebug(args ...?n) {
    if log >= LogLevel.DEBUG {
      writeln(BLUE, "[DEBUG] ", ENDC, (...args));
    }
  }

  proc logTrace(args ...?n) {
    if log >= LogLevel.TRACE {
      writeln(RED, "[TRACE] ", ENDC, (...args));
    }
  }

  // ---------------------------------------------------------------------------
  // Record types
  // ---------------------------------------------------------------------------

  // TODO(refactor): Move ClockProperties into the FastOTF2 library package.
  record ClockProperties {
    // See https://perftools.pages.jsc.fz-juelich.de/cicd/otf2/tags/latest/html/group__records__definition.html#ClockProperties
    var timerResolution: uint(64);
    var globalOffset: uint(64);
    var traceLength: uint(64);
    var realtimeTimestamp: uint(64);
  }

  // TODO(refactor): Move definition records into the FastOTF2 library package.
  record LocationGroup {
    var name: string;
    var creatingLocationGroup: string;
  }
  record Location {
    var name: string;
    var group: OTF2_LocationGroupRef;
  }

  record MetricMember {
    var name: string;
    var unit: string;
  }

  // TODO(refactor): Unify MetricClass and MetricInstance under a common base.
  record MetricClass {
    var numberOfMetrics: c_uint8;
    var firstMemberID: OTF2_MetricMemberRef;  // Store just the first member ID directly
  }

  record MetricInstance {
    var metricClass: OTF2_MetricRef;
    var recorder: OTF2_LocationRef;
  }

  record MetricDefContext {
    var metricClassIds: domain(OTF2_MetricRef);
    var metricClassTable: [metricClassIds] MetricClass;
    var metricInstanceIds: domain(OTF2_MetricRef);
    var metricInstanceTable: [metricInstanceIds] MetricInstance;
    var metricMemberIds: domain(OTF2_MetricMemberRef);
    var metricMemberTable: [metricMemberIds] MetricMember;
    var metricClassRecorderIds: domain(OTF2_MetricRef);
    var metricClassRecorderTable: [metricClassRecorderIds] OTF2_LocationRef;
  }

  record DefCallbackContext {
    var locationGroupIds: domain(OTF2_LocationGroupRef);
    var locationGroupTable: [locationGroupIds] LocationGroup;
    var locationIds: domain(OTF2_LocationRef);
    var locationTable: [locationIds] Location;
    var regionIds: domain(OTF2_RegionRef);
    var regionTable: [regionIds] string;
    var stringIds: domain(OTF2_StringRef);
    var stringTable: [stringIds] string;
    var clockProps: ClockProperties;
    var metricDefContext: MetricDefContext;
  }

  record EvtCallbackArgs {
    const processesToTrack: domain(string);
    const metricsToTrack: domain(string);
    const excludeMPI: bool = false;
    const excludeHIP: bool = false;
  }

  record EvtCallbackContext {
    const evtArgs: EvtCallbackArgs;
    var defContext: DefCallbackContext;
    var seenGroups: map(string, domain(string));
    // Call Graphs are per location group and per location (thread)
    var callGraphs: map(string, map(string, shared CallGraph));
    // Metrics recorded per location group and per location (thread)
    var metrics: map(string, map(string, list((real(64), OTF2_Type, OTF2_MetricValue))));

    proc init(evtArgs: EvtCallbackArgs,
              defContext: DefCallbackContext) {
      this.evtArgs = evtArgs;
      this.defContext = defContext;
      this.seenGroups = new map(string, domain(string));
      this.callGraphs = new map(string, map(string, shared CallGraph));
      this.metrics = new map(string, map(string, list((real(64), OTF2_Type, OTF2_MetricValue))));
    }
  }

  // ---------------------------------------------------------------------------
  // Helper procs
  // ---------------------------------------------------------------------------

  proc timestampToSeconds(ts: OTF2_TimeStamp, clockProps: ClockProperties): real(64) {
    if clockProps.timerResolution == 0 then
      return 0.0;
    // We use this start_time to normalize timestamps to start from zero
    // We don't use a ProgramBegin event because each MPI rank will have its own
    // and we want a global start time
    const start_time = clockProps.globalOffset;
    if ts < start_time {
      return -1.0 * ((start_time - ts):real(64) / clockProps.timerResolution);
    }
    return (ts - start_time):real(64) / clockProps.timerResolution;
  }

  proc getLocationAndRegionInfo(defCtx: DefCallbackContext,
                       location: OTF2_LocationRef,
                       region: OTF2_RegionRef) : (string, string, string) {
    const locName = if defCtx.locationIds.contains(location) then defCtx.locationTable[location].name else "UnknownLocation";
    var locGroup = "UnknownLocationGroup";
    if defCtx.locationIds.contains(location) {
      const lgid = defCtx.locationTable[location].group;
      if defCtx.locationGroupIds.contains(lgid) {
        const locationGroup = defCtx.locationGroupTable[lgid];
        // Use creating_location_group if it exists (matching Python behavior)
        locGroup = if locationGroup.creatingLocationGroup != "None" && locationGroup.creatingLocationGroup != "" 
                   then locationGroup.creatingLocationGroup
                   else locationGroup.name;
      }
    }
    const regionName = if defCtx.regionIds.contains(region) then defCtx.regionTable[region] else "UnknownRegion";
    return (locName, locGroup, regionName);
  }

  proc updateMaps(ref ctx: EvtCallbackContext, locGroup: string, location: string) {
    // Update seen groups
    try! {
      ref seenGroups = ctx.seenGroups;
      if !seenGroups.contains(locGroup) {
        seenGroups[locGroup] = {location};
        logDebug("New group and thread: ", location, " in group ", locGroup);
      } else if !seenGroups[locGroup].contains(location) {
        seenGroups[locGroup] += location;
        logDebug("New thread: ", location, " in existing group ", locGroup);
      }
    }

    try! {
    // Update call graphs
    ref callGraphs = ctx.callGraphs;
    if !callGraphs.contains(locGroup) {
      logDebug("New call graph group: ", locGroup);
      callGraphs[locGroup] = new map(string, shared CallGraph);
    }
    if !callGraphs[locGroup].contains(location) {
      logDebug("New call graph for thread: ", location, " in group ", locGroup);
      // TODO(chapel-bug): map[key] = new shared CallGraph() triggers an
      // ownership issue in the Chapel compiler. Using add() works around it.
      callGraphs[locGroup].add(location, new shared CallGraph());
    }
    }

    // Update metrics
    ref metrics = ctx.metrics;
    if !metrics.contains(locGroup) {
      metrics[locGroup] = new map(string, list((real(64), OTF2_Type, OTF2_MetricValue)));
      for metric in ctx.evtArgs.metricsToTrack {
        metrics[locGroup][metric] = new list((real(64), OTF2_Type, OTF2_MetricValue));
        logDebug("New metric list for metric: ", metric, " in group ", locGroup);
      }
    }
  }

  proc getMetricInfo(defCtx: DefCallbackContext,
                     location: OTF2_LocationRef,
                     metric: OTF2_MetricRef): (string, string, string) {
    var metricName: string;
    var metricUnit: string;
    var metricRecorder: string;

    ref metricCtx = defCtx.metricDefContext;
    var metricClassRef: OTF2_MetricRef;
    // This metric can be a metric class or a metric instance, check both
    // If it is a metric instance, it will also have a recorder location
    // Otherwise the recorder is the same as the location of the event
    if metricCtx.metricInstanceIds.contains(metric) {
      const mInstance = metricCtx.metricInstanceTable[metric];
      metricRecorder = if defCtx.locationIds.contains(mInstance.recorder) then defCtx.locationTable[mInstance.recorder].name else "UnknownLocation";
      metricClassRef = mInstance.metricClass;
    } else {
      metricClassRef = metric;
      (metricRecorder, _, _) = getLocationAndRegionInfo(defCtx, location, 0);
    }
    if metricCtx.metricClassIds.contains(metricClassRef) {
      const metricClass = metricCtx.metricClassTable[metricClassRef];
      if metricClass.numberOfMetrics == 1 { // We only handle single metric members for now
        const metricMemberRef = metricClass.firstMemberID;
        if metricCtx.metricMemberIds.contains(metricMemberRef) {
          const metricMember = metricCtx.metricMemberTable[metricMemberRef];
          metricName = metricMember.name;
          metricUnit = metricMember.unit;
        } else {
          metricName = "UnknownMetricMember";
          metricUnit = "UnknownUnit";
        }
      } else {
        logWarn("Metric class with ", metricClass.numberOfMetrics, " members - only processing first member");
        // Instead of halting, just process the first member
        const metricMemberRef = metricClass.firstMemberID;
        if metricCtx.metricMemberIds.contains(metricMemberRef) {
          const metricMember = metricCtx.metricMemberTable[metricMemberRef];
          metricName = metricMember.name;
          metricUnit = metricMember.unit;
        } else {
          metricName = "UnknownMetricMember";
          metricUnit = "UnknownUnit";
        }
      }
    } else {
      metricName = "UnknownMetricClass";
      metricUnit = "UnknownUnit";
    }
    return (metricName, metricUnit, metricRecorder);
  }

  proc checkEnterLeaveSkipConditions(const ref ctx: EvtCallbackContext,
                                     locGroup: string,
                                     regionName: string): bool {
    // Skip events for processes not in the tracking list (empty = track all)
    if (ctx.evtArgs.processesToTrack.size > 0) &&
      (!ctx.evtArgs.processesToTrack.contains(locGroup)) {
      return true; // Skip this event
    }
    if (!ctx.evtArgs.excludeHIP && !ctx.evtArgs.excludeMPI) {
      return false; // Do not skip
    }
    const regionNameLower = regionName.toLower();
    if regionNameLower.size >= 3 {
      const prefix = regionNameLower[0..2];
      if prefix == "mpi" && ctx.evtArgs.excludeMPI {
        logTrace("Skipping MPI region: ", regionName, " in group ", locGroup);
        return true;
      }
      if prefix == "hip" && ctx.evtArgs.excludeHIP {
        logTrace("Skipping HIP region: ", regionName, " in group ", locGroup);
        return true;
      }
    }
    return false; // Do not skip
  }

  // ---------------------------------------------------------------------------
  // Debug print helper
  // ---------------------------------------------------------------------------

  proc printCallGraphAndMetrics(ref evtCtx: EvtCallbackContext, verbose: bool = false) {
    logDebug("\n--- Call Graphs ---");
    logDebug("Total location groups with call graphs: ", evtCtx.callGraphs.size);
    for locGroup in evtCtx.callGraphs.keys() {
      logDebug("Location Group: ", locGroup);
      const locMap = evtCtx.callGraphs[locGroup];
      for locName in locMap.keys() {
        logDebug("  Thread: ", locName);
      }
    }

    logDebug("\n--- Metrics Summary ---");
    var totalMetricsStored: int = 0;
    for locGroup in evtCtx.metrics.keys() {
      logDebug("Location Group: ", locGroup);
      const metricMap = evtCtx.metrics[locGroup];
      for metricName in metricMap.keys() {
        const values = metricMap[metricName];
        logDebug("  Metric: ", metricName, ", Count: ", values.size);
        if values.size > 0 {
          logDebug("First Value: ", values[0]);
        }
        totalMetricsStored += values.size;
      }
    }
    logDebug("Total metrics stored: ", totalMetricsStored);
  }
}
