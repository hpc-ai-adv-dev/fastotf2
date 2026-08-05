// Copyright Hewlett Packard Enterprise Development LP.

module ConverterParallelism {
  use ConverterArgs;
  use ConverterCommon;
  use ConverterParams;
  use ConverterWriters;
  use FastOTF2;
  use CTypes;
  use List;
  use Map;

  private proc ceilDiv(numerator: int, denominator: int): int {
    if denominator == 0 then return 0;
    return (numerator + denominator - 1) / denominator;
  }

  private proc countRange(low: int, high: int): string {
    if low == high then return low:string;
    return low:string + ".." + high:string;
  }

  @chplcheck.ignore("IncorrectIndentation")
  proc printLocationGroupParallelism(
    const ref conf: ConverterConfig,
    const ref defCtx: DefCallbackContext,
    const ref evtArgs: EvtCallbackArgs,
    numberOfLocations: c_uint64,
    const ref groupLocationMap: map(string, list(OTF2_LocationRef)),
    totalReaders: int
  ) throws {
    const rawLocationGroups = defCtx.locationGroupIds.size;
    const resolvedGroups = groupLocationMap.size;
    const collapsedOrEmptyGroups = max(0, rawLocationGroups - resolvedGroups);
    const maxTaskPar = here.maxTaskPar;
    const allocatedWorkerCapacity = numLocales * maxTaskPar;
    const activeLocales = min(numLocales, totalReaders);
    const idleLocales = numLocales - activeLocales;
    const activeWorkerCapacity = activeLocales * maxTaskPar;

    const minReadersPerLocale = if activeLocales > 0
      then totalReaders / activeLocales
      else 0;
    const maxReadersPerLocale = if activeLocales > 0
      then ceilDiv(totalReaders, activeLocales)
      else 0;
    var minGroupsPerReader = 0;
    var maxGroupsPerReader = 0;
    var firstReaderLocale = true;
    for localeId in 0..<numLocales {
      const localeGroups = resolvedGroups / numLocales +
        if localeId < resolvedGroups % numLocales then 1 else 0;
      const localeReaders = totalReaders / numLocales +
        if localeId < totalReaders % numLocales then 1 else 0;
      if localeReaders > 0 {
        const localMin = localeGroups / localeReaders;
        const localMax = ceilDiv(localeGroups, localeReaders);
        if firstReaderLocale || localMin < minGroupsPerReader then
          minGroupsPerReader = localMin;
        if firstReaderLocale || localMax > maxGroupsPerReader then
          maxGroupsPerReader = localMax;
        firstReaderLocale = false;
      }
    }

    var assignedLocations = 0;
    var minLocationsPerGroup = 0;
    var maxLocationsPerGroup = 0;
    var firstGroup = true;
    var writeGroups = 0;
    var writeLocationUpperBound = 0;
    for groupName in groupLocationMap.keys() {
      const groupLocations = groupLocationMap[groupName].size;
      assignedLocations += groupLocations;
      if firstGroup || groupLocations < minLocationsPerGroup then
        minLocationsPerGroup = groupLocations;
      if firstGroup || groupLocations > maxLocationsPerGroup then
        maxLocationsPerGroup = groupLocations;
      firstGroup = false;

      if evtArgs.processesToTrack.isEmpty() ||
         evtArgs.processesToTrack.contains(groupName) {
        writeGroups += 1;
        writeLocationUpperBound += groupLocations;
      }
    }
    const averageLocationsPerGroup = if resolvedGroups > 0
      then assignedLocations:real / resolvedGroups:real
      else 0.0;

    writeln();
    writeln("=== Parallelism Preflight ===");
    writeln("Strategy: ", conf.strategy);
    writeln("Output format: ", conf.outputFormat:string);
    writeln();
    writeln("Trace topology");
    writeln("  OTF2 locations: ", numberOfLocations);
    writeln("  Raw OTF2 location groups: ", rawLocationGroups);
    writeln("  Resolved output groups (real groups): ", resolvedGroups);
    writeln("  Folded/empty raw groups: ", collapsedOrEmptyGroups);
    writeln("  Locations per resolved group: ",
            countRange(minLocationsPerGroup, maxLocationsPerGroup),
            " (average ", averageLocationsPerGroup, ")");
    if assignedLocations != numberOfLocations:int then
      writeln("  Warning: resolved groups account for ", assignedLocations,
              " of ", numberOfLocations, " OTF2 locations");

    writeln();
    writeln("Allocated resources and work distribution");
    writeln("  Locales: ", numLocales);
    writeln("  maxTaskPar per locale: ", maxTaskPar);
    writeln("  Allocated Chapel worker capacity: ", allocatedWorkerCapacity);
    writeln("  Reader pipelines: min(resolved groups, locales * maxTaskPar) = ",
            totalReaders);
    writeln("  Locales owning reader pipelines: ", activeLocales,
            " (idle: ", idleLocales, ")");
    writeln("  Readers per active locale: ",
            countRange(minReadersPerLocale, maxReadersPerLocale));
    writeln("  Resolved groups per reader: ",
            countRange(minGroupsPerReader, maxGroupsPerReader));
    writeln("  Balance basis: group count, not locations, events, or bytes");
    writeln("  Worker capacity on locales with readers: up to ",
            activeWorkerCapacity, " shared worker slots");

    writeln();
    writeln("Phase parallelism");
    writeln("  Definitions: serial on locale 0");
    writeln("    One OTF2 global-definition reader");
    writeln("  Group resolution/distribution: serial on locale 0");
    writeln("  Event open/read: ", totalReaders,
            " concurrent reader pipelines; each OTF2 reader is serial");
    if noopCallbacks {
      writeln("  Event processing: callback bodies are compiled as no-ops");
      writeln("  Output: disabled by noopCallbacks=true");
    } else {
      writeln("  Event processing: ", totalReaders,
              " concurrent serial callback streams");
      writeln("  Pipeline overlap: read/write phases overlap across readers");
      writeln("  Callgraph file tasks: up to ", writeLocationUpperBound);
      writeln("    Parallel across readers, groups, and locations");
      if conf.sortCallgraph then
        writeln("  Callgraph sorting: parallel across and within large files");
      else
        writeln("  Callgraph sorting: disabled");
      if conf.outputFormat == OutputFormat.PARQUET {
        writeln("  Parquet columns: data-parallel materialization per file");
        writeln("  Parquet encoding: serial per file; files run concurrently");
      } else {
        writeln("  CSV rows: serial per file; files run concurrently");
      }
      writeln("  Metrics file tasks: up to ", writeGroups,
              " (serial rows per file)");
      writeln("  Write ordering: callgraphs precede metrics per reader");
      writeln("    Different readers can overlap these phases");
      writeln("  Worker sharing: readers and output tasks share maxTaskPar");
    }
    if writeGroups < resolvedGroups then
      writeln("  Process filter: output bounds cover ", writeGroups,
            " of ", resolvedGroups,
            " groups; all groups are still assigned to readers");

    writeln();
    writeln("Scaling headroom");
    const readerHeadroom = resolvedGroups - totalReaders;
    if readerHeadroom > 0 {
      writeln("  Direct reader scaling: AVAILABLE (", readerHeadroom,
              " additional group-owned readers possible)");
      writeln("  Reader saturation at current maxTaskPar: ",
              ceilDiv(resolvedGroups, maxTaskPar), " locales");
      writeln("  More resources can increase read/callback concurrency");
    } else {
      writeln("  Direct reader scaling: SATURATED (", totalReaders,
              " readers for ", resolvedGroups, " resolved groups)");
      writeln("  More cores cannot add readers; they can serve output tasks");
    }

    const localePlacementHeadroom = max(0, resolvedGroups - activeLocales);
    if localePlacementHeadroom > 0 {
      writeln("  Locale placement headroom: ", localePlacementHeadroom,
              " more locales can own at least one resolved group");
      writeln("  Additional-locale verdict: MAY HELP up to ", resolvedGroups,
              " locales by spreading reader pipelines, nested writes, ",
              "memory traffic, and I/O");
      if readerHeadroom == 0 {
        writeln("  Why gains remain after reader saturation:");
        writeln("    Readers share fewer workers/resources per locale");
        writeln("    Writes gain worker, memory, and I/O capacity");
      }
    } else {
      writeln("  Locale placement headroom: NONE");
      writeln("  Additional-locale verdict: NO NEW CONVERTER PARALLELISM");
      writeln("    Locales beyond ", resolvedGroups,
              " receive no conversion work");
    }
    writeln("  Actual speedup remains workload/filesystem dependent");
    writeln("  This report describes capacity, not guaranteed speedup");
    writeln("=== End Parallelism Preflight ===");
    writeln();
  }
}