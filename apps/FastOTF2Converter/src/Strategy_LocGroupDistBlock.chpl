// Copyright Hewlett Packard Enterprise Development LP.
//
// Location-group distributed block strategy.
// Block-distributes groups across locales, then block-partitions within
// each locale across its tasks.
//
// Multi-locale.

module Strategy_LocGroupDistBlock {
  use ConverterDefReaders;
  use ConverterCommon;
  use FastOTF2;
  use Time;
  use List;
  use Map;
  use BlockDist;
  use RangeChunk;

  proc run(conf: ConverterConfig) throws {
    var sw: stopwatch;
    var global_sw: stopwatch;
    sw.start();
    global_sw.start();

    const (defCtx, numberOfLocations) = readGlobalDefinitions(conf.trace);
    const evtArgs = buildEvtCallbackArgs(conf);

    const defReadTime = sw.elapsed();
    sw.clear();

    // Build output-group ownership map (resolves HIP contexts to parent MPI ranks)
    const groupLocationMap = buildGroupLocationMap(defCtx);
    const groupNames = orderedOutputGroups(defCtx, groupLocationMap);
    const totalGroups = groupNames.size;
    logInfo("Using locgroup_dist_block strategy with ", numLocales,
            " locales for ", totalGroups, " output groups");

    // Block-distribute group indices across locales
    const groupDom = blockDist.createDomain(0..<totalGroups);
    var totalEventsRead: c_uint64 = 0;

    logInfo("Writing ", conf.outputFormat: string, " files to directory: ",
            conf.outputDir, " as each reader completes (no merge needed)");

    coforall loc in Locales with (+ reduce totalEventsRead) {
      on loc {
        // Find which group indices are local to this locale
        const mySubDom = groupDom.localSubdomain();
        const nGroups = mySubDom.size;
        if nGroups == 0 {
          logTrace("Locale ", loc.id, " has no groups assigned");
        } else {
          const numberOfReaders = min(here.maxTaskPar, nGroups);
          logTrace("Locale ", loc.id, " processing ", nGroups,
                   " groups with ", numberOfReaders, " reader tasks");

          // Block-partition local output groups across reader tasks
          var readerGroups: [0..<numberOfReaders] list(string);
          const localGroupIndices: [0..<nGroups] int = for i in mySubDom do i;
          for (r, groupRange) in zip(0..<numberOfReaders, chunks(0..<nGroups, numberOfReaders)) {
            for idx in groupRange {
              readerGroups[r].pushBack(groupNames[localGroupIndices[idx]]);
            }
          }

          var evtContexts = [0..<numberOfReaders] new EvtCallbackContext(evtArgs, defCtx);
          var localeEventsRead: c_uint64 = 0;

          coforall i in 0..<numberOfReaders
            with (+ reduce localeEventsRead, ref evtContexts) {

            const myGroupNames: [0..<readerGroups[i].size] string =
              for g in readerGroups[i] do g;
            const myLocs = locationsForOutputGroups(myGroupNames, groupLocationMap);

            logTrace("Locale ", loc.id, " reader ", i, " assigned ",
                     readerGroups[i].size, " groups with ", myLocs.size, " locations");

            const localTraceName = conf.trace;
            localeEventsRead += readEventsForLocations(localTraceName, myLocs, evtContexts[i]);
            writeOutputForContext(evtContexts[i], conf.outputFormat, conf.outputDir);
          }

          totalEventsRead += localeEventsRead;
        }
      }
    }

    const evtReadTime = sw.elapsed();
    logDebug("Time taken to read events and write output: ", evtReadTime, " seconds");

    logDebug("Total events read: ", totalEventsRead);
    logInfo("Trace loaded in ", global_sw.elapsed(), " seconds");
    logInfo("Finished converting trace in ", global_sw.elapsed(), " seconds");
  }
}
