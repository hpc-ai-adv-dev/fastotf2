// Copyright Hewlett Packard Enterprise Development LP.
//
// Command-line argument parsing and configuration for the converter.
// Provides the ConverterConfig record, argument parser, path validation,
// and the ConverterConfig → EvtCallbackArgs conversion.

module ConverterArgs {
  use ConverterCommon;
  use ConverterWriters;
  use ArgumentParser;
  use FileSystem;

  // -------------------------------------------------------------------------
  // ConverterConfig — holds all parsed command-line arguments
  // -------------------------------------------------------------------------

  record ConverterConfig {
    var strategy: string;
    var trace: string;
    var metrics: string;
    var processes: string;
    var outputDir: string;
    var outputFormat: OutputFormat;
    var excludeMPI: bool;
    var excludeHIP: bool;
  }

  // -------------------------------------------------------------------------
  // parseConverterArgs — full ArgumentParser for all common flags
  // -------------------------------------------------------------------------

  proc parseConverterArgs(programArgs: [] string): ConverterConfig throws {
    var conf: ConverterConfig;

    var parser = new argumentParser(addHelp=true);

    var traceArg = parser.addArgument(
      name="trace",
      defaultValue="../../sample-traces/simple-mi300-example-run/traces.otf2",
      help="Path to the OTF2 trace file"
    );

    var metricsArg = parser.addOption(
      name="metrics",
      defaultValue="",
      numArgs=1,
      help="Metrics to track (comma-separated, empty = all)"
    );

    var processesArg = parser.addOption(
      name="processes",
      defaultValue="",
      numArgs=1,
      help="Processes to track (comma-separated, empty = all)"
    );

    var outputDirArg = parser.addOption(
      name="outputDir",
      defaultValue="./",
      numArgs=1,
      help="Directory to write output files to"
    );

    var formatArg = parser.addOption(
      name="format",
      defaultValue="CSV",
      numArgs=1,
      help="Output format: CSV or PARQUET"
    );

    const defaultStrategy = if numLocales > 1
      then "locgroup_dist_balanced"
      else "locgroup_dynamic";
    var strategyArg = parser.addOption(
      name="strategy",
      defaultValue=defaultStrategy,
      numArgs=1,
      help="Partition strategy: serial, loc_block, loc_dynamic, "
           + "locgroup_block, locgroup_dynamic, locgroup_dist_block, "
           + "locgroup_blockdist_dynamic, locgroup_dist_balanced"
    );

    var excludeMPIArg = parser.addFlag(
      name="excludeMPI",
      defaultValue=false,
      numArgs=0,
      help="Exclude MPI functions from the callgraph output"
    );

    var excludeHIPArg = parser.addFlag(
      name="excludeHIP",
      defaultValue=false,
      numArgs=0,
      help="Exclude HIP functions from the callgraph output"
    );

    var logArg = parser.addOption(
      name="log",
      defaultValue="INFO",
      numArgs=1,
      help="Logging level (NONE, ERROR, WARN, INFO, DEBUG, TRACE)"
    );

    parser.parseArgs(programArgs);

    conf.strategy = strategyArg.value();
    conf.trace = traceArg.value();
    conf.metrics = metricsArg.value();
    conf.processes = processesArg.value();
    conf.outputDir = outputDirArg.value();
    conf.excludeMPI = excludeMPIArg.valueAsBool();
    conf.excludeHIP = excludeHIPArg.valueAsBool();

    try {
      log = logArg.value(): LogLevel;
    } catch e {
      logError("Invalid log level: ", logArg.value(),
               ". Use one of: NONE, ERROR, WARN, INFO, DEBUG, or TRACE.");
      halt("invalid log level");
    }

    try {
      conf.outputFormat = parseOutputFormat(formatArg.value());
    } catch e {
      logError(e.message());
      halt("invalid output format");
    }

    if conf.excludeMPI then
      logInfo("Excluding MPI functions from callgraph output");
    if conf.excludeHIP then
      logInfo("Excluding HIP functions from callgraph output");

    return conf;
  }

  // -------------------------------------------------------------------------
  // validatePaths — check trace exists, create outputDir if needed
  // -------------------------------------------------------------------------

  proc validatePaths(const ref conf: ConverterConfig) throws {
    if !exists(conf.trace) {
      logError("Trace file does not exist: ", conf.trace);
      halt("trace file not found");
    }
    if !exists(conf.outputDir) {
      logInfo("Output directory does not exist, creating: ", conf.outputDir);
      mkdir(conf.outputDir);
    }
  }

  // -------------------------------------------------------------------------
  // buildEvtCallbackArgs — parse metrics/processes strings into EvtCallbackArgs
  // -------------------------------------------------------------------------

  proc buildEvtCallbackArgs(const ref conf: ConverterConfig): EvtCallbackArgs {
    var metricsToTrack: domain(string);
    if conf.metrics != "" {
      for metric in conf.metrics.split(",") {
        metricsToTrack += metric.strip();
      }
    }

    var processesToTrack: domain(string);
    if conf.processes != "" {
      for process in conf.processes.split(",") {
        processesToTrack += process.strip();
      }
    }

    return new EvtCallbackArgs(
      processesToTrack=processesToTrack,
      metricsToTrack=metricsToTrack,
      excludeMPI=conf.excludeMPI,
      excludeHIP=conf.excludeHIP
    );
  }
}
