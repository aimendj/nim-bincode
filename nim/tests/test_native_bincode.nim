{.push gcsafe.}

import unittest
import ../native_bincode

suite "Native bincode core serialization":
  test "serialize empty sequence":
    let empty: seq[byte] = @[]
    let serialized = serialize(empty)
    check serialized.len == 8
    check serialized == @[byte(0), 0, 0, 0, 0, 0, 0, 0]

  test "deserialize empty sequence":
    let empty_encoded: seq[byte] = @[byte(0), 0, 0, 0, 0, 0, 0, 0]
    let deserialized = deserialize(empty_encoded)
    check deserialized.len == 0
    let empty: seq[byte] = @[]
    check deserialized == empty

  test "serialize and deserialize small sequence":
    let original = @[byte(1), 2, 3, 4, 5]
    let serialized = serialize(original)
    check serialized.len == 13 # 8 bytes length + 5 bytes data
    check serialized[0..7] == @[byte(5), 0, 0, 0, 0, 0, 0, 0] # length prefix
    check serialized[8..12] == original # data

    let deserialized = deserialize(serialized)
    check deserialized == original

  test "roundtrip serialization":
    let original = @[byte(1), 2, 3, 4, 5, 100, 200, 255]
    let serialized = serialize(original)
    let deserialized = deserialize(serialized)
    check deserialized == original

  test "serialize single byte":
    let original = @[byte(42)]
    let serialized = serialize(original)
    check serialized.len == 9 # 8 bytes length + 1 byte data
    check serialized[0..7] == @[byte(1), 0, 0, 0, 0, 0, 0, 0] # length = 1
    check serialized[8] == byte(42)

    let deserialized = deserialize(serialized)
    check deserialized == original

  test "deserialize with insufficient data raises":
    let insufficient = @[byte(1), 2, 3] # Only 3 bytes, need at least 8
    expect BincodeError:
      discard deserialize(insufficient)

  test "deserialize with insufficient content raises":
    # 8 bytes length prefix says length = 5, but only 10 bytes total (need 13)
    let insufficient = @[byte(5), 0, 0, 0, 0, 0, 0, 0, 1, 2]
    expect BincodeError:
      discard deserialize(insufficient)

  test "deserialize with trailing bytes raises":
    # 8 bytes length prefix says length = 2, but have 13 bytes total (should be 10)
    let with_trailing = @[byte(2), 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5]
    expect BincodeError:
      discard deserialize(with_trailing)

  test "serialize with data exceeding limit raises":
    var large = newSeq[byte](65537) # 65537 bytes > 65536 limit
    for i in 0..<large.len:
      large[i] = byte(i mod 256)
    expect BincodeError:
      discard serialize(large)

  test "deserialize with length exceeding limit raises":
    # Length prefix says 65537, which exceeds limit
    var invalid = newSeq[byte](16)
    # Encode 65537 as little-endian u64: [1, 0, 1, 0, 0, 0, 0, 0]
    invalid[0] = byte(1)
    invalid[1] = byte(0)
    invalid[2] = byte(1)
    invalid[3] = byte(0)
    invalid[4] = byte(0)
    invalid[5] = byte(0)
    invalid[6] = byte(0)
    invalid[7] = byte(0)
    # Add some dummy data
    for i in 8..<invalid.len:
      invalid[i] = byte(i)
    expect BincodeError:
      discard deserialize(invalid)

suite "Native bincode string serialization":
  test "serialize empty string":
    let empty = ""
    let serialized = serializeString(empty)
    check serialized.len == 8
    check serialized == @[byte(0), 0, 0, 0, 0, 0, 0, 0]

  test "deserialize empty string":
    let empty_encoded = @[byte(0), 0, 0, 0, 0, 0, 0, 0]
    let deserialized = deserializeString(empty_encoded)
    check deserialized == ""

  test "serialize and deserialize basic string":
    let original = "Hello, World!"
    let serialized = serializeString(original)
    check serialized.len == 21 # 8 bytes length + 13 bytes UTF-8
    check serialized[0..7] == @[byte(13), 0, 0, 0, 0, 0, 0, 0] # length prefix

    let deserialized = deserializeString(serialized)
    check deserialized == original

  test "roundtrip string serialization":
    let original = "Test string with various characters: !@#$%^&*()"
    let serialized = serializeString(original)
    let deserialized = deserializeString(serialized)
    check deserialized == original

  test "serialize and deserialize unicode string":
    let original = "Test with émojis 🚀"
    let serialized = serializeString(original)
    let deserialized = deserializeString(serialized)
    check deserialized == original

  test "serialize and deserialize string with null bytes":
    let original = "Null\0byte"
    let serialized = serializeString(original)
    let deserialized = deserializeString(serialized)
    check deserialized == original

  test "serialize and deserialize multiline string":
    let original = "Line 1\nLine 2\nLine 3"
    let serialized = serializeString(original)
    let deserialized = deserializeString(serialized)
    check deserialized == original

  test "serialize string with various unicode characters":
    let original = "Unicode: 中文 العربية русский 🎉 émoji"
    let serialized = serializeString(original)
    let deserialized = deserializeString(serialized)
    check deserialized == original

{.pop.}
