// Copyright Hewlett Packard Enterprise Development LP.

// CallgraphParityTest.chpl
//
// Verifies that FastOTF2Converter's Parquet callgraph output matches CSV output.
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

import Math.inf;

private config const csvDir = "/tmp/csv_out";
private config const pqDir  = "/tmp/pq_out";
private config const callgraphBase = "Process_Master_thread_callgraph";

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

private proc csvPath: string { return csvDir + "/" + callgraphBase + ".csv"; }
private proc pqPath:  string { return pqDir  + "/" + callgraphBase + ".parquet"; }

proc filesReady(): bool {
  if !exists(csvPath) || !exists(pqPath) {
    writeln("SKIP: required files not found");
    writeln("  CSV:     ", csvPath, " ", if exists(csvPath) then "(ok)" else "(MISSING)");
    writeln("  Parquet: ", pqPath,  " ", if exists(pqPath)  then "(ok)" else "(MISSING)");
    return false;
  }
  return true;
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

// CSV format: Thread,Group,Depth,"Name",Start Time,End Time,Duration
// Name is double-quoted and may contain commas.
// First 3 and last 3 fields are fixed; middle tokens form the name.
record CgRow {
  var thread, group, name: string;
  var depth: int(64);
  var startSec, endSec, durationSec: real(64);
}

proc parseCgLine(line: string): CgRow throws {
  var parts = line.split(",");
  const lo = parts.domain.low;
  const hi = parts.domain.high;

  var row: CgRow;
  row.thread      = parts[lo];
  row.group       = parts[lo + 1];
  row.depth       = parts[lo + 2]: int(64);
  row.startSec    = parts[hi - 2]: real(64);
  row.endSec      = parts[hi - 1]: real(64);
  row.durationSec = parts[hi]:     real(64);

  row.name = "";
  for i in lo + 3 .. hi - 3 {
    if i > lo + 3 then row.name += ",";
    row.name += parts[i];
  }
  row.name = row.name.replace("\"", "");
  return row;
}

// ---------------------------------------------------------------------------
// tests
// ---------------------------------------------------------------------------

proc testCallgraphRowCount(test: borrowed Test) throws {
  if !filesReady() then return;

  const csvN = countCSVDataRows(csvPath);
  const pqN  = getArrSize(pqPath);
  writeln("callgraph rows: CSV=", csvN, " Parquet=", pqN);
  test.assertEqual(csvN, pqN);
}

proc testCallgraphNumericParity(test: borrowed Test) throws {
  if !filesReady() then return;
  const n = getArrSize(pqPath);
  if n == 0 { writeln("SKIP: no data rows"); return; }

  var pqDepth:      [0..<n] int(64);
  var pqStartTime:  [0..<n] real(64);
  var pqEndTime:    [0..<n] real(64);
  var pqDuration:   [0..<n] real(64);
  readColumn(filename=pqPath, colName="depth",       Arr=pqDepth);
  readColumn(filename=pqPath, colName="start_time",  Arr=pqStartTime);
  readColumn(filename=pqPath, colName="end_time",    Arr=pqEndTime);
  readColumn(filename=pqPath, colName="duration",    Arr=pqDuration);

  const lines = readCSVDataLines(csvPath);
  var mismatches = 0;

  for i in 0..<lines.size {
    const row = parseCgLine(lines[i]);

    if row.depth != pqDepth[i] {
      writeln("row ", i, " depth: CSV=", row.depth, " PQ=", pqDepth[i]);
      mismatches += 1;
    }

    // Allow ±1e-9 s tolerance for CSV text round-trip (%.15dr ≈ 15 sig digits;
    // IEEE 754 double needs 17 for exact round-trip).
    if abs(row.startSec - pqStartTime[i]) > 1e-9 {
      writeln("row ", i, " start_time: CSV=", row.startSec, " PQ=", pqStartTime[i]);
      mismatches += 1;
    }

    if row.endSec != pqEndTime[i] {
      if abs(row.endSec - pqEndTime[i]) > 1e-9 {
        writeln("row ", i, " end_time: CSV=", row.endSec, " PQ=", pqEndTime[i]);
        mismatches += 1;
      }
    }

    if row.durationSec != pqDuration[i] {
      if abs(row.durationSec - pqDuration[i]) > 1e-9 {
        writeln("row ", i, " duration: CSV=", row.durationSec, " PQ=", pqDuration[i]);
        mismatches += 1;
      }
    }
  }

  writeln("numeric parity: ", lines.size, " rows, ", mismatches, " mismatches");
  test.assertEqual(mismatches, 0);
}

// ---------------------------------------------------------------------------
// [PARQUET-PKG-1] getDatasets() and getArrType() segfault on valid Parquet
// files. Uncomment this test when the Parquet package fixes these functions.
// ---------------------------------------------------------------------------
// proc testCallgraphColumnSchema(test: borrowed Test) throws {
//   if !exists(pqPath) { writeln("SKIP: ", pqPath, " not found"); return; }
//
//   const cols = getDatasets(pqPath);
//   const expectedCols = ["thread", "group", "depth", "name",
//                         "start_time", "end_time", "duration"];
//   for col in expectedCols do
//     test.assertTrue(cols.contains(col));
//
//   test.assertEqual(getArrType(pqPath, "thread"),      ArrowTypes.stringArr);
//   test.assertEqual(getArrType(pqPath, "group"),       ArrowTypes.stringArr);
//   test.assertEqual(getArrType(pqPath, "depth"),       ArrowTypes.int64);
//   test.assertEqual(getArrType(pqPath, "name"),        ArrowTypes.stringArr);
//   test.assertEqual(getArrType(pqPath, "start_time"),  ArrowTypes.real64);
//   test.assertEqual(getArrType(pqPath, "end_time"),    ArrowTypes.real64);
//   test.assertEqual(getArrType(pqPath, "duration"),    ArrowTypes.real64);
// }

// ---------------------------------------------------------------------------
// [PARQUET-PKG-2] readColumn() does not support string-typed columns.
// Uncomment when readColumn() gains string support (or when a single-locale
// string reader is available).
// ---------------------------------------------------------------------------
// proc testCallgraphStringParity(test: borrowed Test) throws {
//   if !filesReady() then return;
//   const n = getArrSize(pqPath);
//   if n == 0 { writeln("SKIP: no data rows"); return; }
//
//   var pqThread: [0..<n] string;
//   var pqGroup:  [0..<n] string;
//   var pqName:   [0..<n] string;
//   readColumn(filename=pqPath, colName="thread", Arr=pqThread);
//   readColumn(filename=pqPath, colName="group",  Arr=pqGroup);
//   readColumn(filename=pqPath, colName="name",   Arr=pqName);
//
//   const lines = readCSVDataLines(csvPath);
//   var mismatches = 0;
//
//   for i in 0..<lines.size {
//     const row = parseCgLine(lines[i]);
//     if row.thread != pqThread[i] { mismatches += 1; }
//     if row.group  != pqGroup[i]  { mismatches += 1; }
//     if row.name   != pqName[i]   { mismatches += 1; }
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
