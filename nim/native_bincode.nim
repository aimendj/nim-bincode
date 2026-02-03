{.push raises: [BincodeError], gcsafe.}

import stew/endians2

type
  BincodeError* = object of CatchableError
    ## Exception raised when bincode operations fail

const BINCODE_SIZE_LIMIT* = 65536'u64
const LENGTH_PREFIX_SIZE* = 8
const INT32_SIZE* = 4
const INT64_SIZE* = 8

proc checkSizeLimit*(size: uint64) {.raises: [BincodeError].} =
  ## Check if size exceeds the 64 KiB limit.
  ## Raises `BincodeError` if size exceeds limit.
  if size > BINCODE_SIZE_LIMIT:
    raise newException(BincodeError, "Data exceeds 64 KiB limit")

proc checkMinimumSize*(dataLen: int, required: int = LENGTH_PREFIX_SIZE) {.raises: [
    BincodeError].} =
  ## Check if data length meets minimum requirement.
  ## Raises `BincodeError` if data is insufficient.
  if dataLen < required:
    raise newException(BincodeError, "Insufficient data for length prefix")

proc checkLengthLimit*(length: uint64) {.raises: [BincodeError].} =
  ## Check if decoded length exceeds the 64 KiB limit.
  ## Raises `BincodeError` if length exceeds limit.
  if length > BINCODE_SIZE_LIMIT:
    raise newException(BincodeError, "Length exceeds 64 KiB limit")

proc checkSufficientData*(dataLen: int, length: int) {.raises: [
    BincodeError].} =
  ## Check if data has sufficient bytes for the decoded length.
  ## Raises `BincodeError` if insufficient data.
  if dataLen < LENGTH_PREFIX_SIZE + length:
    raise newException(BincodeError, "Insufficient data for content")

proc checkNoTrailingBytes*(dataLen: int, length: int) {.raises: [
    BincodeError].} =
  ## Check if there are no trailing bytes after the expected data.
  ## Raises `BincodeError` if trailing bytes detected.
  if dataLen != LENGTH_PREFIX_SIZE + length:
    raise newException(BincodeError, "Trailing bytes detected")

proc serialize*(data: openArray[byte]): seq[byte] {.raises: [BincodeError].} =
  ## Serialize a byte sequence to bincode format.
  ##
  ## Format: [8-byte u64 length (little-endian)] + [data bytes]
  ##
  ## Raises `BincodeError` if data exceeds 64 KiB limit.
  ##
  ## Empty sequences serialize to 8 zero bytes (length = 0).

  checkSizeLimit(data.len.uint64)

  let lengthBytes = toBytesLE(data.len.uint64)

  result = newSeq[byte](LENGTH_PREFIX_SIZE + data.len)
  copyMem(result[0].addr, lengthBytes[0].addr, LENGTH_PREFIX_SIZE)
  if data.len > 0:
    copyMem(result[LENGTH_PREFIX_SIZE].addr, data[0].unsafeAddr, data.len)

proc deserialize*(data: openArray[byte]): seq[byte] {.raises: [BincodeError].} =
  ## Deserialize bincode-encoded data to a byte sequence.
  ##
  ## Format: [8-byte u64 length (little-endian)] + [data bytes]
  ##
  ## Raises `BincodeError` if:
  ## - Data is insufficient for length prefix (< 8 bytes)
  ## - Length exceeds 64 KiB limit
  ## - Insufficient data for content
  ## - Trailing bytes detected (all input bytes must be consumed)

  checkMinimumSize(data.len)

  var lengthBytes: array[LENGTH_PREFIX_SIZE, byte]
  for i in 0..<LENGTH_PREFIX_SIZE:
    lengthBytes[i] = data[i]
  let length = fromBytesLE(uint64, lengthBytes).int

  checkLengthLimit(length.uint64)
  checkSufficientData(data.len, length)

  result = newSeq[byte](length)
  if length > 0:
    copyMem(result[0].addr, data[LENGTH_PREFIX_SIZE].unsafeAddr, length)

  checkNoTrailingBytes(data.len, length)

proc serializeString*(s: string): seq[byte] {.raises: [BincodeError].} =
  ## Serialize a string to bincode format.
  ##
  ## Format: [8-byte u64 length (little-endian)] + [UTF-8 bytes]
  ##
  ## The length is the UTF-8 byte count, not character count.
  ## Unicode characters are handled correctly (multi-byte UTF-8 sequences).
  ##
  ## Raises `BincodeError` if UTF-8 byte length exceeds 64 KiB limit.
  ##
  ## Empty strings serialize to 8 zero bytes (length = 0).

  var utf8Bytes = newSeq[byte](s.len)
  if s.len > 0:
    copyMem(utf8Bytes[0].addr, s[0].unsafeAddr, s.len)

  result = serialize(utf8Bytes)

proc deserializeString*(data: openArray[byte]): string {.raises: [
    BincodeError].} =
  ## Deserialize bincode-encoded data to a string.
  ##
  ## Format: [8-byte u64 length (little-endian)] + [UTF-8 bytes]
  ##
  ## The length is the UTF-8 byte count, not character count.
  ## Unicode characters are handled correctly (multi-byte UTF-8 sequences).
  ##
  ## Raises `BincodeError` if:
  ## - Data is insufficient for length prefix (< 8 bytes)
  ## - Length exceeds 64 KiB limit
  ## - Insufficient data for content
  ## - Trailing bytes detected
  ## - Invalid UTF-8 encoding

  let bytes = deserialize(data)

  if bytes.len == 0:
    return ""

  result = newString(bytes.len)
  copyMem(result[0].addr, bytes[0].addr, bytes.len)

proc serializeInt32*(value: int32): seq[byte] {.raises: [BincodeError].} =
  ## Serialize an int32 to bincode format.
  ##
  ## Wraps the int32 bytes in Vec<u8> format (8-byte length prefix + 4-byte data).
  ## Format: [8-byte u64 length (little-endian)] + [4-byte int32 (little-endian, two's complement)]

  let bytes = toBytesLE(value.uint32)
  result = serialize(@[bytes[0], bytes[1], bytes[2], bytes[3]])

proc deserializeInt32*(data: openArray[byte]): int32 {.raises: [
    BincodeError].} =
  ## Deserialize bincode-encoded data to an int32.
  ##
  ## Expects Vec<u8> format (8-byte length prefix + 4-byte data).
  ## Raises `BincodeError` if deserialized data is insufficient (< 4 bytes).

  let bytes = deserialize(data)
  if bytes.len < INT32_SIZE:
    raise newException(BincodeError, "Cannot deserialize int32: insufficient data")
  result = cast[int32](fromBytesLE(uint32, bytes))

proc serializeUint32*(value: uint32): seq[byte] {.raises: [BincodeError].} =
  ## Serialize a uint32 to bincode format.
  ##
  ## Wraps the uint32 bytes in Vec<u8> format (8-byte length prefix + 4-byte data).
  ## Format: [8-byte u64 length (little-endian)] + [4-byte uint32 (little-endian)]

  let bytes = toBytesLE(value)
  result = serialize(@[bytes[0], bytes[1], bytes[2], bytes[3]])

proc deserializeUint32*(data: openArray[byte]): uint32 {.raises: [
    BincodeError].} =
  ## Deserialize bincode-encoded data to a uint32.
  ##
  ## Expects Vec<u8> format (8-byte length prefix + 4-byte data).
  ## Raises `BincodeError` if deserialized data is insufficient (< 4 bytes).

  let bytes = deserialize(data)
  if bytes.len < INT32_SIZE:
    raise newException(BincodeError, "Cannot deserialize uint32: insufficient data")
  result = fromBytesLE(uint32, bytes)

proc serializeInt64*(value: int64): seq[byte] {.raises: [BincodeError].} =
  ## Serialize an int64 to bincode format.
  ##
  ## Wraps the int64 bytes in Vec<u8> format (8-byte length prefix + 8-byte data).
  ## Format: [8-byte u64 length (little-endian)] + [8-byte int64 (little-endian, two's complement)]

  let bytes = toBytesLE(value.uint64)
  result = serialize(@[bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[
      5], bytes[6], bytes[7]])

proc deserializeInt64*(data: openArray[byte]): int64 {.raises: [
    BincodeError].} =
  ## Deserialize bincode-encoded data to an int64.
  ##
  ## Expects Vec<u8> format (8-byte length prefix + 8-byte data).
  ## Raises `BincodeError` if deserialized data is insufficient (< 8 bytes).

  let bytes = deserialize(data)
  if bytes.len < INT64_SIZE:
    raise newException(BincodeError, "Cannot deserialize int64: insufficient data")
  result = cast[int64](fromBytesLE(uint64, bytes))

{.pop.}
