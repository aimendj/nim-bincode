{.push raises: [], gcsafe.}

import unittest
import os
import ../nim_bincode
import ../bincode_config

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
const DeserializeTestFilesVariable {.used.}: array[14, string] = [
  "nim_var_001.bin", "nim_var_002.bin", "nim_var_003.bin", "nim_var_004.bin",
  "nim_var_005.bin", "nim_var_006.bin", "nim_var_007.bin", "nim_var_008.bin",
  "nim_var_009.bin", "nim_var_010.bin", "nim_var_011.bin", "nim_var_012.bin",
  "nim_var_013.bin", "nim_var_014.bin",
]

# Test files for fixed 8-byte encoding deserialization
const DeserializeTestFilesFixed8 {.used.}: array[14, string] = [
  "nim_fixed8_001.bin", "nim_fixed8_002.bin", "nim_fixed8_003.bin",
  "nim_fixed8_004.bin", "nim_fixed8_005.bin", "nim_fixed8_006.bin",
  "nim_fixed8_007.bin", "nim_fixed8_008.bin", "nim_fixed8_009.bin",
  "nim_fixed8_010.bin", "nim_fixed8_011.bin", "nim_fixed8_012.bin",
  "nim_fixed8_013.bin", "nim_fixed8_014.bin",
]

# Get expected data for deserialization tests
# Large arrays (4GB+) are created lazily to avoid slow upfront allocation
proc getExpectedData(): seq[seq[byte]] {.raises: [].} =
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
      newSeq[byte](0), # Placeholder for 4294967295 - will be created lazily
      newSeq[byte](0), # Placeholder for 4294967296 - will be created lazily
    ]

# Lazy creation of large arrays (only when actually needed for serialization)
proc getLargeArray(index: int): seq[byte] {.raises: [].} =
  case index
  of 12: # Just below 2^32 threshold
    return newSeq[byte](4294967295)
  of 13: # Just at 2^32 threshold
    return newSeq[byte](4294967296)
  else:
    return @[]

# ============================================================================
# Helper Functions
# ============================================================================

proc formatVecForLog(data: openArray[byte]): string {.raises: [].} =
  ## Format a vector for logging - show full vector if <= 20 bytes, otherwise show size only
  if data.len > 20:
    return $data.len & " bytes"
  else:
    return $data

proc serializeToFile(
    data: openArray[byte], filename: string, config: BincodeConfig = standard()
): void {.raises: [BincodeError, IOError, OSError].} =
  ## Serialize data and write to file for Rust to read
  let serialized = serialize(data, config)
  createDir(TestDataDir)
  let filePath = TestDataDir / filename
  writeFile(filePath, cast[string](serialized))
  echo "Serialized ", formatVecForLog(data), " to ", filename

proc deserializeFromFile(
    filename: string, config: BincodeConfig = standard()
): seq[byte] {.raises: [BincodeError, IOError].} =
  ## Read file and deserialize data that was serialized by Rust
  let filePath = TestDataDir / filename
  let serialized = cast[seq[byte]](readFile(filePath))
  return deserialize(serialized, config)

# ============================================================================
# Variable-Length Encoding (LEB128) Cross-Verification Tests
# ============================================================================

when RUN_VARIABLE_TESTS:
  suite "Rust serialize → Nim deserialize (variable encoding)":
    test "deserialize rust_var_001.bin":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_001.bin", config)
      echo "Deserialized ", formatVecForLog(deserialized), " from rust_var_001.bin"
      check deserialized == @[byte(1), 2, 3, 4, 5]

    test "deserialize rust_var_002.bin (empty)":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_002.bin", config)
      echo "Deserialized ",
        formatVecForLog(deserialized), " from rust_var_002.bin (empty)"
      check deserialized.len == 0

    test "deserialize rust_var_003.bin":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_003.bin", config)
      echo "Deserialized ", formatVecForLog(deserialized), " from rust_var_003.bin"
      check deserialized == @[byte(0), 255, 128, 64]

    test "deserialize rust_var_004.bin (100 bytes)":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_004.bin", config)
      echo "Deserialized ", deserialized.len, " bytes from rust_var_004.bin"
      check deserialized.len == 100
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(1)

    test "deserialize rust_var_005.bin (string)":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_005.bin", config)
      let text = cast[string](deserialized)
      echo "Deserialized ",
        formatVecForLog(deserialized), " (", text, ") from rust_var_005.bin"
      check text == "Hello, World!"

    test "deserialize rust_var_006.bin":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_006.bin", config)
      echo "Deserialized ", formatVecForLog(deserialized), " from rust_var_006.bin"
      check deserialized == @[byte(42)]

    test "deserialize rust_var_007.bin (unicode)":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_007.bin", config)
      let text = cast[string](deserialized)
      echo "Deserialized ",
        formatVecForLog(deserialized), " (", text, ") from rust_var_007.bin"
      check text == "Test with émojis 🚀"

    test "deserialize rust_var_008.bin (20kB)":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_008.bin", config)
      echo "Deserialized ", deserialized.len, " bytes from rust_var_008.bin (20kB)"
      check deserialized.len == 20 * 1024
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

    test "deserialize rust_var_009.bin (just below 251 threshold, uses single byte)":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_009.bin", config)
      echo "Deserialized ",
        deserialized.len,
        " bytes from rust_var_009.bin (just below threshold, uses single byte)"
      check deserialized.len == 250
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

    test "deserialize rust_var_010.bin (just at threshold, uses 0xfb + u16 LE)":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_010.bin", config)
      echo "Deserialized ",
        deserialized.len,
        " bytes from rust_var_010.bin (just at threshold, uses 0xfb + u16 LE)"
      check deserialized.len == 251
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

    test "deserialize rust_var_011.bin (just below 2^16 threshold, uses 0xfb + u16)":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_011.bin", config)
      echo "Deserialized ",
        deserialized.len,
        " bytes from rust_var_011.bin (just below 2^16 threshold, uses 0xfb + u16)"
      check deserialized.len == 65535
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

    test "deserialize rust_var_012.bin (just at 2^16 threshold, uses 0xfc + u32)":
      let config = standard().withVariableIntEncoding()
      let deserialized = deserializeFromFile("rust_var_012.bin", config)
      echo "Deserialized ",
        deserialized.len,
        " bytes from rust_var_012.bin (just at 2^16 threshold, uses 0xfc + u32)"
      check deserialized.len == 65536
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

    test "deserialize rust_var_013.bin (just below 2^32 threshold, uses 0xfc + u32)":
      let config = standard().withVariableIntEncoding().withLimit(4294967305'u64)
      let deserialized = deserializeFromFile("rust_var_013.bin", config)
      echo "Deserialized ",
        deserialized.len,
        " bytes from rust_var_013.bin (just below 2^32 threshold, uses 0xfc + u32)"
      check deserialized.len == 4294967295
      # Skip byte-by-byte check for very large arrays (too slow)
      # Just verify length and first/last few bytes
      if deserialized.len > 0:
        check deserialized[0] == byte(0)
        check deserialized[^1] == byte(0)

    test "deserialize rust_var_014.bin (just at 2^32 threshold, uses 0xfd + u64)":
      let config = standard().withVariableIntEncoding().withLimit(4294967305'u64)
      let deserialized = deserializeFromFile("rust_var_014.bin", config)
      echo "Deserialized ",
        deserialized.len,
        " bytes from rust_var_014.bin (just at 2^32 threshold, uses 0xfd + u64)"
      check deserialized.len == 4294967296
      # Skip byte-by-byte check for very large arrays (too slow)
      # Just verify length and first/last few bytes
      if deserialized.len > 0:
        check deserialized[0] == byte(0)
        check deserialized[^1] == byte(0)

when RUN_VARIABLE_TESTS:
  suite "Nim serialize → Rust deserialize (variable encoding)":
    test "serialize all test cases":
      let expectedData = getExpectedData()
      let config = standard().withVariableIntEncoding().withLimit(4294967305'u64)
      for i, filename in DeserializeTestFilesVariable:
        # Lazy-load large arrays (indices 12-13) only when needed
        let data =
          if i >= 12:
            getLargeArray(i)
          else:
            expectedData[i]
        serializeToFile(data, filename, config)
        echo "Created ", filename, " with variable encoding for Rust to verify"

when RUN_VARIABLE_TESTS:
  suite "Byte-for-byte compatibility (variable encoding)":
    test "verify Rust variable-length roundtrip matches data":
      let testCases = getExpectedData()[0 .. 6] # avoid huge allocations
      let config = standard().withVariableIntEncoding()

      for original in testCases:
        let nimSerialized = serialize(original, config)
        let nimDeserialized = deserialize(nimSerialized, config)

        # Roundtrip must preserve data
        check nimDeserialized == original

    test "verify marker byte prefixes (0xfb, 0xfc, 0xfd)":
      let config = standard().withVariableIntEncoding().withLimit(4294967305'u64)

      # Test single byte encoding (< 251): length 250 should be single byte
      let data250 = newSeq[byte](250)
      let serialized250 = serialize(data250, config)
      check serialized250[0] == 250'u8 # No marker, just the value itself
      check serialized250.len == 251 # 1 byte length + 250 data

      # Test 0xfb marker (251-65535): length 251 should use 0xfb + u16 LE
      let data251 = newSeq[byte](251)
      let serialized251 = serialize(data251, config)
      check serialized251[0] == 0xfb'u8
      check serialized251.len == 254 # 3 bytes (0xfb + u16) + 251 data

      # Test 0xfc marker (65536-4294967295): length 65536 should use 0xfc + u32 LE
      let data65536 = newSeq[byte](65536)
      let serialized65536 = serialize(data65536, config)
      check serialized65536[0] == 0xfc'u8
      check serialized65536.len == 65541 # 5 bytes (0xfc + u32) + 65536 data

      # Test 0xfd marker (4294967296+): length 4294967296 should use 0xfd + u64 LE
      # Skip full allocation for speed - just verify the marker byte in a small test
      # The actual 4GB test is covered by cross-verification with Rust
      let data4GB = getLargeArray(13) # Lazy load
      let serialized4GB = serialize(data4GB, config)
      check serialized4GB[0] == 0xfd'u8
      check serialized4GB.len == 4294967305 # 9 bytes (0xfd + u64) + 4294967296 data

# ============================================================================
# Fixed 8-byte Encoding Cross-Verification Tests
# ============================================================================

when RUN_FIXED8_TESTS:
  suite "Rust serialize → Nim deserialize (fixed 8-byte)":
    test "deserialize rust_fixed8_001.bin":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_001.bin", config)
      echo "Deserialized ", formatVecForLog(deserialized), " from rust_fixed8_001.bin"
      check deserialized == @[byte(1), 2, 3, 4, 5]

    test "deserialize rust_fixed8_002.bin (empty)":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_002.bin", config)
      echo "Deserialized ",
        formatVecForLog(deserialized), " from rust_fixed8_002.bin (empty)"
      check deserialized.len == 0

    test "deserialize rust_fixed8_003.bin":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_003.bin", config)
      echo "Deserialized ", formatVecForLog(deserialized), " from rust_fixed8_003.bin"
      check deserialized == @[byte(0), 255, 128, 64]

    test "deserialize rust_fixed8_004.bin (100 bytes)":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_004.bin", config)
      echo "Deserialized ", deserialized.len, " bytes from rust_fixed8_004.bin"
      check deserialized.len == 100
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(1)

    test "deserialize rust_fixed8_005.bin (string)":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_005.bin", config)
      let text = cast[string](deserialized)
      echo "Deserialized ",
        formatVecForLog(deserialized), " (", text, ") from rust_fixed8_005.bin"
      check text == "Hello, World!"

    test "deserialize rust_fixed8_006.bin":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_006.bin", config)
      echo "Deserialized ", formatVecForLog(deserialized), " from rust_fixed8_006.bin"
      check deserialized == @[byte(42)]

    test "deserialize rust_fixed8_007.bin (unicode)":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_007.bin", config)
      let text = cast[string](deserialized)
      echo "Deserialized ",
        formatVecForLog(deserialized), " (", text, ") from rust_fixed8_007.bin"
      check text == "Test with émojis 🚀"

    test "deserialize rust_fixed8_008.bin (20kB)":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_008.bin", config)
      echo "Deserialized ", deserialized.len, " bytes from rust_fixed8_008.bin (20kB)"
      check deserialized.len == 20 * 1024
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

    test "deserialize rust_fixed8_009.bin (just below 251 threshold)":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_009.bin", config)
      echo "Deserialized ",
        deserialized.len, " bytes from rust_fixed8_009.bin (just below threshold)"
      check deserialized.len == 250
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

    test "deserialize rust_fixed8_010.bin (just at threshold)":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_010.bin", config)
      echo "Deserialized ",
        deserialized.len, " bytes from rust_fixed8_010.bin (just at threshold)"
      check deserialized.len == 251
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

    test "deserialize rust_fixed8_011.bin (just below 2^16 threshold)":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_011.bin", config)
      echo "Deserialized ",
        deserialized.len, " bytes from rust_fixed8_011.bin (just below 2^16 threshold)"
      check deserialized.len == 65535
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

    test "deserialize rust_fixed8_012.bin (just at 2^16 threshold)":
      let config = standard().withFixedIntEncoding(8)
      let deserialized = deserializeFromFile("rust_fixed8_012.bin", config)
      echo "Deserialized ",
        deserialized.len, " bytes from rust_fixed8_012.bin (just at 2^16 threshold)"
      check deserialized.len == 65536
      for i in 0 ..< deserialized.len:
        check deserialized[i] == byte(0)

    test "deserialize rust_fixed8_013.bin (just below 2^32 threshold)":
      let config = standard().withFixedIntEncoding(8).withLimit(4294967305'u64)
      let deserialized = deserializeFromFile("rust_fixed8_013.bin", config)
      echo "Deserialized ",
        deserialized.len, " bytes from rust_fixed8_013.bin (just below 2^32 threshold)"
      check deserialized.len == 4294967295
      # Skip byte-by-byte check for very large arrays (too slow)
      # Just verify length and first/last few bytes
      if deserialized.len > 0:
        check deserialized[0] == byte(0)
        check deserialized[^1] == byte(0)

    test "deserialize rust_fixed8_014.bin (just at 2^32 threshold)":
      let config = standard().withFixedIntEncoding(8).withLimit(4294967305'u64)
      let deserialized = deserializeFromFile("rust_fixed8_014.bin", config)
      echo "Deserialized ",
        deserialized.len, " bytes from rust_fixed8_014.bin (just at 2^32 threshold)"
      check deserialized.len == 4294967296
      # Skip byte-by-byte check for very large arrays (too slow)
      # Just verify length and first/last few bytes
      if deserialized.len > 0:
        check deserialized[0] == byte(0)
        check deserialized[^1] == byte(0)

when RUN_FIXED8_TESTS:
  suite "Nim serialize → Rust deserialize (fixed 8-byte)":
    test "serialize all test cases":
      let expectedData = getExpectedData()
      let config = standard().withFixedIntEncoding(8).withLimit(4294967305'u64)
      for i, filename in DeserializeTestFilesFixed8:
        # Lazy-load large arrays (indices 12-13) only when needed
        let data =
          if i >= 12:
            getLargeArray(i)
          else:
            expectedData[i]
        serializeToFile(data, filename, config)
        echo "Created ", filename, " with fixed 8-byte encoding for Rust to verify"

when RUN_FIXED8_TESTS:
  suite "Byte-for-byte compatibility (fixed 8-byte)":
    test "verify Rust fixed8 roundtrip matches data":
      let testCases = getExpectedData()[0 .. 6] # avoid huge allocations
      let config = standard().withFixedIntEncoding(8)

      for original in testCases:
        let nimSerialized = serialize(original, config)
        let nimDeserialized = deserialize(nimSerialized, config)

        # Roundtrip must preserve data
        check nimDeserialized == original

{.pop.}
