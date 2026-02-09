# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import stew/endians2
import stew/leb128
import bincode_config

## Core bincode serialization/deserialization for byte sequences.
##
## This module provides the fundamental byte-level operations for the bincode format:
## - Length prefix encoding/decoding (fixed and variable)
## - Byte sequence serialization/deserialization
## - Validation and utility functions

type BincodeError* = object of CatchableError
  ## Exception raised when bincode operations fail

const LENGTH_PREFIX_SIZE* = 8

# Rust bincode variable-length encoding constants
# Values < 251: Single byte (the value itself)
# Values 251 to 2^16-1: 0xfb + u16 LE
# Values 2^16 to 2^32-1: 0xfc + u32 LE
# Values 2^32 to 2^64-1: 0xfd + u64 LE
# Values 2^64 to 2^128-1: 0xfe + u128 LE
const RUST_BINCODE_THRESHOLD_U16* = 251'u64
const RUST_BINCODE_THRESHOLD_U32* = 65536'u64 # 2^16
const RUST_BINCODE_THRESHOLD_U64* = 4294967296'u64 # 2^32
const RUST_BINCODE_MARKER_U16* = 0xfb'u8
const RUST_BINCODE_MARKER_U32* = 0xfc'u8
const RUST_BINCODE_MARKER_U64* = 0xfd'u8
const RUST_BINCODE_MARKER_U128* = 0xfe'u8

proc checkSizeLimit*(size: uint64, limit: uint64 = BINCODE_SIZE_LIMIT) =
  ## Check if size exceeds the specified limit.
  ## Raises `BincodeError` if size exceeds limit.
  if size > limit:
    raise newException(BincodeError, "Data exceeds size limit")

proc checkMinimumSize*(dataLen: int, required: int = LENGTH_PREFIX_SIZE) =
  ## Check if data length meets minimum requirement.
  ## Raises `BincodeError` if data is insufficient.
  if dataLen < required:
    raise newException(BincodeError, "Insufficient data for length prefix")

proc checkLengthLimit*(length: uint64, limit: uint64 = BINCODE_SIZE_LIMIT) =
  ## Check if decoded length exceeds the specified limit.
  ## Raises `BincodeError` if length exceeds limit.
  if length > limit:
    raise newException(BincodeError, "Length exceeds size limit")

proc checkSufficientData*(dataLen: int, prefixSize: int, length: int) =
  ## Check if data has sufficient bytes for the decoded length.
  ## Raises `BincodeError` if insufficient data.
  if dataLen < prefixSize + length:
    raise newException(BincodeError, "Insufficient data for content")

proc checkNoTrailingBytes*(dataLen: int, prefixSize: int, length: int) =
  ## Check if there are no trailing bytes after the expected data.
  ## Raises `BincodeError` if trailing bytes detected.
  if dataLen != prefixSize + length:
    raise newException(BincodeError, "Trailing bytes detected")

func zigzagEncode*(value: int64): uint64 =
  ## Encode a signed integer using zigzag encoding for LEB128.
  ## Zigzag encoding maps signed integers to unsigned integers:
  ## 0 -> 0, -1 -> 1, 1 -> 2, -2 -> 3, 2 -> 4, etc.
  if value >= 0:
    (value.uint64 shl 1)
  else:
    ((not value.uint64) shl 1) or 1

func zigzagDecode*(value: uint64): int64 =
  ## Decode a zigzag-encoded unsigned integer back to a signed integer.
  if (value and 1) == 0:
    (value shr 1).int64
  else:
    not ((value shr 1).int64)

func encodeLength*(length: uint64, config: BincodeConfig): seq[byte] =
  ## Encode a length value according to the config's integer encoding.
  if config.intSize > 0:
    case config.byteOrder
    of LittleEndian:
      let bytes = toBytesLE(length)
      return
        @[
          bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7]
        ]
    of BigEndian:
      let bytes = toBytesBE(length)
      return
        @[
          bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7]
        ]
  else:
    # Variable encoding: Rust bincode uses special encoding
    # Note: RUST_BINCODE_MARKER_U128 (0xfe) is not used in encoding since length is uint64 (max 2^64-1)
    if length < RUST_BINCODE_THRESHOLD_U16:
      # Single byte: the value itself
      return @[length.byte]
    elif length < RUST_BINCODE_THRESHOLD_U32:
      # 0xfb + u16 little-endian
      let u16Value = length.uint16
      let bytes = toBytesLE(u16Value)
      return @[RUST_BINCODE_MARKER_U16, bytes[0], bytes[1]]
    elif length < RUST_BINCODE_THRESHOLD_U64:
      # 0xfc + u32 little-endian
      let u32Value = length.uint32
      let bytes = toBytesLE(u32Value)
      return @[RUST_BINCODE_MARKER_U32, bytes[0], bytes[1], bytes[2], bytes[3]]
    else:
      # 0xfd + u64 little-endian
      # Note: We never use 0xfe (u128) in encoding since length is uint64 (max 2^64-1)
      let bytes = toBytesLE(length)
      return
        @[
          RUST_BINCODE_MARKER_U64,
          bytes[0],
          bytes[1],
          bytes[2],
          bytes[3],
          bytes[4],
          bytes[5],
          bytes[6],
          bytes[7],
        ]

proc decodeLength*(data: openArray[byte], config: BincodeConfig): (uint64, int) =
  ## Decode a length value according to the config's integer encoding.
  ## Returns (length, bytes_consumed).
  ##
  ## For variable encoding, Rust's bincode uses a special encoding:
  ## - Values < 16384: Standard LEB128
  ## - Values >= 16384: 0xfb marker byte + u16 little-endian (3 bytes total)
  if config.intSize > 0:
    if data.len < LENGTH_PREFIX_SIZE:
      raise newException(BincodeError, "Insufficient data for length prefix")
    var lengthBytes: array[LENGTH_PREFIX_SIZE, byte]
    for i in 0 ..< LENGTH_PREFIX_SIZE:
      lengthBytes[i] = data[i]
    let length =
      case config.byteOrder
      of LittleEndian:
        fromBytesLE(uint64, lengthBytes)
      of BigEndian:
        fromBytesBE(uint64, lengthBytes)
    return (length, LENGTH_PREFIX_SIZE)
  else:
    # Variable encoding: Rust bincode uses special encoding
    # Check for marker bytes: 0xfb (u16), 0xfc (u32), 0xfd (u64), 0xfe (u128)
    if data.len == 0:
      raise newException(BincodeError, "Insufficient data for length prefix")

    let firstByte = data[0]

    if firstByte < RUST_BINCODE_MARKER_U16:
      # Single byte: the value itself
      return (firstByte.uint64, 1)
    elif firstByte == RUST_BINCODE_MARKER_U16:
      # 0xfb + u16 little-endian
      if data.len < 3:
        raise newException(BincodeError, "Insufficient data for u16 length prefix")
      var u16Bytes: array[2, byte]
      u16Bytes[0] = data[1]
      u16Bytes[1] = data[2]
      let length = fromBytesLE(uint16, u16Bytes).uint64
      return (length, 3)
    elif firstByte == RUST_BINCODE_MARKER_U32:
      # 0xfc + u32 little-endian
      if data.len < 5:
        raise newException(BincodeError, "Insufficient data for u32 length prefix")
      var u32Bytes: array[4, byte]
      for i in 0 ..< 4:
        u32Bytes[i] = data[i + 1]
      let length = fromBytesLE(uint32, u32Bytes).uint64
      return (length, 5)
    elif firstByte == RUST_BINCODE_MARKER_U64:
      # 0xfd + u64 little-endian
      if data.len < 9:
        raise newException(BincodeError, "Insufficient data for u64 length prefix")
      var u64Bytes: array[8, byte]
      for i in 0 ..< 8:
        u64Bytes[i] = data[i + 1]
      let length = fromBytesLE(uint64, u64Bytes)
      return (length, 9)
    elif firstByte == RUST_BINCODE_MARKER_U128:
      # 0xfe + u128 little-endian
      # Since we return uint64, we can only handle values < 2^64
      if data.len < 17:
        raise newException(BincodeError, "Insufficient data for u128 length prefix")
      # Check if high 8 bytes are all zero (value fits in u64)
      var allZero = true
      for i in 8 ..< 16:
        if data[i + 1] != 0:
          allZero = false
          break
      if not allZero:
        raise newException(BincodeError, "Length value exceeds uint64 maximum (2^64-1)")
      # Extract low 8 bytes as u64
      var u64Bytes: array[8, byte]
      for i in 0 ..< 8:
        u64Bytes[i] = data[i + 1]
      let length = fromBytesLE(uint64, u64Bytes)
      return (length, 17)
    else:
      # Standard LEB128 encoding (for values that don't use markers)
      # This shouldn't happen with Rust bincode, but keep for compatibility
      let decoded = fromBytes(uint64, data, Leb128)
      if decoded.len <= 0:
        raise newException(BincodeError, "Failed to decode variable-length integer")
      return (decoded.val, decoded.len.int)

proc serialize*(data: openArray[byte], config: BincodeConfig = standard()): seq[byte] =
  ## Serialize a byte sequence to bincode format.
  ##
  ## Format depends on config:
  ## - Fixed encoding: [8-byte u64 length] + [data bytes]
  ## - Variable encoding: [LEB128 length] + [data bytes]
  ##
  ## Byte order (little-endian/big-endian) applies to fixed encoding.
  ##
  ## Raises `BincodeError` if data exceeds the configured size limit.
  ##
  ## Empty sequences serialize to a zero-length prefix + no data bytes.

  checkSizeLimit(data.len.uint64, config.sizeLimit)

  let lengthPrefix = encodeLength(data.len.uint64, config)

  var output = newSeq[byte](lengthPrefix.len + data.len)
  copyMem(output[0].addr, lengthPrefix[0].addr, lengthPrefix.len)
  if data.len > 0:
    copyMem(output[lengthPrefix.len].addr, data[0].unsafeAddr, data.len)
  return output

proc deserialize*(
    data: openArray[byte], config: BincodeConfig = standard()
): seq[byte] =
  ## Deserialize bincode-encoded data to a byte sequence.
  ##
  ## Format depends on config:
  ## - Fixed encoding: [8-byte u64 length] + [data bytes]
  ## - Variable encoding: [LEB128 length] + [data bytes]
  ##
  ## Byte order (little-endian/big-endian) applies to fixed encoding.
  ##
  ## Raises `BincodeError` if:
  ## - Data is insufficient for length prefix
  ## - Length exceeds the configured size limit
  ## - Length value exceeds maximum int size (prevents integer overflow)
  ## - Insufficient data for content
  ## - Trailing bytes detected (all input bytes must be consumed)

  checkMinimumSize(data.len, 1)

  let (lengthValue, prefixSize) = decodeLength(data, config)

  checkLengthLimit(lengthValue, config.sizeLimit)

  # Check for integer overflow when converting uint64 to int
  # On 32-bit platforms, int.high is 2^31-1, so values > int.high would overflow
  if lengthValue > int.high.uint64:
    raise newException(BincodeError, "Length value exceeds maximum int size")

  let length = lengthValue.int
  checkSufficientData(data.len, prefixSize, length)

  var output = newSeq[byte](length)
  if length > 0:
    copyMem(output[0].addr, data[prefixSize].unsafeAddr, length)

  checkNoTrailingBytes(data.len, prefixSize, length)

  return output

{.pop.}
