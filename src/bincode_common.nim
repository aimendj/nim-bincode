# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import faststreams # Uses: memoryOutput, OutputStreamHandle, write, getOutput
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
  ## Largest fixed length-prefix width supported (``intSize`` 8). Used as a loose
  ## default for ``checkMinimumSize`` only; real prefixes follow ``config.intSize``.

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

func maxUnsignedForFixedIntSize*(size: int): uint64 {.raises: [BincodeError].} =
  ## Largest unsigned integer representable in ``size`` bytes (1, 2, 4, or 8).
  case size
  of 1:
    uint8.high.uint64
  of 2:
    uint16.high.uint64
  of 4:
    uint32.high.uint64
  of 8:
    uint64.high
  else:
    raise newException(BincodeError, "invalid fixed int size for length prefix")

proc encodeLength*(
    stream: OutputStreamHandle, length: uint64, config: BincodeConfig
) {.raises: [BincodeError, IOError].} =
  ## Encode a **container** length (``Vec``/string/byte blob prefix).
  ##
  ## - **Variable** mode (``config.intSize == 0``): Rust bincode v2-style length encoding.
  ## - **Fixed** mode (``config.intSize > 0``): writes ``config.intSize`` bytes
  ##   (unsigned, same endianness as scalars). Values larger than that width can
  ##   represent raise ``BincodeError``.
  if config.intSize > 0:
    let size = config.intSize
    let cap = maxUnsignedForFixedIntSize(size)
    if length > cap:
      raise newException(
        BincodeError,
        "Length " & $length & " exceeds maximum for " & $size & "-byte fixed prefix",
      )
    let bytes =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(length)
      of BigEndian:
        toBytesBE(length)
    case config.byteOrder
    of LittleEndian:
      stream.write(bytes.toOpenArray(0, size - 1))
    of BigEndian:
      stream.write(bytes.toOpenArray(8 - size, 7))
  else:
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

proc encodeLength*(
    length: uint64, config: BincodeConfig
): seq[byte] {.raises: [BincodeError, IOError].} =
  ## Same as `encodeLength(stream, length, config)` but returns a ``seq[byte]``.
  var stream = memoryOutput()
  encodeLength(stream, length, config)
  stream.getOutput()

func decodeLength*(
    data: openArray[byte], config: BincodeConfig
): (uint64, int) {.raises: [BincodeError].} =
  ## Decode a **container** length. Returns ``(length, bytes_consumed)``.
  ##
  ## In **fixed** mode (``config.intSize > 0``), reads ``config.intSize`` bytes as an
  ## unsigned integer (zero-extended to ``uint64``); see `encodeLength`.
  ## In **variable** mode (``intSize == 0``), uses Rust bincode v2-style markers / LEB128.
  if config.intSize > 0:
    let size = config.intSize
    if data.len < size:
      raise newException(BincodeError, "Insufficient data for length prefix")
    var padded: array[8, byte]
    let length =
      case config.byteOrder
      of LittleEndian:
        for i in 0 ..< size:
          padded[i] = data[i]
        fromBytesLE(uint64, padded)
      of BigEndian:
        for i in 0 ..< size:
          padded[8 - size + i] = data[i]
        fromBytesBE(uint64, padded)
    return (length, size)
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

proc serialize*(
    stream: OutputStreamHandle,
    data: openArray[byte],
    config: BincodeConfig = standard(),
) {.raises: [BincodeError, IOError].} =
  ## Serialize a byte sequence to bincode format and write to stream.
  ##
  ## Format depends on config:
  ## - Fixed encoding: [``intSize``-byte unsigned length] + [data bytes]
  ## - Variable encoding: [LEB128 length] + [data bytes]
  ##
  ## Byte order (little-endian/big-endian) applies to fixed encoding.
  ##
  ## Raises `BincodeError` if data exceeds the configured size limit or the length
  ## does not fit in a fixed ``config.intSize``-byte prefix.
  ## Raises `IOError` if stream write fails.
  ##
  ## Empty sequences serialize to a zero-length prefix + no data bytes.

  checkSizeLimit(data.len.uint64, config.sizeLimit)

  encodeLength(stream, data.len.uint64, config)
  if data.len > 0:
    stream.write(data)

func deserialize*(
    data: openArray[byte], config: BincodeConfig = standard()
): seq[byte] {.raises: [BincodeError].} =
  ## Deserialize bincode-encoded data to a byte sequence.
  ##
  ## Format depends on config:
  ## - Fixed encoding: [``intSize``-byte unsigned length] + [data bytes]
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

  output

{.pop.}
