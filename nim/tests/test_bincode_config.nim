{.push raises: [], gcsafe.}

import unittest
import ../bincode_config
import ../nim_bincode

suite "Bincode Config":
  test "standard config has correct defaults":
    let config = standard()
    check config.byteOrder == LittleEndian
    check config.intSize == 8
    check config.sizeLimit == BINCODE_SIZE_LIMIT

  test "withLittleEndian sets byte order":
    let config = standard().withLittleEndian()
    check config.byteOrder == LittleEndian

  test "withBigEndian sets byte order":
    let config = standard().withBigEndian()
    check config.byteOrder == BigEndian

  test "withFixedIntEncoding with default size":
    let config = standard().withFixedIntEncoding()
    check config.intSize == 8

  test "withFixedIntEncoding with size 1":
    let config = standard().withFixedIntEncoding(1)
    check config.intSize == 1

  test "withFixedIntEncoding with size 2":
    let config = standard().withFixedIntEncoding(2)
    check config.intSize == 2

  test "withFixedIntEncoding with size 4":
    let config = standard().withFixedIntEncoding(4)
    check config.intSize == 4

  test "withFixedIntEncoding with size 8":
    let config = standard().withFixedIntEncoding(8)
    check config.intSize == 8

  test "withFixedIntEncoding with size 0 maps to variable (intSize == 0)":
    let config = standard().withFixedIntEncoding(0)
    check config.intSize == 0

  test "withFixedIntEncoding with invalid size raises BincodeConfigError":
    expect BincodeConfigError:
      discard standard().withFixedIntEncoding(3)
    expect BincodeConfigError:
      discard standard().withFixedIntEncoding(5)
    expect BincodeConfigError:
      discard standard().withFixedIntEncoding(7)
    expect BincodeConfigError:
      discard standard().withFixedIntEncoding(9)
    expect BincodeConfigError:
      discard standard().withFixedIntEncoding(-1)

  test "withVariableIntEncoding sets intSize to 0":
    let config = standard().withVariableIntEncoding()
    check config.intSize == 0

  test "withLimit sets size limit":
    let customLimit: uint64 = 1024
    let config = standard().withLimit(customLimit)
    check config.sizeLimit == customLimit

  test "config builder chaining":
    let config = standard().withBigEndian().withFixedIntEncoding(4).withLimit(2048'u64)
    check config.byteOrder == BigEndian
    check config.intSize == 4
    check config.sizeLimit == 2048'u64

suite "Config with Serialization":
  test "default config serializes correctly":
    let data = @[byte(1), 2, 3]
    let config = standard()
    let serialized = serialize(data, config)
    let deserialized = deserialize(serialized, config)
    check data == deserialized

  test "big-endian config serializes correctly":
    let data = @[byte(1), 2, 3]
    let config = standard().withBigEndian()
    let serialized = serialize(data, config)
    let deserialized = deserialize(serialized, config)
    check data == deserialized

  test "variable encoding config serializes correctly":
    let data = @[byte(1), 2, 3]
    let config = standard().withVariableIntEncoding()
    let serialized = serialize(data, config)
    let deserialized = deserialize(serialized, config)
    check data == deserialized
    check serialized.len < 13

  test "custom size limit enforces limit":
    let config = standard().withLimit(10'u64)
    let smallData = @[byte(1), 2, 3]
    check smallData.len.uint64 <= config.sizeLimit
    let serialized = serialize(smallData, config)
    check smallData.len.uint64 <= config.sizeLimit

  test "custom size limit raises on exceed":
    let config = standard().withLimit(10'u64)
    let largeData = newSeq[byte](100)
    expect BincodeError:
      discard serialize(largeData, config)

suite "Config with Integer Serialization":
  test "default config serializes int32":
    let value: int32 = 42
    let config = standard()
    let serialized = serializeInt32(value, config)
    let deserialized = deserializeInt32(serialized, config)
    check value == deserialized

  test "fixed 1-byte encoding serializes int32":
    let value: int32 = 42
    let config = standard().withFixedIntEncoding(1)
    let serialized = serializeInt32(value, config)
    let deserialized = deserializeInt32(serialized, config)
    check value == deserialized

  test "fixed 2-byte encoding serializes int32":
    let value: int32 = 1000
    let config = standard().withFixedIntEncoding(2)
    let serialized = serializeInt32(value, config)
    let deserialized = deserializeInt32(serialized, config)
    check value == deserialized

  test "fixed 4-byte encoding serializes int32":
    let value: int32 = 100000
    let config = standard().withFixedIntEncoding(4)
    let serialized = serializeInt32(value, config)
    let deserialized = deserializeInt32(serialized, config)
    check value == deserialized

  test "fixed 8-byte encoding serializes int32":
    let value: int32 = 42
    let config = standard().withFixedIntEncoding(8)
    let serialized = serializeInt32(value, config)
    let deserialized = deserializeInt32(serialized, config)
    check value == deserialized

  test "variable encoding serializes int32":
    let value: int32 = 42
    let config = standard().withVariableIntEncoding()
    let serialized = serializeInt32(value, config)
    let deserialized = deserializeInt32(serialized, config)
    check value == deserialized

  test "big-endian config serializes int32":
    let value: int32 = 42
    let config = standard().withBigEndian()
    let serialized = serializeInt32(value, config)
    let deserialized = deserializeInt32(serialized, config)
    check value == deserialized

  test "default config serializes uint32":
    let value: uint32 = 42
    let config = standard()
    let serialized = serializeUint32(value, config)
    let deserialized = deserializeUint32(serialized, config)
    check value == deserialized

  test "variable encoding serializes uint32":
    let value: uint32 = 42
    let config = standard().withVariableIntEncoding()
    let serialized = serializeUint32(value, config)
    let deserialized = deserializeUint32(serialized, config)
    check value == deserialized

  test "default config serializes int64":
    let value: int64 = 123456789
    let config = standard()
    let serialized = serializeInt64(value, config)
    let deserialized = deserializeInt64(serialized, config)
    check value == deserialized

  test "variable encoding serializes int64":
    let value: int64 = 123456789
    let config = standard().withVariableIntEncoding()
    let serialized = serializeInt64(value, config)
    let deserialized = deserializeInt64(serialized, config)
    check value == deserialized

suite "Config Compatibility":
  test "configs with same settings produce same output":
    let data = @[byte(1), 2, 3, 4, 5]
    let config1 = standard()
    let config2 = standard().withLittleEndian().withFixedIntEncoding(8)
    let serialized1 = serialize(data, config1)
    let serialized2 = serialize(data, config2)
    check serialized1 == serialized2

  test "big-endian produces different output than little-endian":
    let data = @[byte(1), 2, 3, 4, 5]
    let leConfig = standard().withLittleEndian()
    let beConfig = standard().withBigEndian()
    let leSerialized = serialize(data, leConfig)
    let beSerialized = serialize(data, beConfig)
    check leSerialized != beSerialized

  test "variable encoding produces different output than fixed":
    let data = @[byte(1), 2, 3]
    let fixedConfig = standard().withFixedIntEncoding()
    let varConfig = standard().withVariableIntEncoding()
    let fixedSerialized = serialize(data, fixedConfig)
    let varSerialized = serialize(data, varConfig)
    check fixedSerialized != varSerialized

{.pop.}
