# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import faststreams  # Uses: memoryOutput, getOutput
import std/[times, strformat, strutils, osproc, algorithm]
import nim_bincode
import bincode_config

type
  BenchmarkResult = object
    name: string
    dataSize: int
    encoding: string
    language: string  # "Nim" or "Rust"
    serializeTimeMs: float
    deserializeTimeMs: float
    serializeThroughputMBs: float
    deserializeThroughputMBs: float

# Helper function to serialize using streaming API and return seq[byte]
proc serializeToSeq[E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64](
    data: openArray[byte], config: BincodeConfig[E, O, L], limit: uint64 = L
): seq[byte] {.raises: [BincodeError, IOError].} =
  var stream = memoryOutput()
  serialize(stream, data, config, limit)
  stream.getOutput()

# Convenience overload with default config
proc serializeToSeq(data: openArray[byte], config: Fixed8LEConfig = standard(), limit: uint64 = BINCODE_SIZE_LIMIT): seq[byte] {.raises: [BincodeError, IOError].} =
  serializeToSeq[FixedEncoding[8], LittleEndian, BINCODE_SIZE_LIMIT](data, config, limit)

func variableConfig(limit: uint64 = 65536'u64): VariableLEConfig =
  standard().withVariableIntEncoding()

func fixed8Config(limit: uint64 = 65536'u64): Fixed8LEConfig =
  standard()

proc benchmarkSerialize[E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64](
    data: seq[byte], config: BincodeConfig[E, O, L], limit: uint64, iterations: int
): float {.raises: [BincodeError, IOError].} =
  let start = cpuTime()
  for _ in 0 ..< iterations:
    discard serializeToSeq(data, config, limit)
  let elapsed = cpuTime() - start
  elapsed / iterations.float

proc benchmarkDeserialize[E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64](
    encoded: seq[byte], config: BincodeConfig[E, O, L], limit: uint64, iterations: int
): float {.raises: [BincodeError].} =
  let start = cpuTime()
  for _ in 0 ..< iterations:
    discard deserialize(encoded, config, limit)
  let elapsed = cpuTime() - start
  elapsed / iterations.float

proc runBenchmark(name: string, data: seq[byte], iterations: int, results: var seq[BenchmarkResult]) {.raises: [BincodeError, IOError].} =
  echo "\n=== ", name, " (", data.len, " bytes, ", iterations, " iterations) ==="
  
  # Calculate appropriate limit (data size + overhead for encoding)
  let limit = (data.len.uint64 * 2).max(65536'u64)
  
  # Variable encoding
  let configVar = variableConfig(limit)
  let encodedVar = serializeToSeq(data, configVar, limit)
  
  let serializeTimeVar = benchmarkSerialize(data, configVar, limit, iterations)
  let deserializeTimeVar = benchmarkDeserialize(encodedVar, configVar, limit, iterations)
  
  echo "Variable encoding:"
  echo &"  Serialize:   {serializeTimeVar * 1000.0:.4} ms/op"
  echo &"  Deserialize: {deserializeTimeVar * 1000.0:.4} ms/op"
  let throughputSerVar = (data.len.float / 1024.0 / 1024.0) / serializeTimeVar
  let throughputDesVar = (data.len.float / 1024.0 / 1024.0) / deserializeTimeVar
  echo &"  Throughput:  {throughputSerVar:.2f} MB/s (serialize), {throughputDesVar:.2f} MB/s (deserialize)"
  
  results.add(BenchmarkResult(
    name: name,
    dataSize: data.len,
    encoding: "Variable",
    language: "Nim",
    serializeTimeMs: serializeTimeVar * 1000.0,
    deserializeTimeMs: deserializeTimeVar * 1000.0,
    serializeThroughputMBs: throughputSerVar,
    deserializeThroughputMBs: throughputDesVar
  ))
  
  # Fixed 8-byte encoding
  let configFixed = fixed8Config(limit)
  let encodedFixed = serializeToSeq(data, configFixed, limit)
  
  let serializeTimeFixed = benchmarkSerialize(data, configFixed, limit, iterations)
  let deserializeTimeFixed = benchmarkDeserialize(encodedFixed, configFixed, limit, iterations)
  
  echo "Fixed 8-byte encoding:"
  echo &"  Serialize:   {serializeTimeFixed * 1000.0:.4} ms/op"
  echo &"  Deserialize: {deserializeTimeFixed * 1000.0:.4} ms/op"
  let throughputSerFixed = (data.len.float / 1024.0 / 1024.0) / serializeTimeFixed
  let throughputDesFixed = (data.len.float / 1024.0 / 1024.0) / deserializeTimeFixed
  echo &"  Throughput:  {throughputSerFixed:.2f} MB/s (serialize), {throughputDesFixed:.2f} MB/s (deserialize)"
  
  results.add(BenchmarkResult(
    name: name,
    dataSize: data.len,
    encoding: "Fixed8",
    language: "Nim",
    serializeTimeMs: serializeTimeFixed * 1000.0,
    deserializeTimeMs: deserializeTimeFixed * 1000.0,
    serializeThroughputMBs: throughputSerFixed,
    deserializeThroughputMBs: throughputDesFixed
  ))

proc formatSize(size: int): string =
  if size < 1024:
    &"{size} B"
  elif size < 1024 * 1024:
    &"{size.float / 1024.0:.1f} KB"
  else:
    &"{size.float / 1024.0 / 1024.0:.1f} MB"

proc runRustBenchmark(): seq[BenchmarkResult] {.raises: [OSError, IOError].} =
  ## Run Rust benchmarks and parse results
  var rustResults: seq[BenchmarkResult] = @[]
  
  echo "\n=== Running Rust benchmarks ==="
  let (output, exitCode) = execCmdEx("cargo test --release --test benchmark -- --nocapture 2>&1")
  
  if exitCode != 0:
    echo "Warning: Rust benchmark failed or not available"
    echo output
    return rustResults
  
  # Parse Rust benchmark output
  var currentName = ""
  var currentSize = 0
  var currentEncoding = ""
  var serializeTime: float = 0.0
  var deserializeTime: float = 0.0
  
  for line in output.splitLines():
    # Match benchmark header: "=== Small data (1024 bytes, 10000 iterations) ==="
    if line.contains("===") and line.contains("bytes"):
      let parts = line.split("(")
      if parts.len >= 2:
        currentName = parts[0].replace("===").strip()
        let sizePart = parts[1].split(" ")[0]
        try:
          currentSize = parseInt(sizePart)
        except:
          discard
    
    # Match encoding type
    if line.contains("Variable encoding:") or line.contains("variable encoding:"):
      currentEncoding = "Variable"
    elif line.contains("Fixed 8-byte encoding:") or line.contains("Fixed 8-byte"):
      currentEncoding = "Fixed8"
    
    # Match serialize time: "  Serialize:   0.0039 ms/op"
    if line.contains("Serialize:") and line.contains("ms/op"):
      let parts = line.split(":")
      if parts.len >= 2:
        let timePart = parts[1].strip().split(" ")[0]
        try:
          serializeTime = parseFloat(timePart)
        except:
          discard
    
    # Match deserialize time: "  Deserialize: 0.0022 ms/op"
    if line.contains("Deserialize:") and line.contains("ms/op"):
      let parts = line.split(":")
      if parts.len >= 2:
        let timePart = parts[1].strip().split(" ")[0]
        try:
          deserializeTime = parseFloat(timePart)
          # When we have both times, calculate throughput and add result
          if currentSize > 0 and currentEncoding != "":
            let sizeMB = currentSize.float / 1024.0 / 1024.0
            let serThroughput = sizeMB / (serializeTime / 1000.0)
            let desThroughput = sizeMB / (deserializeTime / 1000.0)
            
            rustResults.add(BenchmarkResult(
              name: currentName,
              dataSize: currentSize,
              encoding: currentEncoding,
              language: "Rust",
              serializeTimeMs: serializeTime,
              deserializeTimeMs: deserializeTime,
              serializeThroughputMBs: serThroughput,
              deserializeThroughputMBs: desThroughput
            ))
            # Reset for next encoding
            currentEncoding = ""
        except:
          discard
  
  rustResults

proc printSummaryTable(nimResults: seq[BenchmarkResult], rustResults: seq[BenchmarkResult]) =
  const separator = "=".repeat(70)
  const headerSeparator = "-".repeat(70)
  
  echo "\n", separator
  echo "COMPARISON TABLE: Nim vs Rust"
  echo separator
  echo "Data Size    Encoding   Language   Ser MB/s      Des MB/s"
  echo headerSeparator
  
  # Group results by data size and encoding
  var grouped: seq[(int, string, BenchmarkResult, BenchmarkResult)] = @[]
  
  for nimResult in nimResults:
    for rustResult in rustResults:
      if nimResult.dataSize == rustResult.dataSize and nimResult.encoding == rustResult.encoding:
        grouped.add((nimResult.dataSize, nimResult.encoding, nimResult, rustResult))
        break
  
  # Sort by data size, then encoding
  grouped.sort do (a, b: (int, string, BenchmarkResult, BenchmarkResult)) -> int:
    if a[0] != b[0]:
      result = a[0] - b[0]
    else:
      result = cmp(a[1], b[1])
  
  for (size, encoding, nim, rust) in grouped:
    let sizeStr = formatSize(size)
    
    # Print Nim row
    const nimLang = "Nim"
    echo &"{sizeStr:<12} {encoding:<10} {nimLang:<11} {nim.serializeThroughputMBs:>10.2f}      {nim.deserializeThroughputMBs:>10.2f}"
    # Print Rust row
    const rustLang = "Rust"
    const empty = ""
    echo &"{empty:<12} {empty:<10} {rustLang:<11} {rust.serializeThroughputMBs:>10.2f}      {rust.deserializeThroughputMBs:>10.2f}"
    echo headerSeparator
  
  echo separator

proc main() {.raises: [BincodeError, IOError, OSError].} =
  echo "Nim Bincode Performance Benchmarks"
  echo "=================================="
  
  var nimResults: seq[BenchmarkResult] = @[]
  
  # Small data (1 KB)
  let smallData = newSeq[byte](1024)
  runBenchmark("Small data", smallData, 10000, nimResults)
  
  # Medium data (64 KB)
  let mediumData = newSeq[byte](64 * 1024)
  runBenchmark("Medium data", mediumData, 1000, nimResults)
  
  # Large data (1 MB)
  let largeData = newSeq[byte](1024 * 1024)
  runBenchmark("Large data", largeData, 100, nimResults)
  
  # Very large data (10 MB)
  let veryLargeData = newSeq[byte](10 * 1024 * 1024)
  runBenchmark("Very large data", veryLargeData, 10, nimResults)
  
  # Run Rust benchmarks
  let rustResults = runRustBenchmark()
  
  # Print comparison table
  printSummaryTable(nimResults, rustResults)
  echo "\n=== Benchmark complete ==="

when isMainModule:
  main()

{.pop.}
