// Copyright Hewlett Packard Enterprise Development LP.
//
// Group/location mapping utilities for the converter.
// Maps OTF2 locations to their resolved output group names (handling
// HIP context folding) and provides helpers for partitioning groups
// across reader tasks.

module ConverterGroupMap {
  use FastOTF2;
  use ConverterCommon;
  use List;
  use Map;

  // -------------------------------------------------------------------------
  // resolveOutputGroup — resolve a location group to its output group name
  // -------------------------------------------------------------------------

  proc resolveOutputGroup(
    const ref defCtx: DefCallbackContext,
    groupRef: OTF2_LocationGroupRef
  ): string {
    if defCtx.locationGroupIds.contains(groupRef) {
      const locationGroup = defCtx.locationGroupTable[groupRef];
      return if locationGroup.creatingLocationGroup != "None"
                && locationGroup.creatingLocationGroup != ""
             then locationGroup.creatingLocationGroup
             else locationGroup.name;
    }
    return "UnknownGroup";
  }

  // -------------------------------------------------------------------------
  // buildGroupLocationMap — build output-group → locations map
  //
  // Groups locations by their *resolved output group name* (the name used
  // for output filenames), NOT by raw OTF2 location group ID.  HIP contexts
  // whose creatingLocationGroup points to an MPI rank are folded under that
  // rank's name, so all locations that contribute to the same output files
  // end up in the same partition.
  // -------------------------------------------------------------------------

  proc buildGroupLocationMap(
    const ref defCtx: DefCallbackContext
  ): map(string, list(OTF2_LocationRef)) throws {
    var groupLocationMap: map(string, list(OTF2_LocationRef));
    for locId in defCtx.locationIds {
      const loc = defCtx.locationTable[locId];
      const outputGroup = resolveOutputGroup(defCtx, loc.group);
      groupLocationMap[outputGroup].pushBack(locId);
    }

    logDebug("Found ", groupLocationMap.size, " output groups");
    for name in groupLocationMap.keys() {
      logDebug("  Output group '", name, "': ",
               groupLocationMap[name].size, " locations");
    }

    return groupLocationMap;
  }

  // -------------------------------------------------------------------------
  // orderedOutputGroups — deterministic ordering of output group names
  // -------------------------------------------------------------------------

  proc orderedOutputGroups(
    const ref defCtx: DefCallbackContext,
    const ref groupLocationMap: map(string, list(OTF2_LocationRef))
  ): [] string {
    const totalGroups = groupLocationMap.size;
    var groups: [0..<totalGroups] string;
    var seen: domain(string);
    var idx = 0;

    // Walk OTF2 location groups in definition order, resolve to output name,
    // and add each unique output name once.
    for gid in defCtx.locationGroupIds {
      const name = resolveOutputGroup(defCtx, gid);
      if groupLocationMap.contains(name) && !seen.contains(name) {
        groups[idx] = name;
        seen += name;
        idx += 1;
      }
    }

    // Safety: pick up any names not yet emitted
    if idx < totalGroups {
      for name in groupLocationMap.keys() {
        if !seen.contains(name) {
          groups[idx] = name;
          seen += name;
          idx += 1;
          if idx == totalGroups then break;
        }
      }
    }

    return groups;
  }

  // -------------------------------------------------------------------------
  // locationsForOutputGroups — collect all locations for a list of output group names
  // -------------------------------------------------------------------------

  proc locationsForOutputGroups(
    const ref groupNames: [] string,
    const ref groupLocationMap: map(string, list(OTF2_LocationRef))
  ): [] OTF2_LocationRef throws {
    var totalLocs = 0;
    for name in groupNames do totalLocs += groupLocationMap[name].size;

    var locs: [0..<totalLocs] OTF2_LocationRef;
    var idx = 0;
    for name in groupNames {
      for loc in groupLocationMap[name] {
        locs[idx] = loc;
        idx += 1;
      }
    }
    return locs;
  }
}
