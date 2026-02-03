{.push raises: [BincodeError], gcsafe.}

import stew/endians2

type BincodeError* = object of CatchableError
  ## Exception raised when bincode operations fail

const BINCODE_SIZE_LIMIT* = 65536'u64 # 64 KiB limit

proc serialize*(data: openArray[byte]): seq[byte] {.raises: [BincodeError].} =
  ## Serialize a byte sequence to bincode format.
  ##
  ## Format: [8-byte u64 length (little-endian)] + [data bytes]
  ##
  ## Raises `BincodeError` if data exceeds 64 KiB limit.
  ##
  ## Empty sequences serialize to 8 zero bytes (length = 0).

  # 1. Check size limit
  if data.len.uint64 > BINCODE_SIZE_LIMIT:
    raise newException(BincodeError, "Data exceeds 64 KiB limit")

  # 2. Encode length as u64 (little-endian)
  let lengthBytes = toBytesLE(data.len.uint64)

  # 3. Combine length + data
  result = newSeq[byte](8 + data.len)
  copyMem(result[0].addr, lengthBytes[0].addr, 8)
  if data.len > 0:
    copyMem(result[8].addr, data[0].unsafeAddr, data.len)

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

  # 1. Check minimum size
  if data.len < 8:
    raise newException(BincodeError, "Insufficient data for length prefix")

  # 2. Decode length (first 8 bytes)
  var lengthBytes: array[8, byte]
  for i in 0..7:
    lengthBytes[i] = data[i]
  let length = fromBytesLE(uint64, lengthBytes).int

  # 3. Check size limit
  if length.uint64 > BINCODE_SIZE_LIMIT:
    raise newException(BincodeError, "Length exceeds 64 KiB limit")

  # 4. Check sufficient data
  if data.len < 8 + length:
    raise newException(BincodeError, "Insufficient data for content")

  # 5. Extract data bytes
  result = newSeq[byte](length)
  if length > 0:
    copyMem(result[0].addr, data[8].unsafeAddr, length)

  # 6. Verify no trailing bytes (matches Rust behavior)
  if data.len != 8 + length:
    raise newException(BincodeError, "Trailing bytes detected")

{.pop.}
