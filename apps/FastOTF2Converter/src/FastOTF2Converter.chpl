// Copyright Hewlett Packard Enterprise Development LP.

module FastOTF2Converter {
  use ConverterArgs;
  use Strategy_Serial;
  use Strategy_LocBlock;
  use Strategy_LocGroupBlock;
  use Strategy_LocGroupDistBlock;
  use CTypes;
  use MemDiagnostics;
  private use MemTracking;
  // Future strategies:
  // use Strategy_LocDynamic;
  // use Strategy_LocGroupDynamic;
  // use Strategy_LocGroupBlockDistDynamic;
  // use Strategy_LocGroupDistBalanced;

  require "helpers/memtrack_helper.h";
  extern proc get_peak_rss_kb(): c_long;

  param KB_PER_GB = 1024.0 * 1024.0;

  proc main(args: [] string) throws {
    const conf = parseConverterArgs(args);
    validatePaths(conf);

    // Capture baseline RSS per locale (before work)
    var baselineKB: [0..#numLocales] int;
    if memTrack {
      coforall loc in Locales do on loc {
        baselineKB[here.id] = get_peak_rss_kb(): int;
      }
    }

    select conf.strategy {
      when "serial" do
        Strategy_Serial.run(conf);
      when "loc_block" do
        Strategy_LocBlock.run(conf);
      when "loc_dynamic" do
        halt("Strategy loc_dynamic not yet implemented");
      when "locgroup_block" do
        Strategy_LocGroupBlock.run(conf);
      when "locgroup_dynamic" do
        halt("Strategy locgroup_dynamic not yet implemented");
      when "locgroup_dist_block" do
        Strategy_LocGroupDistBlock.run(conf);
      when "locgroup_blockdist_dynamic" do
        halt("Strategy locgroup_blockdist_dynamic not yet implemented");
      when "locgroup_dist_balanced" do
        halt("Strategy locgroup_dist_balanced not yet implemented");
      otherwise
        halt("Unknown strategy: ", conf.strategy,
             ". Use one of: serial, loc_block, loc_dynamic, locgroup_block, ",
             "locgroup_dynamic, locgroup_dist_block, ",
             "locgroup_blockdist_dynamic, locgroup_dist_balanced");
    }

    // Report memory stats if --memTrack was passed
    if memTrack {
      writeln();
      writeln("=== Memory Report ===");
      coforall loc in Locales do on loc {
        var peakKB = get_peak_rss_kb(): int;
        var deltaKB = peakKB - baselineKB[here.id];
        var peakGB = peakKB: real / KB_PER_GB;
        var deltaGB = deltaKB: real / KB_PER_GB;
        writeln("  Locale ", here.id,
                ": peak RSS=", peakGB, " GB",
                "  delta RSS (OTF2+parquet memory usage)=", deltaGB, " GB");
        printMemAllocStats();
      }
      writeln("=== End Memory Report ===");
    }
  }
}
