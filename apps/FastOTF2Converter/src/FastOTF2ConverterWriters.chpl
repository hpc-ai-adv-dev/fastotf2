module FastOTF2ConverterWriters {
  use FastOTF2;
  use List;
  use Map;
  use IO;
  use CallGraphModule;
  use Parquet;

  import Math.inf;

  enum OutputFormat {
    CSV,
    PARQUET
  }

  proc parseOutputFormat(value: string): OutputFormat throws {
    select value.toUpper() {
      when "CSV" do return OutputFormat.CSV;
      when "PARQUET" do return OutputFormat.PARQUET;
      otherwise throw new Error("Invalid output format '" + value + "'. Use CSV or PARQUET.");
    }
  }

  proc outputExtension(format: OutputFormat): string {
    if format == OutputFormat.CSV then
      return ".csv";
    else
      return ".parquet";
  }

  inline proc secondsToNanoseconds(value: real): int(64) {
    return (value * 1_000_000_000.0): int(64);
  }

  inline proc metricValueToInt64(valueType: OTF2_Type, value: OTF2_MetricValue): int(64) {
    if valueType == OTF2_TYPE_INT64 then
      return value.signed_int: int(64);
    else if valueType == OTF2_TYPE_UINT64 then
      return value.unsigned_int: int(64);
    else if valueType == OTF2_TYPE_DOUBLE then
      return value.floating_point: int(64);
    else
      return 0:int(64);
  }

  proc callgraphFilename(group: string, thread: string, format: OutputFormat): string {
    return group + "_" + thread.replace(" ", "_") + "_callgraph" + outputExtension(format);
  }

  proc metricsFilename(group: string, format: OutputFormat): string {
    return group + "_metrics" + outputExtension(format);
  }

  proc writeCallgraphCSV(callGraph: shared CallGraph, group: string, thread: string, outputPath: string) throws {
    var outfile = open(outputPath, ioMode.cw);
    var writer = outfile.writer(locking=false);

    writer.writeln("Thread,Group,Depth,Name,Start Time,End Time,Duration");

    const intervals = callGraph.getIntervalsBetween(-inf, inf);

    for iv in intervals {
      const start = iv.start;
      const end = if iv.hasEnd then iv.end else inf;
      const duration = end - start;
      const name = if iv.name != "" then iv.name else "Unknown";
      const depth = iv.depth;

      writer.writef("%s,%s,%i,\"%s\",%.15dr,%.15dr,%.15dr\n",
                    thread, group, depth, name, start, end, duration);
    }

    writer.close();
    outfile.close();
  }

  proc writeMetricsCSV(group: string, threadMetrics: map(string, list((real(64), OTF2_Type, OTF2_MetricValue))), outputPath: string) throws {
    var outfile = open(outputPath, ioMode.cw);
    var writer = outfile.writer(locking=false);

    writer.writeln("Group,Metric Name,Time,Value");

    for (metricName, values) in threadMetrics.items() {
      for (time, valueType, value) in values {
        if valueType == OTF2_TYPE_INT64 then
          writer.writef("%s,%s,%.15dr,%i\n", group, metricName, time, value.signed_int);
        else if valueType == OTF2_TYPE_UINT64 then
          writer.writef("%s,%s,%.15dr,%u\n", group, metricName, time, value.unsigned_int);
        else if valueType == OTF2_TYPE_DOUBLE then
          writer.writef("%s,%s,%.15dr,%.15dr\n", group, metricName, time, value.floating_point);
      }
    }

    writer.close();
    outfile.close();
  }

  // Writes all callgraph intervals to a Parquet file with the same columns as
  // the CSV output: thread, group, depth, name, start_ns, end_ns, duration_ns.
  // Times are stored as int64 nanoseconds (multiply CSV seconds columns by 1e9).
  // end_ns is -1 for intervals with no recorded end event.
  proc writeCallgraphParquet(callGraph: shared CallGraph, group: string, thread: string, outputPath: string) throws {
    const intervals = callGraph.getIntervalsBetween(-inf, inf);
    const n = intervals.size;

    // [PARQUET-PKG-GUARD] writeTable() crashes on empty arrays.
    // Remove this guard when the Parquet package handles n=0 gracefully.
    if n == 0 then return;

    var threadCol:   [0..<n] string;
    var groupCol:    [0..<n] string;
    var depthCol:    [0..<n] int(64);
    var nameCol:     [0..<n] string;
    var startNsCol:  [0..<n] int(64);
    var endNsCol:    [0..<n] int(64);
    var durationCol: [0..<n] int(64);

    for (idx, iv) in zip(0..<n, intervals) {
      const endSec = if iv.hasEnd then iv.end else inf;
      threadCol[idx]   = thread;
      groupCol[idx]    = group;
      depthCol[idx]    = iv.depth: int(64);
      nameCol[idx]     = if iv.name != "" then iv.name else "Unknown";
      startNsCol[idx]  = secondsToNanoseconds(iv.start);
      endNsCol[idx]    = if iv.hasEnd then secondsToNanoseconds(iv.end) else -1:int(64);
      durationCol[idx] = secondsToNanoseconds(endSec - iv.start);
    }

    writeTable(outputPath,
               colNames=("thread", "group", "depth", "name",
                         "start_ns", "end_ns", "duration_ns"),
               threadCol, groupCol, depthCol, nameCol,
               startNsCol, endNsCol, durationCol);
  }

  // Writes all recorded metric samples to a Parquet file with the same columns
  // as the CSV output: group, metric_name, time_ns, value_i64.
  // time_ns is the sample timestamp in nanoseconds (multiply CSV Time by 1e9).
  // Metric values are cast to int64 (DOUBLE metrics lose fractional precision).
  proc writeMetricsParquet(group: string, threadMetrics: map(string, list((real(64), OTF2_Type, OTF2_MetricValue))), outputPath: string) throws {
    var totalValues = 0;
    for values in threadMetrics.values() do
      totalValues += values.size;

    // [PARQUET-PKG-GUARD] writeTable() crashes on empty arrays.
    // Remove this guard when the Parquet package handles n=0 gracefully.
    if totalValues == 0 then return;

    var groupCol:      [0..<totalValues] string;
    var metricNameCol: [0..<totalValues] string;
    var timeNsCol:     [0..<totalValues] int(64);
    var valueCol:      [0..<totalValues] int(64);

    var idx = 0;
    for (metricName, values) in threadMetrics.items() {
      for (time, valueType, value) in values {
        groupCol[idx]      = group;
        metricNameCol[idx] = metricName;
        timeNsCol[idx]     = secondsToNanoseconds(time);
        valueCol[idx]      = metricValueToInt64(valueType, value);
        idx += 1;
      }
    }

    writeTable(outputPath,
               colNames=("group", "metric_name", "time_ns", "value_i64"),
               groupCol, metricNameCol, timeNsCol, valueCol);
  }
}
