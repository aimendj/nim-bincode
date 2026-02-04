{.push raises: [], gcsafe.}

import unittest
import strutils
import ../nim_bincode

# ============================================================================
# Basic Serialization/Deserialization Tests
# ============================================================================

suite "Basic serialize/deserialize":
  test "serialize and deserialize basic byte array":
    let original = @[byte(1), 2, 3, 4, 5]
    let serialized = serialize(original)
    check original == deserialize(serialized)

  test "serialize and deserialize empty array":
    let original: seq[byte] = @[]
    let serialized = serialize(original)
    # With fixed integer encoding, empty arrays serialize to 8 zero bytes (u64 length prefix)
    check serialized.len == 8
    # All 8 bytes should be zero (little-endian u64 for length 0)
    for i in 0 ..< serialized.len:
      check serialized[i] == byte(0)
    check original == deserialize(serialized)

  test "serialize and deserialize single byte":
    let original = @[byte(42)]
    let serialized = serialize(original)
    check original == deserialize(serialized)

  test "serialize and deserialize large array":
    var original = newSeq[byte](1000)
    for i in 0 ..< 1000:
      original[i] = byte(i mod 256)
    let serialized = serialize(original)
    check original == deserialize(serialized)

  test "serialize and deserialize with all byte values":
    var original = newSeq[byte](256)
    for i in 0 ..< 256:
      original[i] = byte(i)
    let serialized = serialize(original)
    check original == deserialize(serialized)

  test "serialize and deserialize with zeros":
    let original = @[byte(0), 0, 0, 0, 0]
    let serialized = serialize(original)
    check original == deserialize(serialized)

  test "serialize and deserialize with max byte values":
    let original = @[byte(255), 255, 255]
    let serialized = serialize(original)
    check original == deserialize(serialized)

  test "deserialize empty data raises exception":
    let empty: seq[byte] = @[]
    expect BincodeError:
      discard deserialize(empty)

# ============================================================================
# String Serialization Tests
# ============================================================================

suite "String serialization":
  test "serialize and deserialize basic string":
    let original = "Hello, World!"
    let serialized = serializeString(original)
    check original == deserializeString(serialized)

  test "serialize and deserialize empty string":
    let original = ""
    let serialized = serializeString(original)
    check original == deserializeString(serialized)

  test "serialize and deserialize unicode string":
    let original = "Test with émojis 🚀"
    let serialized = serializeString(original)
    check original == deserializeString(serialized)

  test "serialize and deserialize long string":
    let original = "Very long string: ".repeat(100)
    let serialized = serializeString(original)
    check original == deserializeString(serialized)

  test "serialize and deserialize string with null bytes":
    let original = "Null\0byte"
    let serialized = serializeString(original)
    check original == deserializeString(serialized)

  test "serialize and deserialize multiline string":
    let original = "Line 1\nLine 2\nLine 3"
    let serialized = serializeString(original)
    check original == deserializeString(serialized)

# ============================================================================
# Integer Serialization Tests
# ============================================================================

suite "Int32 serialization":
  test "serialize and deserialize int32 zero":
    let original: int32 = 0
    let serialized = serializeInt32(original)
    check original == deserializeInt32(serialized)

  test "serialize and deserialize int32 positive":
    let original: int32 = 42
    let serialized = serializeInt32(original)
    check original == deserializeInt32(serialized)

  test "serialize and deserialize int32 negative":
    let original: int32 = -42
    let serialized = serializeInt32(original)
    check original == deserializeInt32(serialized)

  test "serialize and deserialize int32 max":
    let original: int32 = int32.high
    let serialized = serializeInt32(original)
    check original == deserializeInt32(serialized)

  test "serialize and deserialize int32 min":
    let original: int32 = int32.low
    let serialized = serializeInt32(original)
    check original == deserializeInt32(serialized)

  test "deserialize int32 with insufficient data raises exception":
    let insufficient = @[byte(1), 2, 3] # Only 3 bytes, need 4
    expect BincodeError:
      discard deserializeInt32(insufficient)

suite "Uint32 serialization":
  test "serialize and deserialize uint32 zero":
    let original: uint32 = 0'u32
    let serialized = serializeUint32(original)
    check original == deserializeUint32(serialized)

  test "serialize and deserialize uint32 positive":
    let original: uint32 = 42'u32
    let serialized = serializeUint32(original)
    check original == deserializeUint32(serialized)

  test "serialize and deserialize uint32 max":
    let original: uint32 = uint32.high
    let serialized = serializeUint32(original)
    check original == deserializeUint32(serialized)

  test "deserialize uint32 with insufficient data raises exception":
    let insufficient = @[byte(1), 2, 3] # Only 3 bytes, need 4
    expect BincodeError:
      discard deserializeUint32(insufficient)

suite "Int64 serialization":
  test "serialize and deserialize int64 zero":
    let original: int64 = 0
    let serialized = serializeInt64(original)
    check original == deserializeInt64(serialized)

  test "serialize and deserialize int64 positive":
    let original: int64 = 42
    let serialized = serializeInt64(original)
    check original == deserializeInt64(serialized)

  test "serialize and deserialize int64 negative":
    let original: int64 = -42
    let serialized = serializeInt64(original)
    check original == deserializeInt64(serialized)

  test "serialize and deserialize int64 max":
    let original: int64 = int64.high
    let serialized = serializeInt64(original)
    check original == deserializeInt64(serialized)

  test "serialize and deserialize int64 min":
    let original: int64 = int64.low
    let serialized = serializeInt64(original)
    check original == deserializeInt64(serialized)

  test "deserialize int64 with insufficient data raises exception":
    let insufficient = @[byte(1), 2, 3, 4, 5, 6, 7] # Only 7 bytes, need 8
    expect BincodeError:
      discard deserializeInt64(insufficient)

# ============================================================================
# Roundtrip Tests
# ============================================================================

suite "Roundtrip tests":
  test "multiple roundtrips preserve data":
    let original = @[byte(1), 2, 3, 4, 5, 100, 200, 255]
    var current = original
    for i in 0 ..< 5:
      current = deserialize(serialize(current))
    check current == original

  test "roundtrip with mixed data":
    let original = @[byte(0), 1, 2, 255, 128, 64, 32, 16, 8, 4, 2, 1, 0]
    let serialized = serialize(original)
    check original == deserialize(serialized)

# ============================================================================
# Edge Cases
# ============================================================================

suite "Edge cases":
  test "serialize single zero byte":
    let original = @[byte(0)]
    let serialized = serialize(original)
    check original == deserialize(serialized)

  test "serialize single max byte":
    let original = @[byte(255)]
    let serialized = serialize(original)
    check original == deserialize(serialized)

  test "serialize pattern bytes":
    let original = @[byte(0xAA), 0x55, 0xAA, 0x55]
    let serialized = serialize(original)
    check original == deserialize(serialized)

{.pop.}
