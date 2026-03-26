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



  // Extract the integer representation of an OTF2 metric value.
  // Returns the native int64 for INT64/UINT64 types, 0 for others.
  inline proc metricValueAsInt(valueType: OTF2_Type, value: OTF2_MetricValue): int(64) {
    if valueType == OTF2_TYPE_INT64 then
      return value.signed_int: int(64);
    else if valueType == OTF2_TYPE_UINT64 then
      return value.unsigned_int: int(64);
    else
      return 0: int(64);
  }

  // Extract the real representation of an OTF2 metric value.
  // Returns the native double for DOUBLE types, 0.0 for others.
  inline proc metricValueAsReal(valueType: OTF2_Type, value: OTF2_MetricValue): real(64) {
    if valueType == OTF2_TYPE_DOUBLE then
      return value.floating_point;
    else
      return 0.0;
  }

  proc callgraphFilename(group: string, thread: string, format: OutputFormat): string {
    return group + "_" + thread.replace(" ", "_") + "_callgraph" + outputExtension(format);
  }

  proc metricsFilename(group: string, format: OutputFormat): string {
    return group + "_metrics" + outputExtension(format);
  }

  proc writeCallgraphCSV(callGraph: shared CallGraph, group: string, thread: string, outputPath: string) throws {
    const intervals = callGraph.getIntervalsBetween(-inf, inf);
    if intervals.size == 0 then return;

    var outfile = open(outputPath, ioMode.cw);
    var writer = outfile.writer(locking=false);

    writer.writeln("Thread,Group,Depth,Name,Start Time,End Time,Duration");

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
    var totalValues = 0;
    for values in threadMetrics.values() do
      totalValues += values.size;
    if totalValues == 0 then return;

    var outfile = open(outputPath, ioMode.cw);
    var writer = outfile.writer(locking=false);

    writer.writeln("Group,Metric Name,Time,Value");

    for metricName in threadMetrics.keys() {
      const values = threadMetrics[metricName];
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

  // Writes all callgraph intervals to a Parquet file with the same columns and
  // values as the CSV output: thread, group, depth, name, start_time, end_time,
  // duration.  Times are real(64) seconds — identical to CSV.
  proc writeCallgraphParquet(callGraph: shared CallGraph, group: string, thread: string, outputPath: string) throws {
    const intervals = callGraph.getIntervalsBetween(-inf, inf);
    const n = intervals.size;

    // [PARQUET-PKG-GUARD] writeTable() crashes on empty arrays.
    // Remove this guard when the Parquet package handles n=0 gracefully.
    if n == 0 then return;

    var threadCol:      [0..<n] string;
    var groupCol:       [0..<n] string;
    var depthCol:       [0..<n] int(64);
    var nameCol:        [0..<n] string;
    var startTimeCol:   [0..<n] real(64);
    var endTimeCol:     [0..<n] real(64);
    var durationCol:    [0..<n] real(64);

    for (idx, iv) in zip(0..<n, intervals) {
      const endSec = if iv.hasEnd then iv.end else inf;
      threadCol[idx]    = thread;
      groupCol[idx]     = group;
      depthCol[idx]     = iv.depth: int(64);
      nameCol[idx]      = if iv.name != "" then iv.name else "Unknown";
      startTimeCol[idx] = iv.start;
      endTimeCol[idx]   = endSec;
      durationCol[idx]  = endSec - iv.start;
    }

    writeTable(outputPath,
               colNames=("thread", "group", "depth", "name",
                         "start_time", "end_time", "duration"),
               threadCol, groupCol, depthCol, nameCol,
               startTimeCol, endTimeCol, durationCol);
  }

  // Writes all recorded metric samples to a Parquet file.
  // Columns: group, metric_name, time, value_int, value_real.
  // Time is real(64) seconds — identical to CSV.
  // INT64/UINT64 metrics populate value_int (value_real is 0.0).
  // DOUBLE metrics populate value_real (value_int is 0).
  // This preserves the native OTF2 type without forced conversions.
  proc writeMetricsParquet(group: string, threadMetrics: map(string, list((real(64), OTF2_Type, OTF2_MetricValue))), outputPath: string) throws {
    var totalValues = 0;
    for values in threadMetrics.values() do
      totalValues += values.size;

    // [PARQUET-PKG-GUARD] writeTable() crashes on empty arrays.
    // Remove this guard when the Parquet package handles n=0 gracefully.
    if totalValues == 0 then return;

    var groupCol:      [0..<totalValues] string;
    var metricNameCol: [0..<totalValues] string;
    var timeCol:       [0..<totalValues] real(64);
    var valueIntCol:   [0..<totalValues] int(64);
    var valueRealCol:  [0..<totalValues] real(64);

    var idx = 0;
    for metricName in threadMetrics.keys() {
      const values = threadMetrics[metricName];
      for (time, valueType, value) in values {
        groupCol[idx]      = group;
        metricNameCol[idx] = metricName;
        timeCol[idx]       = time;
        valueIntCol[idx]   = metricValueAsInt(valueType, value);
        valueRealCol[idx]  = metricValueAsReal(valueType, value);
        idx += 1;
      }
    }

    writeTable(outputPath,
               colNames=("group", "metric_name", "time",
                         "value_int", "value_real"),
               groupCol, metricNameCol, timeCol,
               valueIntCol, valueRealCol);
  }
}
