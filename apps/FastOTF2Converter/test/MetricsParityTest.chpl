// Copyright Hewlett Packard Enterprise Development LP.

// MetricsParityTest.chpl
//
// Verifies that FastOTF2Converter's Parquet metrics output matches CSV output.
//
// When the trace has no metric samples the CSV file contains only the header
// and no Parquet file is created (writeTable requires >=1 row).  The tests
// handle this gracefully by verifying the empty-data invariant.
//
// Prerequisites:
//   mason run --release -- <trace> --format CSV    --outputDir /tmp/csv_out
//   mason run --release -- <trace> --format PARQUET --outputDir /tmp/pq_out
//
// Run:
//   mason test --show
//
// Override paths (for direct binary execution):
//   ./MetricsParityTest --csvDir=/path --pqDir=/path --help
//
// Known Parquet package issues (search these tags to find/remove workarounds):
//   [PARQUET-PKG-1] getDatasets() / getArrType() segfault on valid files
//   [PARQUET-PKG-2] readColumn() does not support string-typed columns

use UnitTest;
use Parquet;
use FileSystem;
use IO;
use List;

config const csvDir = "/tmp/csv_out";
config const pqDir  = "/tmp/pq_out";

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

proc metricsCSVFilesInDir(dirPath: string): domain(string) {
  var files: domain(string);
  if !exists(dirPath) || !isDir(dirPath) then return files;

  for entry in listDir(dirPath) {
    const fullPath = dirPath + "/" + entry;
    if isFile(fullPath) && entry.endsWith("_metrics.csv") {
      files += entry;
    }
  }
  return files;
}

proc metricsParquetFilesInDir(dirPath: string): domain(string) {
  var files: domain(string);
  if !exists(dirPath) || !isDir(dirPath) then return files;

  for entry in listDir(dirPath) {
    const fullPath = dirPath + "/" + entry;
    if isFile(fullPath) && entry.endsWith("_metrics.parquet") {
      files += entry;
    }
  }
  return files;
}

proc metricsInputsReady(): (bool, string) {
  if !exists(csvDir) || !isDir(csvDir) {
    return (false, "CSV directory not found: " + csvDir);
  }
  if !exists(pqDir) || !isDir(pqDir) {
    return (false, "Parquet directory not found: " + pqDir);
  }

  const csvFiles = metricsCSVFilesInDir(csvDir);
  if csvFiles.size == 0 {
    return (false, "No metrics CSV files found in " + csvDir);
  }

  return (true, "");
}

proc countCSVDataRows(path: string): int throws {
  var n = 0;
  var f = open(path, ioMode.r);
  var r = f.reader(locking=false);
  var line: string;
  r.readLine(line); // skip header
  while r.readLine(line) do n += 1;
  return n;
}

proc readCSVDataLines(path: string): list(string) throws {
  var lines: list(string);
  var f = open(path, ioMode.r);
  var r = f.reader(locking=false);
  var line: string;
  r.readLine(line); // skip header
  while r.readLine(line, stripNewline=true) {
    line = line.strip();
    if line.size > 0 then lines.pushBack(line);
  }
  return lines;
}

// CSV format: Group,Metric Name,Time,Value
// Group is first, Value is last, Time is second-to-last.
// Metric Name may span multiple comma-separated tokens.
record MetRow {
  var group, metricName, valueStr: string;
  var timeSec: real(64);
}

proc parseMetLine(line: string): MetRow throws {
  var parts = line.split(",");
  const lo = parts.domain.low;
  const hi = parts.domain.high;

  var row: MetRow;
  row.group    = parts[lo];
  row.valueStr = parts[hi];
  row.timeSec  = parts[hi - 1]: real(64);

  row.metricName = "";
  for i in lo + 1 .. hi - 2 {
    if i > lo + 1 then row.metricName += ",";
    row.metricName += parts[i];
  }
  return row;
}

// CSV values may be int ("42") or float ("42.5").
// Parquet stores them in separate columns: value_int (int64) and value_real (real64).
// For int-typed metrics, compare via int64; for real-typed, compare via real64.
proc csvValIsReal(s: string): bool {
  try {
    var tmp = s: real(64);
  } catch {
    return false;
  }
  return s.find(".") >= 0;
}
proc csvValToInt64(s: string): int(64) {
  return s: real(64) : int(64);
}
proc csvValToReal64(s: string): real(64) {
  return s: real(64);
}

// ---------------------------------------------------------------------------
// tests
// ---------------------------------------------------------------------------

// When the trace has no metric data the CSV file has only the header row
// and no Parquet file is created.  Verify this invariant.
proc testMetricsFileListParity(test: borrowed Test) throws {
  const (ready, reason) = metricsInputsReady();
  test.skipIf(!ready, reason);

  const csvFiles = metricsCSVFilesInDir(csvDir);
  const pqFiles = metricsParquetFilesInDir(pqDir);

  writeln("testing metrics parity:");
  writeln("  CSV dir:     ", csvDir);
  writeln("  PQ dir:      ", pqDir);
  writeln("  CSV files:     ", csvFiles.size);
  writeln("  Parquet files: ", pqFiles.size);

  writeln("  file list parity:");
  var missingFromCsv = 0;
  var missingParquetForNonEmptyCsv = 0;

  // Every parquet metrics file must have a matching CSV file.
  for pqFile in pqFiles {
    const baseName = pqFile[0..pqFile.size-9]; // remove ".parquet"
    const csvFile = baseName + ".csv";
    if !csvFiles.contains(csvFile) {
      writeln("    ERROR: missing CSV file for parquet: ", csvFile);
      missingFromCsv += 1;
    }
  }

  // CSV files with metric rows must have matching parquet files.
  for csvFile in csvFiles {
    const baseName = csvFile[0..csvFile.size-5];
    const pqFile = baseName + ".parquet";
    if !pqFiles.contains(pqFile) {
      const csvPath = csvDir + "/" + csvFile;
      const csvN = countCSVDataRows(csvPath);
      if csvN > 0 {
        writeln("    ERROR: missing parquet file for non-empty CSV: ", pqFile);
        missingParquetForNonEmptyCsv += 1;
      }
    }
  }

  test.assertEqual(missingFromCsv, 0);
  test.assertEqual(missingParquetForNonEmptyCsv, 0);
}

proc testMetricsRowCount(test: borrowed Test) throws {
  const (ready, reason) = metricsInputsReady();
  test.skipIf(!ready, reason);

  const csvFiles = metricsCSVFilesInDir(csvDir);
  const pqFiles = metricsParquetFilesInDir(pqDir);

  writeln("  row count parity:");
  var totalMismatches = 0;

  for csvFile in csvFiles {
    const baseName = csvFile[0..csvFile.size-5];
    const pqFile = baseName + ".parquet";
    const csvPath = csvDir + "/" + csvFile;
    const pqPath = pqDir + "/" + pqFile;

    const csvN = countCSVDataRows(csvPath);

    if !exists(pqPath) {
      // Parquet can be absent only for empty metrics CSV outputs.
      if csvN != 0 {
        writeln("    ERROR: ", csvFile, ": CSV has data but no parquet file");
        totalMismatches += 1;
      }
      continue;
    }

    const pqN = getArrSize(pqPath);
    if csvN != pqN {
      writeln("    ERROR: ", csvFile, ": CSV=", csvN, " PQ=", pqN);
      totalMismatches += 1;
    }
  }

  test.assertEqual(totalMismatches, 0);
}

proc testMetricsNumericParity(test: borrowed Test) throws {
  const (ready, reason) = metricsInputsReady();
  test.skipIf(!ready, reason);

  const csvFiles = metricsCSVFilesInDir(csvDir);
  const pqFiles = metricsParquetFilesInDir(pqDir);

  writeln("  numeric parity:");
  var totalMismatches = 0;

  for csvFile in csvFiles {
    const baseName = csvFile[0..csvFile.size-5];
    const pqFile = baseName + ".parquet";
    const csvPath = csvDir + "/" + csvFile;
    const pqPath = pqDir + "/" + pqFile;

    if !exists(pqPath) then continue;

    const n = getArrSize(pqPath);
    if n == 0 then continue;

    var pqTime:       [0..<n] real(64);
    var pqValueInt:   [0..<n] int(64);
    var pqValueReal:  [0..<n] real(64);
    readColumn(filename=pqPath, colName="time",       Arr=pqTime);
    readColumn(filename=pqPath, colName="value_int",  Arr=pqValueInt);
    readColumn(filename=pqPath, colName="value_real", Arr=pqValueReal);

    const lines = readCSVDataLines(csvPath);
    var mismatches = 0;

    for i in 0..<lines.size {
      const row = parseMetLine(lines[i]);

      // Allow ±1e-9 s tolerance for CSV text round-trip (%.15dr ≈ 15 sig digits).
      if abs(row.timeSec - pqTime[i]) > 1e-9 {
        mismatches += 1;
      }

      // Check the appropriate value column based on the CSV value format.
      // Integer values (no decimal point) are in value_int;
      // real values (with decimal point) are in value_real.
      if csvValIsReal(row.valueStr) {
        const csvVal = csvValToReal64(row.valueStr);
        if abs(csvVal - pqValueReal[i]) > 1e-9 {
          mismatches += 1;
        }
      } else {
        const csvVal = csvValToInt64(row.valueStr);
        if csvVal != pqValueInt[i] {
          mismatches += 1;
        }
      }
    }

    if mismatches > 0 {
      writeln("    ERROR: ", csvFile, ": ", mismatches, " mismatches in ", lines.size, " rows");
      totalMismatches += mismatches;
    }
  }

  if totalMismatches > 0 then
    writeln("  total numeric mismatches: ", totalMismatches);
  test.assertEqual(totalMismatches, 0);
}

// ---------------------------------------------------------------------------
// [PARQUET-PKG-1] getDatasets() and getArrType() segfault on valid Parquet
// files. Uncomment this test when the Parquet package fixes these functions.
// ---------------------------------------------------------------------------
// proc testMetricsColumnSchema(test: borrowed Test) throws {
//   const (ready, reason) = metricsInputsReady();
//   test.skipIf(!ready, reason);
//
//   const pqFiles = metricsParquetFilesInDir(pqDir);
//   for pqFile in pqFiles {
//     const pqPath = pqDir + "/" + pqFile;
//
//     const cols = getDatasets(pqPath);
//     const expectedCols = ["group", "metric_name", "time", "value_int", "value_real"];
//     for col in expectedCols do
//       test.assertTrue(cols.contains(col));
//
//     test.assertEqual(getArrType(pqPath, "group"),       ArrowTypes.stringArr);
//     test.assertEqual(getArrType(pqPath, "metric_name"), ArrowTypes.stringArr);
//     test.assertEqual(getArrType(pqPath, "time"),        ArrowTypes.real64);
//     test.assertEqual(getArrType(pqPath, "value_int"),   ArrowTypes.int64);
//     test.assertEqual(getArrType(pqPath, "value_real"),  ArrowTypes.real64);
//   }
// }

// ---------------------------------------------------------------------------
// [PARQUET-PKG-2] readColumn() does not support string-typed columns.
// Uncomment when readColumn() gains string support (or when a single-locale
// string reader is available).
// ---------------------------------------------------------------------------
// proc testMetricsStringParity(test: borrowed Test) throws {
//   const (ready, reason) = metricsInputsReady();
//   test.skipIf(!ready, reason);
//
//   const csvFiles = metricsCSVFilesInDir(csvDir);
//   const pqFiles = metricsParquetFilesInDir(pqDir);
//
//   var totalMismatches = 0;
//   for csvFile in csvFiles {
//     const baseName = csvFile[0..csvFile.size-5];
//     const pqFile = baseName + ".parquet";
//     if !pqFiles.contains(pqFile) then continue;
//
//     const csvPath = csvDir + "/" + csvFile;
//     const pqPath = pqDir + "/" + pqFile;
//     const n = getArrSize(pqPath);
//     if n == 0 then continue;
//
//     var pqGroup:      [0..<n] string;
//     var pqMetricName: [0..<n] string;
//     readColumn(filename=pqPath, colName="group",       Arr=pqGroup);
//     readColumn(filename=pqPath, colName="metric_name", Arr=pqMetricName);
//
//     const lines = readCSVDataLines(csvPath);
//     var mismatches = 0;
//     for i in 0..<lines.size {
//       const row = parseMetLine(lines[i]);
//       if row.group      != pqGroup[i]     { mismatches += 1; }
//       if row.metricName != pqMetricName[i] { mismatches += 1; }
//     }
//
//     if mismatches > 0 {
//       writeln("string mismatches in ", csvFile, ": ", mismatches);
//       totalMismatches += mismatches;
//     }
//   }
//
//   test.assertEqual(totalMismatches, 0);
// }

// NOTE: exit(0) is NOT needed here. The teardown segfault previously seen was
// caused by getDatasets()/getArrType() [PARQUET-PKG-1] corrupting memory, not
// by Arrow C++ global destructors. If [PARQUET-PKG-1] tests are re-enabled and
// cause crashes again, add exit(0) after UnitTest.main() as a temporary fix.
proc main(args: [] string) throws {
  UnitTest.main();
}
