// Copyright Hewlett Packard Enterprise Development LP.

// StrategyParquetParityTest.chpl
//
// Verifies parity between the baseline location strategy and the
// location_group strategy using Parquet outputs.
//
// Prerequisites:
//   # Baseline (old) output
//   mason run --release -- ../../sample-traces/simple-mi300-example-run/traces.otf2 \
//     --partitionStrategy=location --format=PARQUET --outputDir=/tmp/old_pq_out
//
//   # New output
//   mason run --release -- ../../sample-traces/simple-mi300-example-run/traces.otf2 \
//     --partitionStrategy=location_group --format=PARQUET --outputDir=/tmp/new_pq_out
//
// Run:
//   mason test --show
//
// Override paths (for direct binary execution):
//   ./StrategyParquetParityTest --oldDir=/path/to/old --newDir=/path/to/new --help

use UnitTest;
use Parquet;
use FileSystem;
use Map;

config const oldDir = "/tmp/old_pq_out";
config const newDir = "/tmp/new_pq_out";

proc parquetFilesInDir(dirPath: string): domain(string) {
  var files: domain(string);
  if !exists(dirPath) || !isDir(dirPath) then return files;

  for entry in listDir(dirPath) {
    const fullPath = dirPath + "/" + entry;
    if isFile(fullPath) && entry.endsWith(".parquet") {
      files += entry;
    }
  }
  writeln("found ", files.size, " parquet files in ", dirPath);
  return files;
}

proc strategyInputsReady(): (bool, string) {
  if !exists(oldDir) || !isDir(oldDir) {
    return (false, "Old parquet directory not found: " + oldDir);
  }
  if !exists(newDir) || !isDir(newDir) {
    return (false, "New parquet directory not found: " + newDir);
  }

  const oldFiles = parquetFilesInDir(oldDir);
  const newFiles = parquetFilesInDir(newDir);
  if oldFiles.size == 0 || newFiles.size == 0 {
    return (false, "No parquet files found in one or both strategy output directories");
  }

  return (true, "");
}

proc fileListsMatch(oldFiles: domain(string), newFiles: domain(string)): bool {
  var ok = true;

  if oldFiles.size != newFiles.size {
    writeln("file count mismatch old/new: ", oldFiles.size, "/", newFiles.size);
    ok = false;
  }

  for f in oldFiles {
    if !newFiles.contains(f) {
      writeln("missing in new: ", f);
      ok = false;
    }
  }

  for f in newFiles {
    if !oldFiles.contains(f) {
      writeln("missing in old: ", f);
      ok = false;
    }
  }

  return ok;
}

proc compareCallgraphNumeric(oldPath: string, newPath: string): int throws {
  const n = getArrSize(oldPath);

  var oldDepth: [0..<n] int(64);
  var newDepth: [0..<n] int(64);
  var oldStart: [0..<n] real(64);
  var newStart: [0..<n] real(64);
  var oldEnd: [0..<n] real(64);
  var newEnd: [0..<n] real(64);
  var oldDuration: [0..<n] real(64);
  var newDuration: [0..<n] real(64);

  readColumn(filename=oldPath, colName="depth", Arr=oldDepth);
  readColumn(filename=newPath, colName="depth", Arr=newDepth);
  readColumn(filename=oldPath, colName="start_time", Arr=oldStart);
  readColumn(filename=newPath, colName="start_time", Arr=newStart);
  readColumn(filename=oldPath, colName="end_time", Arr=oldEnd);
  readColumn(filename=newPath, colName="end_time", Arr=newEnd);
  readColumn(filename=oldPath, colName="duration", Arr=oldDuration);
  readColumn(filename=newPath, colName="duration", Arr=newDuration);

  // Order-insensitive multiset comparison of numeric tuples.
  var oldCounts: map(string, int);
  var newCounts: map(string, int);

  for i in 0..<n {
    const key = oldDepth[i]:string + "|" + oldStart[i]:string + "|" + oldEnd[i]:string + "|" + oldDuration[i]:string;
    oldCounts[key] += 1;
  }

  for i in 0..<n {
    const key = newDepth[i]:string + "|" + newStart[i]:string + "|" + newEnd[i]:string + "|" + newDuration[i]:string;
    newCounts[key] += 1;
  }

  var mismatches = 0;
  for key in oldCounts.keys() {
    if newCounts[key] != oldCounts[key] then mismatches += 1;
  }
  for key in newCounts.keys() {
    if oldCounts[key] != newCounts[key] then mismatches += 1;
  }
  return mismatches;
}

proc compareMetricsNumeric(oldPath: string, newPath: string): int throws {
  const n = getArrSize(oldPath);

  var oldTime: [0..<n] real(64);
  var newTime: [0..<n] real(64);
  var oldValueInt: [0..<n] int(64);
  var newValueInt: [0..<n] int(64);
  var oldValueReal: [0..<n] real(64);
  var newValueReal: [0..<n] real(64);

  readColumn(filename=oldPath, colName="time", Arr=oldTime);
  readColumn(filename=newPath, colName="time", Arr=newTime);
  readColumn(filename=oldPath, colName="value_int", Arr=oldValueInt);
  readColumn(filename=newPath, colName="value_int", Arr=newValueInt);
  readColumn(filename=oldPath, colName="value_real", Arr=oldValueReal);
  readColumn(filename=newPath, colName="value_real", Arr=newValueReal);

  // Order-insensitive multiset comparison of numeric tuples.
  var oldCounts: map(string, int);
  var newCounts: map(string, int);

  for i in 0..<n {
    const key = oldTime[i]:string + "|" + oldValueInt[i]:string + "|" + oldValueReal[i]:string;
    oldCounts[key] += 1;
  }

  for i in 0..<n {
    const key = newTime[i]:string + "|" + newValueInt[i]:string + "|" + newValueReal[i]:string;
    newCounts[key] += 1;
  }

  var mismatches = 0;
  for key in oldCounts.keys() {
    if newCounts[key] != oldCounts[key] then mismatches += 1;
  }
  for key in newCounts.keys() {
    if oldCounts[key] != newCounts[key] then mismatches += 1;
  }
  return mismatches;
}

proc testParquetFileListParityOldVsNew(test: borrowed Test) throws {
  const (ready, reason) = strategyInputsReady();
  test.skipIf(!ready, reason);

  const oldFiles = parquetFilesInDir(oldDir);
  const newFiles = parquetFilesInDir(newDir);

  writeln("parquet file count old/new: ", oldFiles.size, "/", newFiles.size);
  test.assertTrue(fileListsMatch(oldFiles, newFiles));
}

proc testParquetRowCountParityOldVsNew(test: borrowed Test) throws {
  const (ready, reason) = strategyInputsReady();
  test.skipIf(!ready, reason);

  const oldFiles = parquetFilesInDir(oldDir);
  const newFiles = parquetFilesInDir(newDir);
  test.assertTrue(fileListsMatch(oldFiles, newFiles));

  for fileName in oldFiles {
    const oldPath = oldDir + "/" + fileName;
    const newPath = newDir + "/" + fileName;
    const oldN = getArrSize(oldPath);
    const newN = getArrSize(newPath);
    if oldN != newN {
      writeln("row count mismatch for ", fileName, ": ", oldN, " vs ", newN);
    }
    test.assertEqual(oldN, newN);
  }
}

proc testParquetNumericParityOldVsNew(test: borrowed Test) throws {
  const (ready, reason) = strategyInputsReady();
  test.skipIf(!ready, reason);

  const oldFiles = parquetFilesInDir(oldDir);
  const newFiles = parquetFilesInDir(newDir);
  test.assertTrue(fileListsMatch(oldFiles, newFiles));

  var totalMismatches = 0;
  for fileName in oldFiles {
    const oldPath = oldDir + "/" + fileName;
    const newPath = newDir + "/" + fileName;
    const oldN = getArrSize(oldPath);
    const newN = getArrSize(newPath);
    if oldN != newN {
      // Already asserted in row-count test, but guard here for isolation.
      totalMismatches += 1;
      continue;
    }

    var mismatches = 0;
    if fileName.endsWith("_callgraph.parquet") {
      mismatches = compareCallgraphNumeric(oldPath, newPath);
    } else if fileName.endsWith("_metrics.parquet") {
      mismatches = compareMetricsNumeric(oldPath, newPath);
    } else {
      // Unknown parquet type in output set should fail explicitly.
      writeln("unknown parquet output file pattern: ", fileName);
      mismatches = 1;
    }

    if mismatches != 0 {
      writeln("numeric mismatches for ", fileName, ": ", mismatches);
    }
    totalMismatches += mismatches;
  }

  writeln("total numeric mismatches across all parquet files: ", totalMismatches);
  test.assertEqual(totalMismatches, 0);
}

proc main(args: [] string) throws {
  // Keep a use-site for `args` to satisfy lint while preserving the
  // standard UnitTest entrypoint signature.
  if args.size < 0 then writeln(args.size);
  UnitTest.main();
}
