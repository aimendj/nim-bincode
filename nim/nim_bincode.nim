{.push raises: [], gcsafe.}

import stew/endians2
import stew/leb128
import bincode_config

## Native Nim implementation of a subset of the bincode v2 format.
##
## For `Vec[byte]` / strings the format matches Rust bincode v2 with:
## - little- or big-endian configurable byte order
## - fixed or variable-length integer encoding (see `bincode_config`)
## - a configurable size limit (default 64 KiB)

type BincodeError* = object of CatchableError
  ## Exception raised when bincode operations fail

const LENGTH_PREFIX_SIZE* = 8
const INT32_SIZE* = 4
const INT64_SIZE* = 8

proc checkSizeLimit*(
    size: uint64, limit: uint64 = BINCODE_SIZE_LIMIT
) {.raises: [BincodeError].} =
  ## Check if size exceeds the specified limit.
  ## Raises `BincodeError` if size exceeds limit.
  if size > limit:
    raise newException(BincodeError, "Data exceeds size limit")

proc checkMinimumSize*(
    dataLen: int, required: int = LENGTH_PREFIX_SIZE
) {.raises: [BincodeError].} =
  ## Check if data length meets minimum requirement.
  ## Raises `BincodeError` if data is insufficient.
  if dataLen < required:
    raise newException(BincodeError, "Insufficient data for length prefix")

proc checkLengthLimit*(
    length: uint64, limit: uint64 = BINCODE_SIZE_LIMIT
) {.raises: [BincodeError].} =
  ## Check if decoded length exceeds the specified limit.
  ## Raises `BincodeError` if length exceeds limit.
  if length > limit:
    raise newException(BincodeError, "Length exceeds size limit")

proc checkSufficientData*(dataLen: int, length: int) {.raises: [BincodeError].} =
  ## Check if data has sufficient bytes for the decoded length.
  ## Raises `BincodeError` if insufficient data.
  if dataLen < LENGTH_PREFIX_SIZE + length:
    raise newException(BincodeError, "Insufficient data for content")

proc checkNoTrailingBytes*(dataLen: int, length: int) {.raises: [BincodeError].} =
  ## Check if there are no trailing bytes after the expected data.
  ## Raises `BincodeError` if trailing bytes detected.
  if dataLen != LENGTH_PREFIX_SIZE + length:
    raise newException(BincodeError, "Trailing bytes detected")

func zigzagEncode*(value: int64): uint64 {.raises: [].} =
  ## Encode a signed integer using zigzag encoding for LEB128.
  ## Zigzag encoding maps signed integers to unsigned integers:
  ## 0 -> 0, -1 -> 1, 1 -> 2, -2 -> 3, 2 -> 4, etc.
  if value >= 0:
    (value.uint64 shl 1)
  else:
    ((not value.uint64) shl 1) or 1

func zigzagDecode*(value: uint64): int64 {.raises: [].} =
  ## Decode a zigzag-encoded unsigned integer back to a signed integer.
  if (value and 1) == 0:
    (value shr 1).int64
  else:
    not ((value shr 1).int64)

func encodeLength*(length: uint64, config: BincodeConfig): seq[byte] {.raises: [].} =
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
    # Values < 251: Single byte (the value itself)
    # Values 251 to 2^16-1: 0xfb + u16 LE
    # Values 2^16 to 2^32-1: 0xfc + u32 LE
    # Values 2^32 to 2^64-1: 0xfd + u64 LE
    # Values 2^64 to 2^128-1: 0xfe + u128 LE
    const RUST_BINCODE_THRESHOLD_U16 = 251'u64
    const RUST_BINCODE_THRESHOLD_U32 = 65536'u64 # 2^16
    const RUST_BINCODE_THRESHOLD_U64 = 4294967296'u64 # 2^32
    const RUST_BINCODE_MARKER_U16 = 0xfb'u8
    const RUST_BINCODE_MARKER_U32 = 0xfc'u8
    const RUST_BINCODE_MARKER_U64 = 0xfd'u8
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

proc decodeLength*(
    data: openArray[byte], config: BincodeConfig
): (uint64, int) {.raises: [BincodeError].} =
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
    const RUST_BINCODE_MARKER_U16 = 0xfb'u8
    const RUST_BINCODE_MARKER_U32 = 0xfc'u8
    const RUST_BINCODE_MARKER_U64 = 0xfd'u8
    const RUST_BINCODE_MARKER_U128 = 0xfe'u8

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

proc serialize*(
    data: openArray[byte], config: BincodeConfig = standard()
): seq[byte] {.raises: [BincodeError].} =
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
): seq[byte] {.raises: [BincodeError].} =
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
  ## - Insufficient data for content
  ## - Trailing bytes detected (all input bytes must be consumed)

  if data.len == 0:
    raise newException(BincodeError, "Insufficient data for length prefix")

  let (lengthValue, prefixSize) = decodeLength(data, config)
  let length = lengthValue.int

  checkLengthLimit(lengthValue, config.sizeLimit)

  if data.len < prefixSize + length:
    raise newException(BincodeError, "Insufficient data for content")

  var output = newSeq[byte](length)
  if length > 0:
    copyMem(output[0].addr, data[prefixSize].unsafeAddr, length)

  if data.len != prefixSize + length:
    raise newException(BincodeError, "Trailing bytes detected")

  return output

proc serializeString*(
    s: string, config: BincodeConfig = standard()
): seq[byte] {.raises: [BincodeError].} =
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

  return serialize(utf8Bytes, config)

proc deserializeString*(
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
  return output

proc serializeInt32*(
    value: int32, config: BincodeConfig = standard()
): seq[byte] {.raises: [BincodeError].} =
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
    intBytes = @buf
  return serialize(intBytes, config)

proc deserializeInt32*(
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
    value: uint32, config: BincodeConfig = standard()
): seq[byte] {.raises: [BincodeError].} =
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
    intBytes = @buf
  return serialize(intBytes, config)

proc deserializeUint32*(
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
    value: int64, config: BincodeConfig = standard()
): seq[byte] {.raises: [BincodeError].} =
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
    intBytes = @buf
  return serialize(intBytes, config)

proc deserializeInt64*(
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

template serializeType*[T](value: T, toBytes: proc(x: T): seq[byte]): seq[byte] =
  ## Serialize a custom type using a conversion function.
  serialize(toBytes(value))

template deserializeType*[T](
    data: openArray[byte], fromBytes: proc(x: openArray[byte]): T
): T =
  ## Deserialize a custom type using a conversion function.
  fromBytes(deserialize(data))

{.pop.}
