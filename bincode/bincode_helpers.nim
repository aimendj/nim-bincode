# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [BincodeError], gcsafe.}

import stew/endians2
import stew/leb128
import bincode_config
import bincode_common

## Helper functions for string and integer serialization/deserialization.
##
## This module provides higher-level operations that build on top of the core
## byte serialization from `bincode_common`:
## - String serialization/deserialization (UTF-8)
## - Integer serialization/deserialization (int32, uint32, int64)

proc serializeString*(s: string, config: BincodeConfig = standard()): seq[byte] =
  ## Serialize a string to bincode format.
  ##
  ## Format depends on config:
  ## - Fixed encoding: [8-byte u64 length] + [UTF-8 bytes]
  ## - Variable encoding: [LEB128 length] + [UTF-8 bytes]
  ##
  ## The length is the UTF-8 byte count, not character count.
  ## Unicode characters are handled correctly (multi-byte UTF-8 sequences).
  ##
  ## Raises `BincodeError` if UTF-8 byte length exceeds the configured size limit.
  ##
  ## Empty strings serialize to a zero-length prefix + no data bytes.

  var utf8Bytes = newSeq[byte](s.len)
  if s.len > 0:
    copyMem(utf8Bytes[0].addr, s[0].unsafeAddr, s.len)

  serialize(utf8Bytes, config)

proc deserializeString*(
    data: openArray[byte], config: BincodeConfig = standard()
): string =
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

proc serializeInt32*(value: int32, config: BincodeConfig = standard()): seq[byte] =
  ## Serialize an int32 to bincode format.
  ##
  ## Wraps the int32 bytes in Vec<u8> format.
  ## Format depends on config:
  ## - Fixed encoding: [length prefix] + [N-byte int32] where N is config.intSize (or 4 if 0)
  ## - Variable encoding: [length prefix] + [LEB128 int32]
  ##
  ## Byte order applies to fixed encoding.

  var intBytes: seq[byte]
  if config.intSize > 0:
    let size = config.intSize
    let bytes =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(value.int64.uint64)
      of BigEndian:
        toBytesBE(value.int64.uint64)
    intBytes = newSeq[byte](size)
    case config.byteOrder
    of LittleEndian:
      copyMem(intBytes[0].addr, bytes[0].addr, size)
    of BigEndian:
      copyMem(intBytes[0].addr, bytes[8 - size].addr, size)
  else:
    let zigzag = zigzagEncode(value.int64)
    let buf = toBytes(zigzag, Leb128)
    intBytes = @(buf.toOpenArray())
  serialize(intBytes, config)

proc deserializeInt32*(
    data: openArray[byte], config: BincodeConfig = standard()
): int32 =
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

proc serializeUint32*(value: uint32, config: BincodeConfig = standard()): seq[byte] =
  ## Serialize a uint32 to bincode format.
  ##
  ## Wraps the uint32 bytes in Vec<u8> format.
  ## Format depends on config:
  ## - Fixed encoding: [length prefix] + [N-byte uint32] where N is config.fixedIntSize (or 4 if 0)
  ## - Variable encoding: [length prefix] + [LEB128 uint32]
  ##
  ## Byte order applies to fixed encoding.

  var intBytes: seq[byte]
  if config.intSize > 0:
    let size = config.intSize
    let bytes =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(value.uint64)
      of BigEndian:
        toBytesBE(value.uint64)
    intBytes = newSeq[byte](size)
    case config.byteOrder
    of LittleEndian:
      copyMem(intBytes[0].addr, bytes[0].addr, size)
    of BigEndian:
      copyMem(intBytes[0].addr, bytes[8 - size].addr, size)
  else:
    let buf = toBytes(value.uint64, Leb128)
    intBytes = @(buf.toOpenArray())
  serialize(intBytes, config)

proc deserializeUint32*(
    data: openArray[byte], config: BincodeConfig = standard()
): uint32 =
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

proc serializeInt64*(value: int64, config: BincodeConfig = standard()): seq[byte] =
  ## Serialize an int64 to bincode format.
  ##
  ## Wraps the int64 bytes in Vec<u8> format.
  ## Format depends on config:
  ## - Fixed encoding: [length prefix] + [N-byte int64] where N is config.fixedIntSize (or 8 if 0)
  ## - Variable encoding: [length prefix] + [LEB128 int64]
  ##
  ## Byte order applies to fixed encoding.

  var intBytes: seq[byte]
  if config.intSize > 0:
    let size = config.intSize
    let bytes =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(value.uint64)
      of BigEndian:
        toBytesBE(value.uint64)
    intBytes = newSeq[byte](size)
    case config.byteOrder
    of LittleEndian:
      copyMem(intBytes[0].addr, bytes[0].addr, size)
    of BigEndian:
      copyMem(intBytes[0].addr, bytes[8 - size].addr, size)
  else:
    let zigzag = zigzagEncode(value)
    let buf = toBytes(zigzag, Leb128)
    intBytes = @(buf.toOpenArray())
  serialize(intBytes, config)

proc deserializeInt64*(
    data: openArray[byte], config: BincodeConfig = standard()
): int64 =
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
