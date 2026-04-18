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
// Override paths (for direct binary execution):
//   ./CallgraphParityTest --csvDir=/path --pqDir=/path --help
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

config const csvDir = "/tmp/csv_out";
config const pqDir  = "/tmp/pq_out";

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

proc callgraphCSVFilesInDir(dirPath: string): domain(string) {
  var files: domain(string);
  if !exists(dirPath) || !isDir(dirPath) then return files;

  for entry in listDir(dirPath) {
    const fullPath = dirPath + "/" + entry;
    if isFile(fullPath) && entry.endsWith("_callgraph.csv") {
      files += entry;
    }
  }
  return files;
}

proc callgraphParquetFilesInDir(dirPath: string): domain(string) {
  var files: domain(string);
  if !exists(dirPath) || !isDir(dirPath) then return files;

  for entry in listDir(dirPath) {
    const fullPath = dirPath + "/" + entry;
    if isFile(fullPath) && entry.endsWith("_callgraph.parquet") {
      files += entry;
    }
  }
  return files;
}

proc callgraphInputsReady(): (bool, string) {
  if !exists(csvDir) || !isDir(csvDir) {
    return (false, "CSV directory not found: " + csvDir);
  }
  if !exists(pqDir) || !isDir(pqDir) {
    return (false, "Parquet directory not found: " + pqDir);
  }
  const csvFiles = callgraphCSVFilesInDir(csvDir);
  const pqFiles = callgraphParquetFilesInDir(pqDir);
  if csvFiles.size == 0 || pqFiles.size == 0 {
    return (false, "No callgraph files found in one or both input directories");
  }
  writeln("testing callgraph parity:");
  writeln("  CSV dir:     ", csvDir);
  writeln("  PQ dir:      ", pqDir);
  writeln("  CSV files:     ", csvFiles.size);
  writeln("  Parquet files: ", pqFiles.size);
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

proc testCallgraphFileListParity(test: borrowed Test) throws {
  const (ready, reason) = callgraphInputsReady();
  test.skipIf(!ready, reason);

  const csvFiles = callgraphCSVFilesInDir(csvDir);
  const pqFiles = callgraphParquetFilesInDir(pqDir);

  writeln("  file list parity:");
  test.assertEqual(csvFiles.size, pqFiles.size);

  for csvFile in csvFiles {
    const baseName = csvFile[0..csvFile.size-5]; // remove ".csv"
    const pqFile = baseName + ".parquet";
    test.assertTrue(pqFiles.contains(pqFile));
  }
}

proc testCallgraphRowCount(test: borrowed Test) throws {
  const (ready, reason) = callgraphInputsReady();
  test.skipIf(!ready, reason);

  const csvFiles = callgraphCSVFilesInDir(csvDir);
  const pqFiles = callgraphParquetFilesInDir(pqDir);
  test.assertEqual(csvFiles.size, pqFiles.size);

  writeln("  row count parity:");
  var totalMismatches = 0;
  for csvFile in csvFiles {
    const baseName = csvFile[0..csvFile.size-5];
    const pqFile = baseName + ".parquet";
    const csvPath = csvDir + "/" + csvFile;
    const pqPath = pqDir + "/" + pqFile;

    test.assertTrue(pqFiles.contains(pqFile));

    const csvN = countCSVDataRows(csvPath);
    const pqN = getArrSize(pqPath);
    if csvN != pqN {
      writeln("    ERROR: ", csvFile, ": CSV=", csvN, " PQ=", pqN);
      totalMismatches += 1;
    }
  }
  test.assertEqual(totalMismatches, 0);
}

proc testCallgraphNumericParity(test: borrowed Test) throws {
  const (ready, reason) = callgraphInputsReady();
  test.skipIf(!ready, reason);

  const csvFiles = callgraphCSVFilesInDir(csvDir);
  const pqFiles = callgraphParquetFilesInDir(pqDir);
  test.assertEqual(csvFiles.size, pqFiles.size);

  writeln("  numeric parity:");
  var totalMismatches = 0;

  for csvFile in csvFiles {
    const baseName = csvFile[0..csvFile.size-5];
    const pqFile = baseName + ".parquet";
    const csvPath = csvDir + "/" + csvFile;
    const pqPath = pqDir + "/" + pqFile;

    test.assertTrue(pqFiles.contains(pqFile));

    const n = getArrSize(pqPath);
    if n == 0 then continue;

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
        mismatches += 1;
      }

      // Allow ±1e-9 s tolerance for CSV text round-trip (%.15dr ≈ 15 sig digits;
      // IEEE 754 double needs 17 for exact round-trip).
      if abs(row.startSec - pqStartTime[i]) > 1e-9 {
        mismatches += 1;
      }

      if row.endSec != pqEndTime[i] {
        if abs(row.endSec - pqEndTime[i]) > 1e-9 {
          mismatches += 1;
        }
      }

      if row.durationSec != pqDuration[i] {
        if abs(row.durationSec - pqDuration[i]) > 1e-9 {
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
// proc testCallgraphColumnSchema(test: borrowed Test) throws {
//   const (ready, reason) = callgraphInputsReady();
//   test.skipIf(!ready, reason);
//
//   const pqFiles = callgraphParquetFilesInDir(pqDir);
//   for pqFile in pqFiles {
//     const pqPath = pqDir + "/" + pqFile;
//
//     const cols = getDatasets(pqPath);
//     const expectedCols = ["thread", "group", "depth", "name",
//                           "start_time", "end_time", "duration"];
//     for col in expectedCols do
//       test.assertTrue(cols.contains(col));
//
//     test.assertEqual(getArrType(pqPath, "thread"),      ArrowTypes.stringArr);
//     test.assertEqual(getArrType(pqPath, "group"),       ArrowTypes.stringArr);
//     test.assertEqual(getArrType(pqPath, "depth"),       ArrowTypes.int64);
//     test.assertEqual(getArrType(pqPath, "name"),        ArrowTypes.stringArr);
//     test.assertEqual(getArrType(pqPath, "start_time"),  ArrowTypes.real64);
//     test.assertEqual(getArrType(pqPath, "end_time"),    ArrowTypes.real64);
//     test.assertEqual(getArrType(pqPath, "duration"),    ArrowTypes.real64);
//   }
// }

// ---------------------------------------------------------------------------
// [PARQUET-PKG-2] readColumn() does not support string-typed columns.
// Uncomment when readColumn() gains string support (or when a single-locale
// string reader is available).
// ---------------------------------------------------------------------------
// proc testCallgraphStringParity(test: borrowed Test) throws {
//   const (ready, reason) = callgraphInputsReady();
//   test.skipIf(!ready, reason);
//
//   const csvFiles = callgraphCSVFilesInDir(csvDir);
//   const pqFiles = callgraphParquetFilesInDir(pqDir);
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
//     var pqThread: [0..<n] string;
//     var pqGroup:  [0..<n] string;
//     var pqName:   [0..<n] string;
//     readColumn(filename=pqPath, colName="thread", Arr=pqThread);
//     readColumn(filename=pqPath, colName="group",  Arr=pqGroup);
//     readColumn(filename=pqPath, colName="name",   Arr=pqName);
//
//     const lines = readCSVDataLines(csvPath);
//     var mismatches = 0;
//     for i in 0..<lines.size {
//       const row = parseCgLine(lines[i]);
//       if row.thread != pqThread[i] { mismatches += 1; }
//       if row.group  != pqGroup[i]  { mismatches += 1; }
//       if row.name   != pqName[i]   { mismatches += 1; }
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
