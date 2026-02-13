# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import faststreams # Uses: memoryOutput, getOutput
import unittest2
import bincode_config
import nim_bincode

# Helper function to serialize using streaming API and return seq[byte]
proc serializeToSeq[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](
    data: openArray[byte], config: BincodeConfig[E, O, L], limit: uint64 = L
): seq[byte] {.raises: [BincodeError, IOError].} =
  var stream = memoryOutput()
  serialize(stream, data, config, limit)
  stream.getOutput()

# Convenience overload with default config
proc serializeToSeq(
    data: openArray[byte],
    config: Fixed8LEConfig = standard(),
    limit: uint64 = BINCODE_SIZE_LIMIT,
): seq[byte] {.raises: [BincodeError, IOError].} =
  serializeToSeq[FixedEncoding[8], LittleEndian, BINCODE_SIZE_LIMIT](
    data, config, limit
  )

# Helper function to serialize int32 using streaming API and return seq[byte]
proc serializeInt32ToSeq[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](value: int32, config: BincodeConfig[E, O, L]): seq[byte] {.raises: [IOError].} =
  var stream = memoryOutput()
  serializeInt32(stream, value, config)
  stream.getOutput()

# Convenience overload with default config
proc serializeInt32ToSeq(
    value: int32, config: Fixed8LEConfig = standard()
): seq[byte] {.raises: [IOError].} =
  serializeInt32ToSeq[FixedEncoding[8], LittleEndian, BINCODE_SIZE_LIMIT](value, config)

# Helper function to serialize uint32 using streaming API and return seq[byte]
proc serializeUint32ToSeq[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](value: uint32, config: BincodeConfig[E, O, L]): seq[byte] {.raises: [IOError].} =
  var stream = memoryOutput()
  serializeUint32(stream, value, config)
  stream.getOutput()

# Convenience overload with default config
proc serializeUint32ToSeq(
    value: uint32, config: Fixed8LEConfig = standard()
): seq[byte] {.raises: [IOError].} =
  serializeUint32ToSeq[FixedEncoding[8], LittleEndian, BINCODE_SIZE_LIMIT](
    value, config
  )

# Helper function to serialize int64 using streaming API and return seq[byte]
proc serializeInt64ToSeq[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](value: int64, config: BincodeConfig[E, O, L]): seq[byte] {.raises: [IOError].} =
  var stream = memoryOutput()
  serializeInt64(stream, value, config)
  stream.getOutput()

# Convenience overload with default config
proc serializeInt64ToSeq(
    value: int64, config: Fixed8LEConfig = standard()
): seq[byte] {.raises: [IOError].} =
  serializeInt64ToSeq[FixedEncoding[8], LittleEndian, BINCODE_SIZE_LIMIT](value, config)

suite "Bincode Config":
  test "standard config has correct defaults":
    let config = standard()
    check config is Fixed8LEConfig
    # Config is now empty object, limit is compile-time constant
    # Test that it works by using it
    let data = @[byte(1), 2, 3]
    let serialized = serializeToSeq(data, config)
    let deserialized = deserialize(serialized, config)
    check data == deserialized

  test "withLittleEndian changes byte order":
    let config = standard().withLittleEndian()
    check config is Fixed8LEConfig
    # Test that it works
    let data = @[byte(1), 2, 3]
    let serialized = serializeToSeq(data, config)
    let deserialized = deserialize(serialized, config)
    check data == deserialized

  test "withBigEndian changes byte order":
    let config = standard().withBigEndian()
    check config is Fixed8BEConfig
    # Test that it works
    let data = @[byte(1), 2, 3]
    let serialized = serializeToSeq(data, config)
    let deserialized = deserialize(serialized, config)
    check data == deserialized

  test "withFixedIntEncoding with default size":
    let config = standard().withFixedIntEncoding()
    check config is Fixed8LEConfig
    # Test that it works
    let data = @[byte(1), 2, 3]
    let serialized = serializeToSeq(data, config)
    let deserialized = deserialize(serialized, config)
    check data == deserialized

  test "withFixedIntEncoding with size 1":
    let config = standard().withFixedIntEncoding(1)
    check config is Fixed1LEConfig
    # Test that it works
    let data = @[byte(1), 2, 3]
    let serialized = serializeToSeq(data, config)
    let deserialized = deserialize(serialized, config)
    check data == deserialized

  test "withFixedIntEncoding with size 2":
    let config = standard().withFixedIntEncoding(2)
    check config is Fixed2LEConfig
    # Test that it works
    let data = @[byte(1), 2, 3]
    let serialized = serializeToSeq(data, config)
    let deserialized = deserialize(serialized, config)
    check data == deserialized

  test "withFixedIntEncoding with size 4":
    let config = standard().withFixedIntEncoding(4)
    check config is Fixed4LEConfig
    # Test that it works
    let data = @[byte(1), 2, 3]
    let serialized = serializeToSeq(data, config)
    let deserialized = deserialize(serialized, config)
    check data == deserialized

  test "withFixedIntEncoding with size 8":
    let config = standard().withFixedIntEncoding(8)
    check config is Fixed8LEConfig
    # Test that it works
    let data = @[byte(1), 2, 3]
    let serialized = serializeToSeq(data, config)
    let deserialized = deserialize(serialized, config)
    check data == deserialized

  test "withVariableIntEncoding creates variable encoding config":
    let config = standard().withVariableIntEncoding()
    check config is VariableLEConfig
    # Test that it works
    let data = @[byte(1), 2, 3]
    let serialized = serializeToSeq(data, config)
    let deserialized = deserialize(serialized, config)
    check data == deserialized

  test "withLimit sets size limit (compile-time)":
    const customLimit: uint64 = 1024
    let config = standard().withLimit(customLimit)
    # Config is now empty object, limit is compile-time constant
    # Test that it works by using it
    let data = @[byte(1), 2, 3]
    let serialized = serializeToSeq(data, config)
    let deserialized = deserialize(serialized, config)
    check data == deserialized

  test "config builder chaining":
    const customLimit: uint64 = 2048
    let config =
      standard().withBigEndian().withFixedIntEncoding(4).withLimit(customLimit)
    check config is BincodeConfig[FixedEncoding[4], BigEndian, customLimit]
    # Test that it works
    let data = @[byte(1), 2, 3]
    let serialized = serializeToSeq(data, config)
    let deserialized = deserialize(serialized, config)
    check data == deserialized

suite "Config with Serialization":
  test "default config serializes correctly":
    let data = @[byte(1), 2, 3]
    let config = standard()
    let serialized = serializeToSeq(data, config)
    let deserialized = deserialize(serialized, config)
    check data == deserialized

  test "big-endian config serializes correctly":
    let data = @[byte(1), 2, 3]
    let config = standard().withBigEndian()
    let serialized = serializeToSeq(data, config)
    let deserialized = deserialize(serialized, config)
    check data == deserialized

  test "variable encoding config serializes correctly":
    let data = @[byte(1), 2, 3]
    let config = standard().withVariableIntEncoding()
    let serialized = serializeToSeq(data, config)
    let deserialized = deserialize(serialized, config)
    check data == deserialized
    check serialized.len < 13

  test "custom size limit enforces limit (compile-time)":
    const customLimit: uint64 = 10
    let config = standard().withLimit(customLimit)
    let smallData = @[byte(1), 2, 3]
    check smallData.len.uint64 <= customLimit
    let serialized = serializeToSeq(smallData, config)
    let deserialized = deserialize(serialized, config)
    check smallData == deserialized

  test "custom size limit raises on exceed (compile-time)":
    const customLimit: uint64 = 10
    let config = standard().withLimit(customLimit)
    let largeData = newSeq[byte](100)
    expect BincodeError:
      discard serializeToSeq(largeData, config)

  test "runtime size limit enforces limit":
    # This test specifically tests runtime limits (when limit is calculated at runtime)
    # In real scenarios, this would be based on dynamic data, user input, etc.
    # Note: Even though we use a constant value here, we're testing the runtime limit API
    let runtimeLimit: uint64 = 10 # Simulating a runtime-calculated limit
    let config = standard() # Use default compile-time config
    let smallData = @[byte(1), 2, 3]
    check smallData.len.uint64 <= runtimeLimit
    let serialized = serializeToSeq(smallData, config, limit = runtimeLimit)
    let deserialized = deserialize(serialized, config, limit = runtimeLimit)
    check smallData == deserialized

  test "runtime size limit raises on exceed":
    # This test specifically tests runtime limits (when limit is calculated at runtime)
    let runtimeLimit: uint64 = 10 # Simulating a runtime-calculated limit
    let config = standard() # Use default compile-time config
    let largeData = newSeq[byte](100)
    expect BincodeError:
      discard serializeToSeq(largeData, config, limit = runtimeLimit)

suite "Config with Integer Serialization":
  test "default config serializes int32":
    let value: int32 = 42
    let config = standard()
    let serialized = serializeInt32ToSeq(value, config)
    let deserialized = deserializeInt32(serialized, config)
    check value == deserialized

  test "fixed 1-byte encoding serializes int32":
    let value: int32 = 42
    let config = standard().withFixedIntEncoding(1)
    let serialized = serializeInt32ToSeq(value, config)
    let deserialized = deserializeInt32(serialized, config)
    check value == deserialized

  test "fixed 2-byte encoding serializes int32":
    let value: int32 = 1000
    let config = standard().withFixedIntEncoding(2)
    let serialized = serializeInt32ToSeq(value, config)
    let deserialized = deserializeInt32(serialized, config)
    check value == deserialized

  test "fixed 4-byte encoding serializes int32":
    let value: int32 = 100000
    let config = standard().withFixedIntEncoding(4)
    let serialized = serializeInt32ToSeq(value, config)
    let deserialized = deserializeInt32(serialized, config)
    check value == deserialized

  test "fixed 8-byte encoding serializes int32":
    let value: int32 = 42
    let config = standard().withFixedIntEncoding(8)
    let serialized = serializeInt32ToSeq(value, config)
    let deserialized = deserializeInt32(serialized, config)
    check value == deserialized

  test "fixed 1-byte encoding preserves negative int32 (sign extension)":
    let value: int32 = -42
    let config = standard().withFixedIntEncoding(1)
    let serialized = serializeInt32ToSeq(value, config)
    let deserialized = deserializeInt32(serialized, config)
    check value == deserialized

  test "fixed 2-byte encoding preserves negative int32 (sign extension)":
    let value: int32 = -42
    let config = standard().withFixedIntEncoding(2)
    let serialized = serializeInt32ToSeq(value, config)
    let deserialized = deserializeInt32(serialized, config)
    check value == deserialized

  test "fixed 1-byte encoding preserves negative int32 with big-endian (sign extension)":
    let value: int32 = -42
    let config = standard().withFixedIntEncoding(1).withBigEndian()
    let serialized = serializeInt32ToSeq(value, config)
    let deserialized = deserializeInt32(serialized, config)
    check value == deserialized

  test "fixed 2-byte encoding preserves negative int32 with big-endian (sign extension)":
    let value: int32 = -42
    let config = standard().withFixedIntEncoding(2).withBigEndian()
    let serialized = serializeInt32ToSeq(value, config)
    let deserialized = deserializeInt32(serialized, config)
    check value == deserialized

  test "variable encoding serializes int32":
    let value: int32 = 42
    let config = standard().withVariableIntEncoding()
    let serialized = serializeInt32ToSeq(value, config)
    let deserialized = deserializeInt32(serialized, config)
    check value == deserialized

  test "big-endian config serializes int32":
    let value: int32 = 42
    let config = standard().withBigEndian()
    let serialized = serializeInt32ToSeq(value, config)
    let deserialized = deserializeInt32(serialized, config)
    check value == deserialized

  test "default config serializes uint32":
    let value: uint32 = 42
    let config = standard()
    let serialized = serializeUint32ToSeq(value, config)
    let deserialized = deserializeUint32(serialized, config)
    check value == deserialized

  test "variable encoding serializes uint32":
    let value: uint32 = 42
    let config = standard().withVariableIntEncoding()
    let serialized = serializeUint32ToSeq(value, config)
    let deserialized = deserializeUint32(serialized, config)
    check value == deserialized

  test "default config serializes int64":
    let value: int64 = 123456789
    let config = standard()
    let serialized = serializeInt64ToSeq(value, config)
    let deserialized = deserializeInt64(serialized, config)
    check value == deserialized

  test "variable encoding serializes int64":
    let value: int64 = 123456789
    let config = standard().withVariableIntEncoding()
    let serialized = serializeInt64ToSeq(value, config)
    let deserialized = deserializeInt64(serialized, config)
    check value == deserialized

  test "fixed 1-byte encoding preserves negative int64 (sign extension)":
    let value: int64 = -42
    let config = standard().withFixedIntEncoding(1)
    let serialized = serializeInt64ToSeq(value, config)
    let deserialized = deserializeInt64(serialized, config)
    check value == deserialized

  test "fixed 2-byte encoding preserves negative int64 (sign extension)":
    let value: int64 = -42
    let config = standard().withFixedIntEncoding(2)
    let serialized = serializeInt64ToSeq(value, config)
    let deserialized = deserializeInt64(serialized, config)
    check value == deserialized

  test "fixed 4-byte encoding preserves negative int64 (sign extension)":
    let value: int64 = -42
    let config = standard().withFixedIntEncoding(4)
    let serialized = serializeInt64ToSeq(value, config)
    let deserialized = deserializeInt64(serialized, config)
    check value == deserialized

  test "fixed 1-byte encoding preserves negative int64 with big-endian (sign extension)":
    let value: int64 = -42
    let config = standard().withFixedIntEncoding(1).withBigEndian()
    let serialized = serializeInt64ToSeq(value, config)
    let deserialized = deserializeInt64(serialized, config)
    check value == deserialized

suite "Config Compatibility":
  test "configs with same settings produce same output":
    let data = @[byte(1), 2, 3, 4, 5]
    let config1 = standard()
    let config2 = standard().withLittleEndian().withFixedIntEncoding(8)
    let serialized1 = serializeToSeq(data, config1)
    let serialized2 = serializeToSeq(data, config2)
    check serialized1 == serialized2

  test "big-endian produces different output than little-endian":
    let data = @[byte(1), 2, 3, 4, 5]
    let leConfig = standard().withLittleEndian()
    let beConfig = standard().withBigEndian()
    let leSerialized = serializeToSeq(data, leConfig)
    let beSerialized = serializeToSeq(data, beConfig)
    check leSerialized != beSerialized

  test "variable encoding produces different output than fixed":
    let data = @[byte(1), 2, 3]
    let fixedConfig = standard().withFixedIntEncoding()
    let varConfig = standard().withVariableIntEncoding()
    let fixedSerialized = serializeToSeq(data, fixedConfig)
    let varSerialized = serializeToSeq(data, varConfig)
    check fixedSerialized != varSerialized

{.pop.}
