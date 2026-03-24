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
// Override paths:
//   mason test --show -- --csvDir=/path --pqDir=/path
//
// Known Parquet package issues (search these tags to find/remove workarounds):
//   [PARQUET-PKG-1] getDatasets() / getArrType() segfault on valid files
//   [PARQUET-PKG-2] readColumn() does not support string-typed columns

use UnitTest;
use Parquet;
use FileSystem;
use IO;
use List;

private config const csvDir = "/tmp/csv_out";
private config const pqDir  = "/tmp/pq_out";
private config const metricsBase = "Process_metrics";

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

private proc csvPath: string { return csvDir + "/" + metricsBase + ".csv"; }
private proc pqPath:  string { return pqDir  + "/" + metricsBase + ".parquet"; }

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

inline proc toNs(sec: real(64)): int(64) {
  return (sec * 1_000_000_000.0): int(64);
}

// CSV values may be int ("42") or float ("42.5"); Parquet stores all as int64.
// Parsing as real then casting handles both representations.
proc csvValToInt64(s: string): int(64) {
  return s: real(64) : int(64);
}

// ---------------------------------------------------------------------------
// tests
// ---------------------------------------------------------------------------

// When the trace has no metric data the CSV file has only the header row
// and no Parquet file is created.  Verify this invariant.
proc testMetricsRowCount(test: borrowed Test) throws {
  if !exists(csvPath) {
    writeln("SKIP: CSV not found: ", csvPath);
    return;
  }

  const csvN = countCSVDataRows(csvPath);

  if !exists(pqPath) {
    // Parquet file absent -> CSV must also be empty.
    writeln("metrics rows: CSV=", csvN, " Parquet file absent");
    test.assertEqual(csvN, 0);
    return;
  }

  const pqN = getArrSize(pqPath);
  writeln("metrics rows: CSV=", csvN, " Parquet=", pqN);
  test.assertEqual(csvN, pqN);
}

proc testMetricsNumericParity(test: borrowed Test) throws {
  if !exists(csvPath) { writeln("SKIP: CSV not found"); return; }
  if !exists(pqPath)  { writeln("SKIP: Parquet file absent (no metric data)"); return; }

  const n = getArrSize(pqPath);
  if n == 0 { writeln("SKIP: no data rows"); return; }

  var pqTimeNs: [0..<n] int(64);
  var pqValue:  [0..<n] int(64);
  readColumn(filename=pqPath, colName="time_ns",   Arr=pqTimeNs);
  readColumn(filename=pqPath, colName="value_i64", Arr=pqValue);

  const lines = readCSVDataLines(csvPath);
  var mismatches = 0;

  for i in 0..<lines.size {
    const row = parseMetLine(lines[i]);

    // ±1 ns tolerance for seconds->nanoseconds float-to-int conversion
    if abs(toNs(row.timeSec) - pqTimeNs[i]) > 1 {
      writeln("row ", i, " time_ns: CSV=", toNs(row.timeSec), " PQ=", pqTimeNs[i]);
      mismatches += 1;
    }

    const csvVal = csvValToInt64(row.valueStr);
    if csvVal != pqValue[i] {
      writeln("row ", i, " value: CSV=", csvVal, " PQ=", pqValue[i]);
      mismatches += 1;
    }
  }

  writeln("numeric parity: ", lines.size, " rows, ", mismatches, " mismatches");
  test.assertEqual(mismatches, 0);
}

// ---------------------------------------------------------------------------
// [PARQUET-PKG-1] getDatasets() and getArrType() segfault on valid Parquet
// files. Uncomment this test when the Parquet package fixes these functions.
// ---------------------------------------------------------------------------
// proc testMetricsColumnSchema(test: borrowed Test) throws {
//   if !exists(pqPath) {
//     writeln("SKIP: Parquet file absent (no metric data): ", pqPath);
//     return;
//   }
//
//   const cols = getDatasets(pqPath);
//   const expectedCols = ["group", "metric_name", "time_ns", "value_i64"];
//   for col in expectedCols do
//     test.assertTrue(cols.contains(col));
//
//   test.assertEqual(getArrType(pqPath, "group"),       ArrowTypes.stringArr);
//   test.assertEqual(getArrType(pqPath, "metric_name"), ArrowTypes.stringArr);
//   test.assertEqual(getArrType(pqPath, "time_ns"),     ArrowTypes.int64);
//   test.assertEqual(getArrType(pqPath, "value_i64"),   ArrowTypes.int64);
// }

// ---------------------------------------------------------------------------
// [PARQUET-PKG-2] readColumn() does not support string-typed columns.
// Uncomment when readColumn() gains string support (or when a single-locale
// string reader is available).
// ---------------------------------------------------------------------------
// proc testMetricsStringParity(test: borrowed Test) throws {
//   if !exists(csvPath) { writeln("SKIP: CSV not found"); return; }
//   if !exists(pqPath)  { writeln("SKIP: Parquet file absent (no metric data)"); return; }
//
//   const n = getArrSize(pqPath);
//   if n == 0 { writeln("SKIP: no data rows"); return; }
//
//   var pqGroup:      [0..<n] string;
//   var pqMetricName: [0..<n] string;
//   readColumn(filename=pqPath, colName="group",       Arr=pqGroup);
//   readColumn(filename=pqPath, colName="metric_name", Arr=pqMetricName);
//
//   const lines = readCSVDataLines(csvPath);
//   var mismatches = 0;
//
//   for i in 0..<lines.size {
//     const row = parseMetLine(lines[i]);
//     if row.group      != pqGroup[i]      { mismatches += 1; }
//     if row.metricName != pqMetricName[i]  { mismatches += 1; }
//   }
//
//   writeln("string parity: ", lines.size, " rows, ", mismatches, " mismatches");
//   test.assertEqual(mismatches, 0);
// }

// NOTE: exit(0) is NOT needed here. The teardown segfault previously seen was
// caused by getDatasets()/getArrType() [PARQUET-PKG-1] corrupting memory, not
// by Arrow C++ global destructors. If [PARQUET-PKG-1] tests are re-enabled and
// cause crashes again, add exit(0) after UnitTest.main() as a temporary fix.
proc main(args: [] string) throws {
  UnitTest.main();
}
