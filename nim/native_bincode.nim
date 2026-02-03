{.push raises: [BincodeError], gcsafe.}

import stew/endians2

type BincodeError* = object of CatchableError
  ## Exception raised when bincode operations fail

const BINCODE_SIZE_LIMIT* = 65536'u64
const LENGTH_PREFIX_SIZE* = 8

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

{.pop.}
