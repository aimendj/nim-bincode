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

proc serializeString*(
    stream: OutputStreamHandle, s: string, config: BincodeConfig = standard()
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
  ## Raises `BincodeError` if UTF-8 byte length exceeds the configured size limit.
  ## Raises `IOError` if stream write fails.
  ##
  ## Empty strings serialize to a zero-length prefix + no data bytes.

  checkSizeLimit(s.len.uint64, config.sizeLimit)

  # Write length prefix directly to stream
  encodeLength(stream, s.len.uint64, config)

  # Write string bytes directly to stream (no intermediate allocation)
  if s.len > 0:
    # Strings in Nim are UTF-8, so we can write the underlying bytes directly
    stream.write(s.toOpenArray(0, s.high))

func deserializeString*(
    data: openArray[byte], config: BincodeConfig = standard()
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
  ## Raises `BincodeError` if:
  ## - Data is insufficient for length prefix
  ## - Length exceeds the configured size limit
  ## - Insufficient data for content
  ## - Trailing bytes detected
  ## - Invalid UTF-8 encoding

  let bytes = deserialize(data, config)

  if bytes.len == 0:
    return ""

  var output = newString(bytes.len)
  copyMem(output[0].addr, bytes[0].addr, bytes.len)
  output

proc serializeInt32*(
    stream: OutputStreamHandle, value: int32, config: BincodeConfig = standard()
) {.raises: [IOError].} =
  ## Serialize an int32 to bincode format and write to stream.
  ##
  ## Wraps the int32 bytes in Vec<u8> format.
  ## Format depends on config:
  ## - Fixed encoding: [length prefix] + [N-byte int32] where N is config.intSize (or 4 if 0)
  ## - Variable encoding: [length prefix] + [LEB128 int32]
  ##
  ## Byte order applies to fixed encoding.

  if config.intSize > 0:
    let size = config.intSize
    let bytes =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(value.int64.uint64)
      of BigEndian:
        toBytesBE(value.int64.uint64)

    # Write length prefix directly to stream
    encodeLength(stream, size.uint64, config)

    # Write int bytes directly to stream (no intermediate seq allocation)
    case config.byteOrder
    of LittleEndian:
      stream.write(bytes.toOpenArray(0, size - 1))
    of BigEndian:
      stream.write(bytes.toOpenArray(8 - size, 7))
  else:
    # Variable encoding: LEB128
    let zigzag = zigzagEncode(value.int64)
    let buf = toBytes(zigzag, Leb128)
    let leb128Len = buf.len

    # Write length prefix directly to stream
    encodeLength(stream, leb128Len.uint64, config)

    # Write LEB128 bytes directly to stream (no intermediate seq allocation)
    stream.write(buf.toOpenArray())

func deserializeInt32*(
    data: openArray[byte], config: BincodeConfig = standard()
): int32 {.raises: [BincodeError].} =
  ## Deserialize bincode-encoded data to an int32.
  ##
  ## Expects Vec<u8> format.
  ## Raises `BincodeError` if deserialized data is insufficient.

  let bytes = deserialize(data, config)
  if config.intSize > 0:
    let size = config.intSize
    if bytes.len < size:
      raise newException(BincodeError, "Cannot deserialize int32: insufficient data")
    var paddedBytes: array[8, byte]
    case config.byteOrder
    of LittleEndian:
      copyMem(paddedBytes[0].addr, bytes[0].addr, size)
      let uintValue = fromBytesLE(uint64, paddedBytes)
      return cast[int32](uintValue)
    of BigEndian:
      copyMem(paddedBytes[8 - size].addr, bytes[0].addr, size)
      let uintValue = fromBytesBE(uint64, paddedBytes)
      return cast[int32](uintValue)
  else:
    let decoded = fromBytes(uint64, bytes, Leb128)
    if decoded.len <= 0:
      raise newException(BincodeError, "Cannot deserialize int32: invalid encoding")
    let zigzagDecoded = zigzagDecode(decoded.val)
    if zigzagDecoded < int32.low.int64 or zigzagDecoded > int32.high.int64:
      raise newException(BincodeError, "Cannot deserialize int32: value out of range")
    return zigzagDecoded.int32

proc serializeUint32*(
    stream: OutputStreamHandle, value: uint32, config: BincodeConfig = standard()
) {.raises: [IOError].} =
  ## Serialize a uint32 to bincode format and write to stream.
  ##
  ## Wraps the uint32 bytes in Vec<u8> format.
  ## Format depends on config:
  ## - Fixed encoding: [length prefix] + [N-byte uint32] where N is config.fixedIntSize (or 4 if 0)
  ## - Variable encoding: [length prefix] + [LEB128 uint32]
  ##
  ## Byte order applies to fixed encoding.

  if config.intSize > 0:
    let size = config.intSize
    let bytes =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(value.uint64)
      of BigEndian:
        toBytesBE(value.uint64)

    # Write length prefix directly to stream
    encodeLength(stream, size.uint64, config)

    # Write int bytes directly to stream (no intermediate seq allocation)
    case config.byteOrder
    of LittleEndian:
      stream.write(bytes.toOpenArray(0, size - 1))
    of BigEndian:
      stream.write(bytes.toOpenArray(8 - size, 7))
  else:
    # Variable encoding: LEB128
    let buf = toBytes(value.uint64, Leb128)
    let leb128Len = buf.len

    # Write length prefix directly to stream
    encodeLength(stream, leb128Len.uint64, config)

    # Write LEB128 bytes directly to stream (no intermediate seq allocation)
    stream.write(buf.toOpenArray())

func deserializeUint32*(
    data: openArray[byte], config: BincodeConfig = standard()
): uint32 {.raises: [BincodeError].} =
  ## Deserialize bincode-encoded data to a uint32.
  ##
  ## Expects Vec<u8> format.
  ## Raises `BincodeError` if deserialized data is insufficient.

  let bytes = deserialize(data, config)
  if config.intSize > 0:
    let size = config.intSize
    if bytes.len < size:
      raise newException(BincodeError, "Cannot deserialize uint32: insufficient data")
    var paddedBytes: array[8, byte]
    case config.byteOrder
    of LittleEndian:
      copyMem(paddedBytes[0].addr, bytes[0].addr, size)
      let uintValue = fromBytesLE(uint64, paddedBytes)
      return uintValue.uint32
    of BigEndian:
      copyMem(paddedBytes[8 - size].addr, bytes[0].addr, size)
      let uintValue = fromBytesBE(uint64, paddedBytes)
      return uintValue.uint32
  else:
    let decoded = fromBytes(uint64, bytes, Leb128)
    if decoded.len <= 0:
      raise newException(BincodeError, "Cannot deserialize uint32: invalid encoding")
    if decoded.val > uint32.high.uint64:
      raise newException(BincodeError, "Cannot deserialize uint32: value out of range")
    return decoded.val.uint32

proc serializeInt64*(
    stream: OutputStreamHandle, value: int64, config: BincodeConfig = standard()
) {.raises: [IOError].} =
  ## Serialize an int64 to bincode format and write to stream.
  ##
  ## Wraps the int64 bytes in Vec<u8> format.
  ## Format depends on config:
  ## - Fixed encoding: [length prefix] + [N-byte int64] where N is config.fixedIntSize (or 8 if 0)
  ## - Variable encoding: [length prefix] + [LEB128 int64]
  ##
  ## Byte order applies to fixed encoding.

  if config.intSize > 0:
    let size = config.intSize
    let bytes =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(value.uint64)
      of BigEndian:
        toBytesBE(value.uint64)

    # Write length prefix directly to stream
    encodeLength(stream, size.uint64, config)

    # Write int bytes directly to stream (no intermediate seq allocation)
    case config.byteOrder
    of LittleEndian:
      stream.write(bytes.toOpenArray(0, size - 1))
    of BigEndian:
      stream.write(bytes.toOpenArray(8 - size, 7))
  else:
    # Variable encoding: LEB128
    let zigzag = zigzagEncode(value)
    let buf = toBytes(zigzag, Leb128)
    let leb128Len = buf.len

    # Write length prefix directly to stream
    encodeLength(stream, leb128Len.uint64, config)

    # Write LEB128 bytes directly to stream (no intermediate seq allocation)
    stream.write(buf.toOpenArray())

func deserializeInt64*(
    data: openArray[byte], config: BincodeConfig = standard()
): int64 {.raises: [BincodeError].} =
  ## Deserialize bincode-encoded data to an int64.
  ##
  ## Expects Vec<u8> format.
  ## Raises `BincodeError` if deserialized data is insufficient.

  let bytes = deserialize(data, config)
  if config.intSize > 0:
    let size = config.intSize
    if bytes.len < size:
      raise newException(BincodeError, "Cannot deserialize int64: insufficient data")
    var paddedBytes: array[8, byte]
    case config.byteOrder
    of LittleEndian:
      copyMem(paddedBytes[0].addr, bytes[0].addr, size)
      let uintValue = fromBytesLE(uint64, paddedBytes)
      return cast[int64](uintValue)
    of BigEndian:
      copyMem(paddedBytes[8 - size].addr, bytes[0].addr, size)
      let uintValue = fromBytesBE(uint64, paddedBytes)
      return cast[int64](uintValue)
  else:
    let decoded = fromBytes(uint64, bytes, Leb128)
    if decoded.len <= 0:
      raise newException(BincodeError, "Cannot deserialize int64: invalid encoding")
    return zigzagDecode(decoded.val)

{.pop.}
