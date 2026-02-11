# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [BincodeError, BincodeConfigError], gcsafe.}

import std/[times, strformat]
import nim_bincode
import bincode_config

func variableConfig(limit: uint64 = 65536'u64): BincodeConfig =
  standard().withVariableIntEncoding().withLimit(limit)

func fixed8Config(limit: uint64 = 65536'u64): BincodeConfig =
  standard().withFixedIntEncoding(8).withLimit(limit)

proc benchmarkSerialize(data: seq[byte], config: BincodeConfig, iterations: int): float =
  let start = cpuTime()
  for _ in 0 ..< iterations:
    discard serialize(data, config)
  let elapsed = cpuTime() - start
  elapsed / iterations.float

proc benchmarkDeserialize(encoded: seq[byte], config: BincodeConfig, iterations: int): float {.raises: [BincodeError].} =
  let start = cpuTime()
  for _ in 0 ..< iterations:
    discard deserialize(encoded, config)
  let elapsed = cpuTime() - start
  elapsed / iterations.float

proc runBenchmark(name: string, data: seq[byte], iterations: int) =
  echo "\n=== ", name, " (", data.len, " bytes, ", iterations, " iterations) ==="
  
  # Calculate appropriate limit (data size + overhead for encoding)
  let limit = (data.len.uint64 * 2).max(65536'u64)
  
  # Variable encoding
  let configVar = variableConfig(limit)
  let encodedVar = serialize(data, configVar)
  
  let serializeTimeVar = benchmarkSerialize(data, configVar, iterations)
  let deserializeTimeVar = benchmarkDeserialize(encodedVar, configVar, iterations)
  
  echo "Variable encoding:"
  echo &"  Serialize:   {serializeTimeVar * 1000.0:.4} ms/op"
  echo &"  Deserialize: {deserializeTimeVar * 1000.0:.4} ms/op"
  let throughputSerVar = (data.len.float / 1024.0 / 1024.0) / serializeTimeVar
  let throughputDesVar = (data.len.float / 1024.0 / 1024.0) / deserializeTimeVar
  echo &"  Throughput:  {throughputSerVar:.2f} MB/s (serialize), {throughputDesVar:.2f} MB/s (deserialize)"
  
  # Fixed 8-byte encoding
  let configFixed = fixed8Config(limit)
  let encodedFixed = serialize(data, configFixed)
  
  let serializeTimeFixed = benchmarkSerialize(data, configFixed, iterations)
  let deserializeTimeFixed = benchmarkDeserialize(encodedFixed, configFixed, iterations)
  
  echo "Fixed 8-byte encoding:"
  echo &"  Serialize:   {serializeTimeFixed * 1000.0:.4} ms/op"
  echo &"  Deserialize: {deserializeTimeFixed * 1000.0:.4} ms/op"
  let throughputSerFixed = (data.len.float / 1024.0 / 1024.0) / serializeTimeFixed
  let throughputDesFixed = (data.len.float / 1024.0 / 1024.0) / deserializeTimeFixed
  echo &"  Throughput:  {throughputSerFixed:.2f} MB/s (serialize), {throughputDesFixed:.2f} MB/s (deserialize)"

proc main() =
  echo "Nim Bincode Performance Benchmarks"
  echo "=================================="
  
  # Small data (1 KB)
  let smallData = newSeq[byte](1024)
  runBenchmark("Small data", smallData, 10000)
  
  # Medium data (64 KB)
  let mediumData = newSeq[byte](64 * 1024)
  runBenchmark("Medium data", mediumData, 1000)
  
  # Large data (1 MB)
  let largeData = newSeq[byte](1024 * 1024)
  runBenchmark("Large data", largeData, 100)
  
  # Very large data (10 MB)
  let veryLargeData = newSeq[byte](10 * 1024 * 1024)
  runBenchmark("Very large data", veryLargeData, 10)
  
  echo "\n=== Benchmark complete ==="

when isMainModule:
  main()
