# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import faststreams # Uses: memoryOutput, OutputStreamHandle, write, getOutput
# Note: Deserialization optimized with copyMem for efficient memory access (faststreams-style optimization)
import stew/[endians2, leb128]
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

func checkSizeLimit*(
    size: uint64, limit: uint64 = BINCODE_SIZE_LIMIT
) {.raises: [BincodeError].} =
  ## Check if size exceeds the specified limit.
  ## Raises `BincodeError` if size exceeds limit.
  if size > limit:
    raise newException(BincodeError, "Data exceeds size limit")

func checkMinimumSize*(
    dataLen: int, required: int = LENGTH_PREFIX_SIZE
) {.raises: [BincodeError].} =
  ## Check if data length meets minimum requirement.
  ## Raises `BincodeError` if data is insufficient.
  if dataLen < required:
    raise newException(BincodeError, "Insufficient data for length prefix")

func checkLengthLimit*(
    length: uint64, limit: uint64 = BINCODE_SIZE_LIMIT
) {.raises: [BincodeError].} =
  ## Check if decoded length exceeds the specified limit.
  ## Raises `BincodeError` if length exceeds limit.
  if length > limit:
    raise newException(BincodeError, "Length exceeds size limit")

func checkSufficientData*(
    dataLen: int, prefixSize: int, length: int
) {.raises: [BincodeError].} =
  ## Check if data has sufficient bytes for the decoded length.
  ## Raises `BincodeError` if insufficient data.
  if dataLen < prefixSize + length:
    raise newException(BincodeError, "Insufficient data for content")

func checkNoTrailingBytes*(
    dataLen: int, prefixSize: int, length: int
) {.raises: [BincodeError].} =
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

proc encodeLength*[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](
    stream: OutputStreamHandle, length: uint64, config: BincodeConfig[E, O, L]
) {.raises: [IOError].} =
  ## Encode a length value according to the config's integer encoding and write to stream.
  when E is VariableEncoding:
    # Variable encoding: Rust bincode uses special encoding
    # Note: RUST_BINCODE_MARKER_U128 (0xfe) is not used in encoding since length is uint64 (max 2^64-1)
    if length < RUST_BINCODE_THRESHOLD_U16:
      # Single byte: the value itself
      stream.write(length.byte)
    elif length < RUST_BINCODE_THRESHOLD_U32:
      # 0xfb + u16 little-endian
      let u16Value = length.uint16
      let bytes = toBytesLE(u16Value)
      stream.write(RUST_BINCODE_MARKER_U16)
      stream.write(bytes.toOpenArray(0, bytes.high))
    elif length < RUST_BINCODE_THRESHOLD_U64:
      # 0xfc + u32 little-endian
      let u32Value = length.uint32
      let bytes = toBytesLE(u32Value)
      stream.write(RUST_BINCODE_MARKER_U32)
      stream.write(bytes.toOpenArray(0, bytes.high))
    else:
      # 0xfd + u64 little-endian
      # Note: We never use 0xfe (u128) in encoding since length is uint64 (max 2^64-1)
      let bytes = toBytesLE(length)
      stream.write(RUST_BINCODE_MARKER_U64)
      stream.write(bytes.toOpenArray(0, bytes.high))
  elif E is FixedEncoding:
    when O == LittleEndian:
      let bytes = toBytesLE(length)
      stream.write(bytes.toOpenArray(0, bytes.high))
    elif O == BigEndian:
      let bytes = toBytesBE(length)
      stream.write(bytes.toOpenArray(0, bytes.high))

proc encodeLength*[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](length: uint64, config: BincodeConfig[E, O, L]): seq[byte] {.raises: [IOError].} =
  ## Encode a length value according to the config's integer encoding.
  ## Returns a sequence (for backward compatibility).
  var stream = memoryOutput()
  encodeLength(stream, length, config)
  stream.getOutput()

func decodeLength*[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](
    data: openArray[byte], config: BincodeConfig[E, O, L]
): (uint64, int) {.raises: [BincodeError].} =
  ## Decode a length value according to the config's integer encoding.
  ## Returns (length, bytes_consumed).
  ##
  ## For variable encoding, Rust's bincode uses a special encoding:
  ## - Values < 16384: Standard LEB128
  ## - Values >= 16384: 0xfb marker byte + u16 little-endian (3 bytes total)
  when E is FixedEncoding:
    if data.len < LENGTH_PREFIX_SIZE:
      raise newException(BincodeError, "Insufficient data for length prefix")
    var lengthBytes: array[LENGTH_PREFIX_SIZE, byte]
    # Use copyMem for efficient copying instead of loop
    copyMem(lengthBytes[0].addr, data[0].unsafeAddr, LENGTH_PREFIX_SIZE)
    when O == LittleEndian:
      let length = fromBytesLE(uint64, lengthBytes)
      return (length, LENGTH_PREFIX_SIZE)
    elif O == BigEndian:
      let length = fromBytesBE(uint64, lengthBytes)
      return (length, LENGTH_PREFIX_SIZE)
  elif E is VariableEncoding:
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
      # Use copyMem for efficient copying instead of individual assignments
      copyMem(u16Bytes[0].addr, data[1].unsafeAddr, 2)
      let length = fromBytesLE(uint16, u16Bytes).uint64
      return (length, 3)
    elif firstByte == RUST_BINCODE_MARKER_U32:
      # 0xfc + u32 little-endian
      if data.len < 5:
        raise newException(BincodeError, "Insufficient data for u32 length prefix")
      var u32Bytes: array[4, byte]
      # Use copyMem for efficient copying instead of loop
      copyMem(u32Bytes[0].addr, data[1].unsafeAddr, 4)
      let length = fromBytesLE(uint32, u32Bytes).uint64
      return (length, 5)
    elif firstByte == RUST_BINCODE_MARKER_U64:
      # 0xfd + u64 little-endian
      if data.len < 9:
        raise newException(BincodeError, "Insufficient data for u64 length prefix")
      var u64Bytes: array[8, byte]
      # Use copyMem for efficient copying instead of loop
      copyMem(u64Bytes[0].addr, data[1].unsafeAddr, 8)
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
      # Use copyMem for efficient copying instead of loop
      copyMem(u64Bytes[0].addr, data[1].unsafeAddr, 8)
      let length = fromBytesLE(uint64, u64Bytes)
      return (length, 17)
    elif firstByte == 0xff'u8:
      # 0xff is not a valid marker byte in Rust bincode v2
      # Only markers 0xfb-0xfe are valid
      raise newException(
        BincodeError, "Invalid marker byte 0xff in variable-length encoding"
      )
    else:
      # Values >= 0xfa and < 0xfb should not occur in Rust bincode encoding
      # Standard LEB128 encoding (for values that don't use markers)
      # This shouldn't happen with Rust bincode, but keep for compatibility
      let decoded = fromBytes(uint64, data, Leb128)
      if decoded.len <= 0:
        raise newException(BincodeError, "Failed to decode variable-length integer")
      return (decoded.val, decoded.len.int)

proc serialize*[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](
    stream: OutputStreamHandle,
    data: openArray[byte],
    config: BincodeConfig[E, O, L],
    limit: uint64 = L,
) {.raises: [BincodeError, IOError].} =
  ## Serialize a byte sequence to bincode format and write to stream.
  ##
  ## Format depends on config:
  ## - Fixed encoding: [8-byte u64 length] + [data bytes]
  ## - Variable encoding: [LEB128 length] + [data bytes]
  ##
  ## Byte order (little-endian/big-endian) applies to fixed encoding.
  ##
  ## `limit` is the maximum size limit (defaults to compile-time `L`).
  ## Pass a runtime `limit` for dynamic limits (e.g., in benchmarks).
  ##
  ## Raises `BincodeError` if data exceeds the specified size limit.
  ## Raises `IOError` if stream write fails.
  ##
  ## Empty sequences serialize to a zero-length prefix + no data bytes.

  checkSizeLimit(data.len.uint64, limit)

  encodeLength(stream, data.len.uint64, config)
  if data.len > 0:
    stream.write(data)

# Convenience overload with default config
proc serialize*(
    stream: OutputStreamHandle,
    data: openArray[byte],
    config: Fixed8LEConfig = standard(),
    limit: uint64 = BINCODE_SIZE_LIMIT,
) {.raises: [BincodeError, IOError].} =
  serialize[FixedEncoding[8], LittleEndian, BINCODE_SIZE_LIMIT](
    stream, data, config, limit
  )

func deserialize*[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](
    data: openArray[byte], config: BincodeConfig[E, O, L], limit: uint64 = L
): seq[byte] {.raises: [BincodeError].} =
  ## Deserialize bincode-encoded data to a byte sequence.
  ##
  ## Format depends on config:
  ## - Fixed encoding: [8-byte u64 length] + [data bytes]
  ## - Variable encoding: [LEB128 length] + [data bytes]
  ##
  ## Byte order (little-endian/big-endian) applies to fixed encoding.
  ##
  ## `limit` is the maximum size limit (defaults to compile-time `L`).
  ## Pass a runtime `limit` for dynamic limits (e.g., in benchmarks).
  ##
  ## Raises `BincodeError` if:
  ## - Data is insufficient for length prefix
  ## - Length exceeds the specified size limit
  ## - Length value exceeds maximum int size (prevents integer overflow)
  ## - Insufficient data for content
  ## - Trailing bytes detected (all input bytes must be consumed)
  ##
  ## This function uses faststreams-style optimizations (efficient copyMem operations)
  ## for improved performance, similar to how faststreams optimizes serialization.

  checkMinimumSize(data.len, 1)

  let (lengthValue, prefixSize) = decodeLength(data, config)

  checkLengthLimit(lengthValue, limit)

  # Check for integer overflow when converting uint64 to int
  # On 32-bit platforms, int.high is 2^31-1, so values > int.high would overflow
  if lengthValue > int.high.uint64:
    raise newException(BincodeError, "Length value exceeds maximum int size")

  let length = lengthValue.int
  checkSufficientData(data.len, prefixSize, length)

  # Use copyMem for efficient memory copying (faststreams-style optimization)
  var output = newSeq[byte](length)
  if length > 0:
    copyMem(output[0].addr, data[prefixSize].unsafeAddr, length)

  checkNoTrailingBytes(data.len, prefixSize, length)

  output

# Convenience overload with default config
func deserialize*(
    data: openArray[byte],
    config: Fixed8LEConfig = standard(),
    limit: uint64 = BINCODE_SIZE_LIMIT,
): seq[byte] {.raises: [BincodeError].} =
  deserialize[FixedEncoding[8], LittleEndian, BINCODE_SIZE_LIMIT](data, config, limit)

{.pop.}
