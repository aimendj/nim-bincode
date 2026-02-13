# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import faststreams # Uses: OutputStreamHandle, write
import stew/[endians2, leb128]
import bincode_config
import bincode_common

## Helper functions for string and integer serialization/deserialization.
##
## This module provides higher-level operations that build on top of the core
## byte serialization from `bincode_common`:
## - String serialization/deserialization (UTF-8)
## - Integer serialization/deserialization (int32, uint32, int64)

proc serializeString*[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](
    stream: OutputStreamHandle,
    s: string,
    config: BincodeConfig[E, O, L],
    limit: uint64 = L,
) {.raises: [BincodeError, IOError].} =
  ## Serialize a string to bincode format and write to stream.
  ##
  ## Format depends on config:
  ## - Fixed encoding: [8-byte u64 length] + [UTF-8 bytes]
  ## - Variable encoding: [LEB128 length] + [UTF-8 bytes]
  ##
  ## The length is the UTF-8 byte count, not character count.
  ## Unicode characters are handled correctly (multi-byte UTF-8 sequences).
  ##
  ## `limit` is the maximum size limit (defaults to compile-time `L`).
  ## Pass a runtime `limit` for dynamic limits (e.g., in benchmarks).
  ##
  ## Raises `BincodeError` if UTF-8 byte length exceeds the specified size limit.
  ## Raises `IOError` if stream write fails.
  ##
  ## Empty strings serialize to a zero-length prefix + no data bytes.

  checkSizeLimit(s.len.uint64, limit)

  # Write length prefix directly to stream
  encodeLength(stream, s.len.uint64, config)

  # Write string bytes directly to stream (no intermediate allocation)
  if s.len > 0:
    # Strings in Nim are UTF-8, so we can write the underlying bytes directly
    stream.write(s.toOpenArray(0, s.high))

# Convenience overload with default config
proc serializeString*(
    stream: OutputStreamHandle,
    s: string,
    config: Fixed8LEConfig = standard(),
    limit: uint64 = BINCODE_SIZE_LIMIT,
) {.raises: [BincodeError, IOError].} =
  serializeString[FixedEncoding[8], LittleEndian, BINCODE_SIZE_LIMIT](
    stream, s, config, limit
  )

func deserializeString*[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](
    data: openArray[byte], config: BincodeConfig[E, O, L], limit: uint64 = L
): string {.raises: [BincodeError].} =
  ## Deserialize bincode-encoded data to a string.
  ##
  ## Format depends on config:
  ## - Fixed encoding: [8-byte u64 length] + [UTF-8 bytes]
  ## - Variable encoding: [LEB128 length] + [UTF-8 bytes]
  ##
  ## The length is the UTF-8 byte count, not character count.
  ## Unicode characters are handled correctly (multi-byte UTF-8 sequences).
  ##
  ## `limit` is the maximum size limit (defaults to compile-time `L`).
  ## Pass a runtime `limit` for dynamic limits (e.g., in benchmarks).
  ##
  ## Raises `BincodeError` if:
  ## - Data is insufficient for length prefix
  ## - Length exceeds the specified size limit
  ## - Insufficient data for content
  ## - Trailing bytes detected
  ## - Invalid UTF-8 encoding

  let bytes = deserialize[E, O, L](data, config, limit)

  if bytes.len == 0:
    return ""

  var output = newString(bytes.len)
  copyMem(output[0].addr, bytes[0].addr, bytes.len)
  output

# Convenience overload with default config
func deserializeString*(
    data: openArray[byte],
    config: Fixed8LEConfig = standard(),
    limit: uint64 = BINCODE_SIZE_LIMIT,
): string {.raises: [BincodeError].} =
  deserializeString[FixedEncoding[8], LittleEndian, BINCODE_SIZE_LIMIT](
    data, config, limit
  )

proc serializeInt32*[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](
    stream: OutputStreamHandle, value: int32, config: BincodeConfig[E, O, L]
) {.raises: [IOError].} =
  ## Serialize an int32 to bincode format and write to stream.
  ##
  ## Wraps the int32 bytes in Vec<u8> format.
  ## Format depends on config:
  ## - Fixed encoding: [length prefix] + [N-byte int32] where N is the fixed size
  ## - Variable encoding: [length prefix] + [LEB128 int32]
  ##
  ## Byte order applies to fixed encoding.

  when E is FixedEncoding:
    const size = E.Size
    let bytes =
      when O == LittleEndian:
        toBytesLE(value.int64.uint64)
      elif O == BigEndian:
        toBytesBE(value.int64.uint64)

    # Write length prefix directly to stream
    encodeLength(stream, size.uint64, config)

    # Write int bytes directly to stream (no intermediate seq allocation)
    when O == LittleEndian:
      stream.write(bytes.toOpenArray(0, size - 1))
    elif O == BigEndian:
      stream.write(bytes.toOpenArray(8 - size, 7))
  elif E is VariableEncoding:
    # Variable encoding: LEB128
    let zigzag = zigzagEncode(value.int64)
    let buf = toBytes(zigzag, Leb128)
    let leb128Len = buf.len

    # Write length prefix directly to stream
    encodeLength(stream, leb128Len.uint64, config)

    # Write LEB128 bytes directly to stream (no intermediate seq allocation)
    stream.write(buf.toOpenArray())

# Convenience overload with default config
proc serializeInt32*(
    stream: OutputStreamHandle, value: int32, config: Fixed8LEConfig = standard()
) {.raises: [IOError].} =
  serializeInt32[FixedEncoding[8], LittleEndian, BINCODE_SIZE_LIMIT](
    stream, value, config
  )

func deserializeInt32*[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](
    data: openArray[byte], config: BincodeConfig[E, O, L], limit: uint64 = L
): int32 {.raises: [BincodeError].} =
  ## Deserialize bincode-encoded data to an int32.
  ##
  ## Expects Vec<u8> format.
  ## Raises `BincodeError` if deserialized data is insufficient.

  let bytes = deserialize[E, O, L](data, config, limit)
  when E is FixedEncoding:
    const size = E.Size
    if bytes.len < size:
      raise newException(BincodeError, "Cannot deserialize int32: insufficient data")
    var paddedBytes: array[8, byte]
    when O == LittleEndian:
      copyMem(paddedBytes[0].addr, bytes[0].addr, size)
      # Sign-extend if MSB (last byte) is negative
      if (bytes[size - 1] and 0x80'u8) != 0:
        for i in size .. 7:
          paddedBytes[i] = 0xFF'u8
      let uintValue = fromBytesLE(uint64, paddedBytes)
      return cast[int32](uintValue)
    elif O == BigEndian:
      copyMem(paddedBytes[8 - size].addr, bytes[0].addr, size)
      # Sign-extend if MSB (first byte) is negative
      if (bytes[0] and 0x80'u8) != 0:
        for i in 0 .. (8 - size - 1):
          paddedBytes[i] = 0xFF'u8
      let uintValue = fromBytesBE(uint64, paddedBytes)
      return cast[int32](uintValue)
  elif E is VariableEncoding:
    let decoded = fromBytes(uint64, bytes, Leb128)
    if decoded.len <= 0:
      raise newException(BincodeError, "Cannot deserialize int32: invalid encoding")
    let zigzagDecoded = zigzagDecode(decoded.val)
    if zigzagDecoded < int32.low.int64 or zigzagDecoded > int32.high.int64:
      raise newException(BincodeError, "Cannot deserialize int32: value out of range")
    zigzagDecoded.int32

# Convenience overload with default config
func deserializeInt32*(
    data: openArray[byte],
    config: Fixed8LEConfig = standard(),
    limit: uint64 = BINCODE_SIZE_LIMIT,
): int32 {.raises: [BincodeError].} =
  deserializeInt32[FixedEncoding[8], LittleEndian, BINCODE_SIZE_LIMIT](
    data, config, limit
  )

proc serializeUint32*[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](
    stream: OutputStreamHandle, value: uint32, config: BincodeConfig[E, O, L]
) {.raises: [IOError].} =
  ## Serialize a uint32 to bincode format and write to stream.
  ##
  ## Wraps the uint32 bytes in Vec<u8> format.
  ## Format depends on config:
  ## - Fixed encoding: [length prefix] + [N-byte uint32] where N is the fixed size
  ## - Variable encoding: [length prefix] + [LEB128 uint32]
  ##
  ## Byte order applies to fixed encoding.

  when E is FixedEncoding:
    const size = E.Size
    let bytes =
      when O == LittleEndian:
        toBytesLE(value.uint64)
      elif O == BigEndian:
        toBytesBE(value.uint64)

    # Write length prefix directly to stream
    encodeLength(stream, size.uint64, config)

    # Write int bytes directly to stream (no intermediate seq allocation)
    when O == LittleEndian:
      stream.write(bytes.toOpenArray(0, size - 1))
    elif O == BigEndian:
      stream.write(bytes.toOpenArray(8 - size, 7))
  elif E is VariableEncoding:
    # Variable encoding: LEB128
    let buf = toBytes(value.uint64, Leb128)
    let leb128Len = buf.len

    # Write length prefix directly to stream
    encodeLength(stream, leb128Len.uint64, config)

    # Write LEB128 bytes directly to stream (no intermediate seq allocation)
    stream.write(buf.toOpenArray())

# Convenience overload with default config
proc serializeUint32*(
    stream: OutputStreamHandle, value: uint32, config: Fixed8LEConfig = standard()
) {.raises: [IOError].} =
  serializeUint32[FixedEncoding[8], LittleEndian, BINCODE_SIZE_LIMIT](
    stream, value, config
  )

func deserializeUint32*[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](
    data: openArray[byte], config: BincodeConfig[E, O, L], limit: uint64 = L
): uint32 {.raises: [BincodeError].} =
  ## Deserialize bincode-encoded data to a uint32.
  ##
  ## Expects Vec<u8> format.
  ## Raises `BincodeError` if deserialized data is insufficient.

  let bytes = deserialize[E, O, L](data, config, limit)
  when E is FixedEncoding:
    const size = E.Size
    if bytes.len < size:
      raise newException(BincodeError, "Cannot deserialize uint32: insufficient data")
    var paddedBytes: array[8, byte]
    when O == LittleEndian:
      copyMem(paddedBytes[0].addr, bytes[0].addr, size)
      let uintValue = fromBytesLE(uint64, paddedBytes)
      return uintValue.uint32
    elif O == BigEndian:
      copyMem(paddedBytes[8 - size].addr, bytes[0].addr, size)
      let uintValue = fromBytesBE(uint64, paddedBytes)
      return uintValue.uint32
  elif E is VariableEncoding:
    let decoded = fromBytes(uint64, bytes, Leb128)
    if decoded.len <= 0:
      raise newException(BincodeError, "Cannot deserialize uint32: invalid encoding")
    if decoded.val > uint32.high.uint64:
      raise newException(BincodeError, "Cannot deserialize uint32: value out of range")
    decoded.val.uint32

# Convenience overload with default config
func deserializeUint32*(
    data: openArray[byte],
    config: Fixed8LEConfig = standard(),
    limit: uint64 = BINCODE_SIZE_LIMIT,
): uint32 {.raises: [BincodeError].} =
  deserializeUint32[FixedEncoding[8], LittleEndian, BINCODE_SIZE_LIMIT](
    data, config, limit
  )

proc serializeInt64*[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](
    stream: OutputStreamHandle, value: int64, config: BincodeConfig[E, O, L]
) {.raises: [IOError].} =
  ## Serialize an int64 to bincode format and write to stream.
  ##
  ## Wraps the int64 bytes in Vec<u8> format.
  ## Format depends on config:
  ## - Fixed encoding: [length prefix] + [N-byte int64] where N is the fixed size
  ## - Variable encoding: [length prefix] + [LEB128 int64]
  ##
  ## Byte order applies to fixed encoding.

  when E is FixedEncoding:
    const size = E.Size
    let bytes =
      when O == LittleEndian:
        toBytesLE(value.uint64)
      elif O == BigEndian:
        toBytesBE(value.uint64)

    # Write length prefix directly to stream
    encodeLength(stream, size.uint64, config)

    # Write int bytes directly to stream (no intermediate seq allocation)
    when O == LittleEndian:
      stream.write(bytes.toOpenArray(0, size - 1))
    elif O == BigEndian:
      stream.write(bytes.toOpenArray(8 - size, 7))
  elif E is VariableEncoding:
    # Variable encoding: LEB128
    let zigzag = zigzagEncode(value)
    let buf = toBytes(zigzag, Leb128)
    let leb128Len = buf.len

    # Write length prefix directly to stream
    encodeLength(stream, leb128Len.uint64, config)

    # Write LEB128 bytes directly to stream (no intermediate seq allocation)
    stream.write(buf.toOpenArray())

# Convenience overload with default config
proc serializeInt64*(
    stream: OutputStreamHandle, value: int64, config: Fixed8LEConfig = standard()
) {.raises: [IOError].} =
  serializeInt64[FixedEncoding[8], LittleEndian, BINCODE_SIZE_LIMIT](
    stream, value, config
  )

func deserializeInt64*[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](
    data: openArray[byte], config: BincodeConfig[E, O, L], limit: uint64 = L
): int64 {.raises: [BincodeError].} =
  ## Deserialize bincode-encoded data to an int64.
  ##
  ## Expects Vec<u8> format.
  ## Raises `BincodeError` if deserialized data is insufficient.

  let bytes = deserialize[E, O, L](data, config, limit)
  when E is FixedEncoding:
    const size = E.Size
    if bytes.len < size:
      raise newException(BincodeError, "Cannot deserialize int64: insufficient data")
    var paddedBytes: array[8, byte]
    when O == LittleEndian:
      copyMem(paddedBytes[0].addr, bytes[0].addr, size)
      # Sign-extend if MSB (last byte) is negative
      if (bytes[size - 1] and 0x80'u8) != 0:
        for i in size .. 7:
          paddedBytes[i] = 0xFF'u8
      let uintValue = fromBytesLE(uint64, paddedBytes)
      return cast[int64](uintValue)
    elif O == BigEndian:
      copyMem(paddedBytes[8 - size].addr, bytes[0].addr, size)
      # Sign-extend if MSB (first byte) is negative
      if (bytes[0] and 0x80'u8) != 0:
        for i in 0 .. (8 - size - 1):
          paddedBytes[i] = 0xFF'u8
      let uintValue = fromBytesBE(uint64, paddedBytes)
      return cast[int64](uintValue)
  elif E is VariableEncoding:
    let decoded = fromBytes(uint64, bytes, Leb128)
    if decoded.len <= 0:
      raise newException(BincodeError, "Cannot deserialize int64: invalid encoding")
    zigzagDecode(decoded.val)

# Convenience overload with default config
func deserializeInt64*(
    data: openArray[byte],
    config: Fixed8LEConfig = standard(),
    limit: uint64 = BINCODE_SIZE_LIMIT,
): int64 {.raises: [BincodeError].} =
  deserializeInt64[FixedEncoding[8], LittleEndian, BINCODE_SIZE_LIMIT](
    data, config, limit
  )

{.pop.}
