# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import faststreams # Uses: memoryOutput, fileOutput, getOutput, close
import unittest2
import std/os
import bincode

const TestDataDir = "target/test_data"

# Compile-time defines to control which test suites run
when defined(testVariable):
  const RUN_VARIABLE_TESTS = true
elif defined(testFixed8):
  const RUN_VARIABLE_TESTS = false
else:
  # Default: run all tests if no specific define is set
  const RUN_VARIABLE_TESTS = true

when defined(testFixed8):
  const RUN_FIXED8_TESTS = true
elif defined(testVariable):
  const RUN_FIXED8_TESTS = false
else:
  # Default: run all tests if no specific define is set
  const RUN_FIXED8_TESTS = true

# ============================================================================
# Test Case Definitions
# ============================================================================

# Test files for variable encoding deserialization
const DeserializeTestFilesVariable {.used.}: array[12, string] = [
  "nim_var_001.bin", "nim_var_002.bin", "nim_var_003.bin", "nim_var_004.bin",
  "nim_var_005.bin", "nim_var_006.bin", "nim_var_007.bin", "nim_var_008.bin",
  "nim_var_009.bin", "nim_var_010.bin", "nim_var_011.bin", "nim_var_012.bin",
]

# Test files for fixed 8-byte encoding deserialization
const DeserializeTestFilesFixed8 {.used.}: array[12, string] = [
  "nim_fixed8_001.bin", "nim_fixed8_002.bin", "nim_fixed8_003.bin",
  "nim_fixed8_004.bin", "nim_fixed8_005.bin", "nim_fixed8_006.bin",
  "nim_fixed8_007.bin", "nim_fixed8_008.bin", "nim_fixed8_009.bin",
  "nim_fixed8_010.bin", "nim_fixed8_011.bin", "nim_fixed8_012.bin",
]

# Get expected data for deserialization tests
func getExpectedData(): seq[seq[byte]] =
  var data100 = newSeq[byte](100)
  for i in 0 ..< data100.len:
    data100[i] = byte(1)

  return
    @[
      @[byte(1), 2, 3, 4, 5],
      @[],
      @[byte(0), 255, 128, 64],
      cast[seq[byte]]("Hello, World!"),
      @[byte(42)],
      cast[seq[byte]]("Test with émojis 🚀"),
      data100,
      newSeq[byte](20 * 1024), # 20kB
      newSeq[byte](250), # Just below 251 threshold (uses single byte)
      newSeq[byte](251), # Just at 251 threshold (uses 0xfb + u16 LE)
      newSeq[byte](65535),
        # Just below 2^16 threshold (uses 0xfb + u16 LE: 3 + 65535 = 65538)
      newSeq[byte](65536),
        # Just at 2^16 threshold (uses 0xfc + u32 LE: 5 + 65536 = 65541)
    ]

func maxPayloadLenForFixedInt(fixedIntBytes: int): uint64 {.raises: [].} =
  ## Largest `seq[byte]` length representable with a fixed `fixedIntBytes` length prefix.
  case fixedIntBytes
  of 1: uint8.high.uint64
  of 2: uint16.high.uint64
  of 4: uint32.high.uint64
  of 8: uint64.high
  else: uint64.high

func expectedPayloadsForNimFixedRoundtrip(
    fixedIntBytes: int
): seq[seq[byte]] {.raises: [].} =
  ## Subset of `getExpectedData()` that fits the fixed length prefix (Rust uses u64 only).
  let cap = maxPayloadLenForFixedInt(fixedIntBytes)
  result = @[]
  for p in getExpectedData():
    if p.len.uint64 <= cap:
      result.add p

# ============================================================================
# Helper Functions
# ============================================================================

proc serializeToFile(
    data: openArray[byte], filename: string, config: BincodeConfig = standard()
) {.raises: [BincodeError, IOError, OSError].} =
  ## Serialize data and write directly to file for Rust to read (no intermediate allocation)
  createDir(TestDataDir)
  let filePath = TestDataDir / filename
  var output = fileOutput(filePath, fmWrite)
  encode(output, data, config)
  output.close()

proc deserializeFromFile(
    filename: string, config: BincodeConfig = standard()
): seq[byte] {.raises: [BincodeError, IOError, OSError].} =
  ## Read file and deserialize data that was serialized by Rust
  let filePath = TestDataDir / filename
  let serialized = cast[seq[byte]](readFile(filePath))
  return decode(serialized, config)

# ============================================================================
# Variable-Length Encoding (LEB128) Cross-Verification Tests
# ============================================================================

when RUN_VARIABLE_TESTS:
  suite "Rust serialize → Nim deserialize (variable encoding)":
    test "deserialize rust_var_001.bin":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_001.bin", config)
      check deserialized == @[byte(1), 2, 3, 4, 5]

    test "deserialize rust_var_002.bin (empty)":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_002.bin", config)
      check deserialized.len == 0

    test "deserialize rust_var_003.bin":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_003.bin", config)
      check deserialized == @[byte(0), 255, 128, 64]

    test "deserialize rust_var_004.bin (Hello, World!)":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_004.bin", config)
      let text = cast[string](deserialized)
      check text == "Hello, World!"

    test "deserialize rust_var_005.bin":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_005.bin", config)
      check deserialized == @[byte(42)]

    test "deserialize rust_var_006.bin (unicode)":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_006.bin", config)
      let text = cast[string](deserialized)
      check text == "Test with émojis 🚀"

    test "deserialize rust_var_007.bin (100 bytes)":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_007.bin", config)
      check deserialized.len == 100
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(1)

    test "deserialize rust_var_008.bin (20kB)":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_008.bin", config)
      check deserialized.len == 20 * 1024
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

    test "deserialize rust_var_009.bin (just below 251 threshold, uses single byte)":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_009.bin", config)
      check deserialized.len == 250
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

    test "deserialize rust_var_010.bin (just at threshold, uses 0xfb + u16 LE)":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_010.bin", config)
      check deserialized.len == 251
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

    test "deserialize rust_var_011.bin (just below 2^16 threshold, uses 0xfb + u16)":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_011.bin", config)
      check deserialized.len == 65535
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

    test "deserialize rust_var_012.bin (just at 2^16 threshold, uses 0xfc + u32)":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_012.bin", config)
      check deserialized.len == 65536
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

when RUN_VARIABLE_TESTS:
  suite "Nim serialize → Rust deserialize (variable encoding)":
    test "serialize all test cases":
      let expectedData = getExpectedData()
      let config = standard().withVariableIntEncoding().withLimit(4294967305'u64)
      for i, filename in DeserializeTestFilesVariable:
        serializeToFile(expectedData[i], filename, config)

when RUN_VARIABLE_TESTS:
  suite "Byte-for-byte compatibility (variable encoding)":
    test "verify Rust variable-length roundtrip matches data":
      let testCases = getExpectedData()[0 .. 6] # avoid huge allocations
      let config = standard().withVariableIntEncoding()

      for original in testCases:
        let nimSerialized = encode(original, config)
        let nimDeserialized = decode(nimSerialized, config)

        # Roundtrip must preserve data
        check nimDeserialized == original

    test "verify marker byte prefixes (0xfb, 0xfc, 0xfd)":
      let config = standard().withVariableIntEncoding().withLimit(4294967305'u64)

      # Test single byte encoding (< 251): length 250 should be single byte
      let data250 = newSeq[byte](250)
      let serialized250 = encode(data250, config)
      check serialized250[0] == 250'u8 # No marker, just the value itself
      check serialized250.len == 251 # 1 byte length + 250 data

      # Test 0xfb marker (251-65535): length 251 should use 0xfb + u16 LE
      let data251 = newSeq[byte](251)
      let serialized251 = encode(data251, config)
      check serialized251[0] == 0xfb'u8
      check serialized251.len == 254 # 3 bytes (0xfb + u16) + 251 data

      # Test 0xfc marker (65536+): length 65536 should use 0xfc + u32 LE
      let data65536 = newSeq[byte](65536)
      let serialized65536 = encode(data65536, config)
      check serialized65536[0] == 0xfc'u8
      check serialized65536.len == 65541 # 5 bytes (0xfc + u32) + 65536 data

# ============================================================================
# Fixed 8-byte Encoding Cross-Verification Tests
# ============================================================================

when RUN_FIXED8_TESTS:
  suite "Rust serialize → Nim deserialize (fixed 8-byte)":
    test "deserialize rust_fixed8_001.bin":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_001.bin", config)
      check deserialized == @[byte(1), 2, 3, 4, 5]

    test "deserialize rust_fixed8_002.bin (empty)":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_002.bin", config)
      check deserialized.len == 0

    test "deserialize rust_fixed8_003.bin":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_003.bin", config)
      check deserialized == @[byte(0), 255, 128, 64]

    test "deserialize rust_fixed8_004.bin (Hello, World!)":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_004.bin", config)
      let text = cast[string](deserialized)
      check text == "Hello, World!"

    test "deserialize rust_fixed8_005.bin":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_005.bin", config)
      check deserialized == @[byte(42)]

    test "deserialize rust_fixed8_006.bin (unicode)":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_006.bin", config)
      let text = cast[string](deserialized)
      check text == "Test with émojis 🚀"

    test "deserialize rust_fixed8_007.bin (100 bytes)":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_007.bin", config)
      check deserialized.len == 100
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(1)

    test "deserialize rust_fixed8_008.bin (20kB)":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_008.bin", config)
      check deserialized.len == 20 * 1024
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

    test "deserialize rust_fixed8_009.bin (just below 251 threshold)":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_009.bin", config)
      check deserialized.len == 250
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

    test "deserialize rust_fixed8_010.bin (just at threshold)":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_010.bin", config)
      check deserialized.len == 251
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

    test "deserialize rust_fixed8_011.bin (just below 2^16 threshold)":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_011.bin", config)
      check deserialized.len == 65535
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

    test "deserialize rust_fixed8_012.bin (just at 2^16 threshold)":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_012.bin", config)
      check deserialized.len == 65536
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

when RUN_FIXED8_TESTS:
  suite "Nim serialize → Rust deserialize (fixed 8-byte)":
    test "serialize all test cases":
      let expectedData = getExpectedData()
      let config = standard().withFixedIntEncoding(8).withLimit(4294967305'u64)
      for i, filename in DeserializeTestFilesFixed8:
        serializeToFile(expectedData[i], filename, config)

when RUN_FIXED8_TESTS:
  suite "Byte-for-byte compatibility (fixed 8-byte)":
    test "verify Rust fixed8 roundtrip matches data":
      let testCases = getExpectedData()[0 .. 6] # avoid huge allocations
      let config = standard().withFixedIntEncoding(8)

      for original in testCases:
        let nimSerialized = encode(original, config)
        let nimDeserialized = decode(nimSerialized, config)

        # Roundtrip must preserve data
        check nimDeserialized == original

when RUN_FIXED8_TESTS:
  suite "Nim roundtrip (fixed 1-byte length prefix)":
    test "deserialize(serialize(payload)) for all payloads that fit u8 length":
      let testCases = expectedPayloadsForNimFixedRoundtrip(1)
      let config = standard().withFixedIntEncoding(1).withLimit(4294967305'u64)
      for original in testCases:
        let wire = encode(original, config)
        let back = decode(wire, config)
        check back == original

    test "empty vec uses one zero byte as length prefix":
      let config = standard().withFixedIntEncoding(1).withLimit(4294967305'u64)
      let wire = encode(newSeq[byte](), config)
      check wire == @[0'u8]
      check decode(wire, config).len == 0

when RUN_FIXED8_TESTS:
  suite "Nim roundtrip (fixed 2-byte length prefix)":
    test "deserialize(serialize(payload)) for all payloads that fit u16 length":
      let testCases = expectedPayloadsForNimFixedRoundtrip(2)
      let config = standard().withFixedIntEncoding(2).withLimit(4294967305'u64)
      for original in testCases:
        let wire = encode(original, config)
        let back = decode(wire, config)
        check back == original

    test "empty vec uses two little-endian zero bytes as length prefix":
      let config = standard().withFixedIntEncoding(2).withLimit(4294967305'u64)
      let wire = encode(newSeq[byte](), config)
      check wire == @[0'u8, 0'u8]
      check decode(wire, config).len == 0

when RUN_FIXED8_TESTS:
  suite "Nim roundtrip (fixed 4-byte length prefix)":
    test "deserialize(serialize(payload)) for all payloads that fit u32 length":
      let testCases = expectedPayloadsForNimFixedRoundtrip(4)
      let config = standard().withFixedIntEncoding(4).withLimit(4294967305'u64)
      for original in testCases:
        let wire = encode(original, config)
        let back = decode(wire, config)
        check back == original

    test "empty vec uses four little-endian zero bytes as length prefix":
      let config = standard().withFixedIntEncoding(4).withLimit(4294967305'u64)
      let wire = encode(newSeq[byte](), config)
      check wire == @[0'u8, 0'u8, 0'u8, 0'u8]
      check decode(wire, config).len == 0

{.pop.}
