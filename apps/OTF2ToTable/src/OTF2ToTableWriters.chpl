module OTF2ToTableWriters {
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

  proc unimplementedFormatMessage(format: OutputFormat): string {
    return "Output format " + format:string + " is wired through the CLI, but writing " + format:string + " files is not implemented yet.";
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

  proc writeInt64ColumnParquet(outputPath: string, datasetName: string, values: [] int(64)) throws {
    if values.size == 0 {
        createEmptyParquetFile(outputPath, datasetName, ARROWINT64, CompressionType.NONE:int);
      return;
    }

    writeColumn(filename=outputPath, colName=datasetName, Arr=values);
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

  proc writeCallgraphParquet(callGraph: shared CallGraph, outputPath: string) throws {
    const intervals = callGraph.getIntervalsBetween(-inf, inf);
    var durationNs: [0..#intervals.size] int(64);

    for (idx, iv) in zip(durationNs.domain, intervals) {
      const end = if iv.hasEnd then iv.end else inf;
      durationNs[idx] = secondsToNanoseconds(end - iv.start);
    }

    writeInt64ColumnParquet(outputPath, "duration_ns", durationNs);
  }

  proc writeMetricsParquet(threadMetrics: map(string, list((real(64), OTF2_Type, OTF2_MetricValue))), outputPath: string) throws {
    var totalValues = 0;
    for values in threadMetrics.values() do
      totalValues += values.size;

    var metricValues: [0..#totalValues] int(64);
    var idx = 0;

    for values in threadMetrics.values() {
      for (_, valueType, value) in values {
        metricValues[idx] = metricValueToInt64(valueType, value);
        idx += 1;
      }
    }

    writeInt64ColumnParquet(outputPath, "value_i64", metricValues);
  }
}