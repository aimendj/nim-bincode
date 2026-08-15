# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import faststreams
import std/[typetraits, options]
import stew/[endians2, leb128]
import ./config

type BincodeError* = object of CatchableError
  ## Exception raised when bincode operations fail

const LENGTH_PREFIX_SIZE* = 8
const RUST_BINCODE_THRESHOLD_U16* = 251'u64
const RUST_BINCODE_THRESHOLD_U32* = 65536'u64
const RUST_BINCODE_THRESHOLD_U64* = 4294967296'u64
const RUST_BINCODE_MARKER_U16* = 0xfb'u8
const RUST_BINCODE_MARKER_U32* = 0xfc'u8
const RUST_BINCODE_MARKER_U64* = 0xfd'u8
const RUST_BINCODE_MARKER_U128* = 0xfe'u8

const BincodeVarintSingleByteMax* = 250'u64
const BincodeVarintU16Tag* = 251'u8
const BincodeVarintU32Tag* = 252'u8
const BincodeVarintU64Tag* = 253'u8

# Validation helpers

func checkSizeLimit*(
    size: uint64, limit: uint64 = BINCODE_SIZE_LIMIT
) {.inline, raises: [BincodeError].} =
  if size > limit:
    raise newException(BincodeError, "Data exceeds size limit")

func checkMinimumSize*(
    dataLen: int, required: int = LENGTH_PREFIX_SIZE
) {.inline, raises: [BincodeError].} =
  if dataLen < required:
    raise newException(BincodeError, "Insufficient data for length prefix")

func checkNoTrailingBytes*(
    dataLen: int, prefixSize: int, length: int
) {.inline, raises: [BincodeError].} =
  if dataLen != prefixSize + length:
    raise newException(BincodeError, "Trailing bytes detected")

func zigzagEncode*(value: int64): uint64 {.inline.} =
  if value >= 0:
    (value.uint64 shl 1)
  else:
    ((not value.uint64) shl 1) or 1

func zigzagDecode*(value: uint64): int64 {.inline.} =
  if (value and 1) == 0:
    (value shr 1).int64
  else:
    not ((value shr 1).int64)

func maxUnsignedForFixedIntSize*(size: int): uint64 {.raises: [BincodeError].} =
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

# Length prefix codecs

proc encodeLength*(
    stream: OutputStreamHandle, length: uint64, config: BincodeConfig
) {.inline, raises: [BincodeError, IOError].} =
  if config.intSize == 8 and config.byteOrder == LittleEndian:
    stream.write(toBytesLE(length))
  elif config.intSize > 0:
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
    if length < RUST_BINCODE_THRESHOLD_U16:
      stream.write(length.byte)
    elif length < RUST_BINCODE_THRESHOLD_U32:
      let bytes = toBytesLE(length.uint16)
      stream.write(RUST_BINCODE_MARKER_U16)
      stream.write(bytes.toOpenArray(0, bytes.high))
    elif length < RUST_BINCODE_THRESHOLD_U64:
      let bytes = toBytesLE(length.uint32)
      stream.write(RUST_BINCODE_MARKER_U32)
      stream.write(bytes.toOpenArray(0, bytes.high))
    else:
      let bytes = toBytesLE(length)
      stream.write(RUST_BINCODE_MARKER_U64)
      stream.write(bytes.toOpenArray(0, bytes.high))

proc encodeLength*(
    length: uint64, config: BincodeConfig
): seq[byte] {.inline, raises: [BincodeError, IOError].} =
  var stream = memoryOutput()
  encodeLength(stream, length, config)
  stream.getOutput()

func decodeLength*(
    data: openArray[byte], config: BincodeConfig
): (uint64, int) {.inline, raises: [BincodeError].} =
  if config.intSize > 0:
    let size = config.intSize
    if data.len < size:
      raise newException(BincodeError, "Insufficient data for length prefix")
    case size
    of 8:
      var b: array[8, byte]
      copyMem(b[0].addr, data[0].unsafeAddr, 8)
      let length =
        case config.byteOrder
        of LittleEndian:
          fromBytesLE(uint64, b)
        of BigEndian:
          fromBytesBE(uint64, b)
      return (length, 8)
    of 4:
      var b: array[4, byte]
      copyMem(b[0].addr, data[0].unsafeAddr, 4)
      let length =
        case config.byteOrder
        of LittleEndian:
          fromBytesLE(uint32, b).uint64
        of BigEndian:
          fromBytesBE(uint32, b).uint64
      return (length, 4)
    of 2:
      var b: array[2, byte]
      b[0] = data[0]
      b[1] = data[1]
      let length =
        case config.byteOrder
        of LittleEndian:
          fromBytesLE(uint16, b).uint64
        of BigEndian:
          fromBytesBE(uint16, b).uint64
      return (length, 2)
    of 1:
      return (data[0].uint64, 1)
    else:
      raise newException(BincodeError, "Invalid fixed int size for length prefix")
  else:
    if data.len == 0:
      raise newException(BincodeError, "Insufficient data for length prefix")
    let firstByte = data[0]
    if firstByte < RUST_BINCODE_MARKER_U16:
      return (firstByte.uint64, 1)
    elif firstByte == RUST_BINCODE_MARKER_U16:
      if data.len < 3:
        raise newException(BincodeError, "Insufficient data for u16 length prefix")
      var u16Bytes: array[2, byte]
      u16Bytes[0] = data[1]
      u16Bytes[1] = data[2]
      return (fromBytesLE(uint16, u16Bytes).uint64, 3)
    elif firstByte == RUST_BINCODE_MARKER_U32:
      if data.len < 5:
        raise newException(BincodeError, "Insufficient data for u32 length prefix")
      var u32Bytes: array[4, byte]
      copyMem(u32Bytes[0].addr, data[1].unsafeAddr, 4)
      return (fromBytesLE(uint32, u32Bytes).uint64, 5)
    elif firstByte == RUST_BINCODE_MARKER_U64:
      if data.len < 9:
        raise newException(BincodeError, "Insufficient data for u64 length prefix")
      var u64Bytes: array[8, byte]
      copyMem(u64Bytes[0].addr, data[1].unsafeAddr, 8)
      return (fromBytesLE(uint64, u64Bytes), 9)
    elif firstByte == RUST_BINCODE_MARKER_U128:
      if data.len < 17:
        raise newException(BincodeError, "Insufficient data for u128 length prefix")
      for i in 8 ..< 16:
        if data[i + 1] != 0:
          raise
            newException(BincodeError, "Length value exceeds uint64 maximum (2^64-1)")
      var u64Bytes: array[8, byte]
      copyMem(u64Bytes[0].addr, data[1].unsafeAddr, 8)
      return (fromBytesLE(uint64, u64Bytes), 17)
    elif firstByte == 0xff'u8:
      raise newException(
        BincodeError, "Invalid marker byte 0xff in variable-length encoding"
      )
    else:
      let decoded = fromBytes(uint64, data, Leb128)
      if decoded.len <= 0:
        raise newException(BincodeError, "Failed to decode variable-length integer")
      return (decoded.val, decoded.len.int)

# Varint codecs

proc encodeBincodeVarintU64*(
    stream: OutputStreamHandle, value: uint64, config: BincodeConfig = standard()
) {.raises: [IOError].} =
  if value <= BincodeVarintSingleByteMax:
    stream.write([byte(value)])
  elif value <= uint16.high.uint64:
    stream.write([BincodeVarintU16Tag])
    let b =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(uint16(value))
      of BigEndian:
        toBytesBE(uint16(value))
    stream.write(b)
  elif value <= uint32.high.uint64:
    stream.write([BincodeVarintU32Tag])
    let b =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(uint32(value))
      of BigEndian:
        toBytesBE(uint32(value))
    stream.write(b)
  else:
    stream.write([BincodeVarintU64Tag])
    let b =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(value)
      of BigEndian:
        toBytesBE(value)
    stream.write(b)

func decodeBincodeVarintU64*(
    data: openArray[byte], config: BincodeConfig, start: int = 0
): (uint64, int) {.raises: [BincodeError].} =
  if start < 0 or start > data.len:
    raise newException(BincodeError, "Invalid start offset for varint u64")
  if start == data.len:
    raise newException(BincodeError, "Insufficient data for varint u64")
  let tag = data[start]
  if tag.uint64 <= BincodeVarintSingleByteMax:
    return (tag.uint64, 1)
  if tag == BincodeVarintU16Tag:
    if data.len - start < 3:
      raise newException(BincodeError, "Insufficient data for varint u16")
    var b: array[2, byte]
    b[0] = data[start + 1]
    b[1] = data[start + 2]
    let v =
      case config.byteOrder
      of LittleEndian:
        fromBytesLE(uint16, b).uint64
      of BigEndian:
        fromBytesBE(uint16, b).uint64
    return (v, 3)
  if tag == BincodeVarintU32Tag:
    if data.len - start < 5:
      raise newException(BincodeError, "Insufficient data for varint u32")
    var b: array[4, byte]
    copyMem(b[0].addr, data[start + 1].unsafeAddr, 4)
    let v =
      case config.byteOrder
      of LittleEndian:
        fromBytesLE(uint32, b).uint64
      of BigEndian:
        fromBytesBE(uint32, b).uint64
    return (v, 5)
  if tag == BincodeVarintU64Tag:
    if data.len - start < 9:
      raise newException(BincodeError, "Insufficient data for varint u64")
    var b: array[8, byte]
    copyMem(b[0].addr, data[start + 1].unsafeAddr, 8)
    let v =
      case config.byteOrder
      of LittleEndian:
        fromBytesLE(uint64, b)
      of BigEndian:
        fromBytesBE(uint64, b)
    return (v, 9)
  raise newException(BincodeError, "Invalid bincode varint tag")

# Prefixed byte sequence codecs

proc encodePrefixedByteSeq*(
    stream: OutputStreamHandle, data: openArray[byte], config: BincodeConfig
) {.raises: [BincodeError, IOError].} =
  checkSizeLimit(data.len.uint64, config.sizeLimit)
  encodeLength(stream, data.len.uint64, config)
  if data.len > 0:
    stream.write(data)

func decodePrefixedByteSeq*(
    data: openArray[byte], config: BincodeConfig, start: int = 0
): (seq[byte], int) {.raises: [BincodeError].} =
  if start < 0 or start > data.len:
    raise newException(BincodeError, "Invalid start offset for prefixed bytes")
  let relLen = data.len - start
  if relLen < 1:
    raise newException(BincodeError, "Insufficient data for length prefix")

  let (lengthValue, prefixSize) =
    decodeLength(data.toOpenArray(start, data.high), config)
  checkSizeLimit(lengthValue, config.sizeLimit)
  if lengthValue > int.high.uint64:
    raise newException(BincodeError, "Length value exceeds maximum int size")

  let length = lengthValue.int
  checkMinimumSize(relLen, prefixSize + length)

  var output = newSeq[byte](length)
  if length > 0:
    copyMem(output[0].addr, data[start + prefixSize].unsafeAddr, length)

  (output, prefixSize + length)

# Enum discriminant codecs

proc encodeBincodeEnumDiscriminant*(
    stream: OutputStreamHandle, ordinal: int, config: BincodeConfig = standard()
) {.raises: [IOError].} =
  if config.intSize > 0:
    let b =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(ordinal.uint32)
      of BigEndian:
        toBytesBE(ordinal.uint32)
    stream.write(b)
  else:
    encodeBincodeVarintU64(stream, ordinal.uint64, config)

func decodeBincodeEnumDiscriminant*(
    data: openArray[byte], config: BincodeConfig, start: int = 0
): (uint32, int) {.raises: [BincodeError].} =
  if config.intSize > 0:
    if data.len - start < 4:
      raise newException(BincodeError, "Insufficient data for enum discriminant")
    var b: array[4, byte]
    copyMem(b[0].addr, data[start].unsafeAddr, 4)
    let v =
      case config.byteOrder
      of LittleEndian:
        fromBytesLE(uint32, b)
      of BigEndian:
        fromBytesBE(uint32, b)
    return (v, 4)
  else:
    let (u, n) = decodeBincodeVarintU64(data, config, start)
    if u > uint32.high.uint64:
      raise newException(BincodeError, "Enum discriminant out of range")
    return (u.uint32, n)

# Generic Primitive and Scalar Codecs

proc encode*[T: bool | char | SomeInteger | SomeFloat | string](
    stream: OutputStreamHandle, value: T, config: BincodeConfig = standard()
) {.raises: [BincodeError, IOError].} =
  when T is string:
    checkSizeLimit(value.len.uint64, config.sizeLimit)
    encodeLength(stream, value.len.uint64, config)
    if value.len > 0:
      stream.write(value.toOpenArray(0, value.high))
  elif T is bool:
    stream.write([if value: 1'u8 else: 0'u8])
  elif T is char:
    stream.write([value.byte])
  elif sizeof(T) == 1:
    stream.write([cast[byte](value)])
  elif T is float32:
    let b =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(cast[uint32](value))
      of BigEndian:
        toBytesBE(cast[uint32](value))
    stream.write(b)
  elif T is float64:
    let b =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(cast[uint64](value))
      of BigEndian:
        toBytesBE(cast[uint64](value))
    stream.write(b)
  elif T is SomeUnsignedInt:
    if config.intSize > 0:
      let b =
        case config.byteOrder
        of LittleEndian:
          toBytesLE(value)
        of BigEndian:
          toBytesBE(value)
      stream.write(b)
    else:
      encodeBincodeVarintU64(stream, value.uint64, config)
  elif T is SomeSignedInt:
    when sizeof(T) == 2:
      type UType = uint16
    elif sizeof(T) == 4:
      type UType = uint32
    else:
      type UType = uint64
    if config.intSize > 0:
      let b =
        case config.byteOrder
        of LittleEndian:
          toBytesLE(cast[UType](value))
        of BigEndian:
          toBytesBE(cast[UType](value))
      stream.write(b)
    else:
      encodeBincodeVarintU64(stream, zigzagEncode(value.int64), config)

func decodeAt*[T: bool | char | SomeInteger | SomeFloat | string](
    data: openArray[byte], tParam: typedesc[T], config: BincodeConfig, start: int = 0
): (T, int) {.raises: [BincodeError].} =
  when T is string:
    let (bytes, used) = decodePrefixedByteSeq(data, config, start)
    var s = newString(bytes.len)
    if bytes.len > 0:
      copyMem(s[0].addr, bytes[0].unsafeAddr, bytes.len)
    (s, used)
  elif T is bool:
    if start >= data.len:
      raise newException(BincodeError, "Insufficient data for bool")
    case data[start]
    of 0'u8:
      (false, 1)
    of 1'u8:
      (true, 1)
    else:
      raise newException(BincodeError, "Invalid bool value")
  elif T is char:
    if start >= data.len:
      raise newException(BincodeError, "Insufficient data for char")
    (data[start].char, 1)
  elif sizeof(T) == 1:
    if start >= data.len:
      raise newException(BincodeError, "Insufficient data for 1-byte integer")
    (cast[T](data[start]), 1)
  elif T is float32:
    if data.len - start < 4:
      raise newException(BincodeError, "Insufficient data for float32")
    var b: array[4, byte]
    copyMem(b[0].addr, data[start].unsafeAddr, 4)
    let u =
      case config.byteOrder
      of LittleEndian:
        fromBytesLE(uint32, b)
      of BigEndian:
        fromBytesBE(uint32, b)
    (cast[float32](u), 4)
  elif T is float64:
    if data.len - start < 8:
      raise newException(BincodeError, "Insufficient data for float64")
    var b: array[8, byte]
    copyMem(b[0].addr, data[start].unsafeAddr, 8)
    let u =
      case config.byteOrder
      of LittleEndian:
        fromBytesLE(uint64, b)
      of BigEndian:
        fromBytesBE(uint64, b)
    (cast[float64](u), 8)
  elif T is SomeUnsignedInt:
    const sz = sizeof(T)
    if config.intSize > 0:
      if data.len - start < sz:
        raise newException(BincodeError, "Insufficient data for integer")
      var b: array[sz, byte]
      copyMem(b[0].addr, data[start].unsafeAddr, sz)
      let v =
        case config.byteOrder
        of LittleEndian:
          fromBytesLE(T, b)
        of BigEndian:
          fromBytesBE(T, b)
      return (v, sz)
    else:
      let (u, n) = decodeBincodeVarintU64(data, config, start)
      if u > T.high.uint64:
        raise newException(BincodeError, "Integer value out of range")
      return (T(u), n)
  elif T is SomeSignedInt:
    when sizeof(T) == 2:
      type UType = uint16
    elif sizeof(T) == 4:
      type UType = uint32
    else:
      type UType = uint64
    const sz = sizeof(T)
    if config.intSize > 0:
      if data.len - start < sz:
        raise newException(BincodeError, "Insufficient data for integer")
      var b: array[sz, byte]
      copyMem(b[0].addr, data[start].unsafeAddr, sz)
      let u =
        case config.byteOrder
        of LittleEndian:
          fromBytesLE(UType, b)
        of BigEndian:
          fromBytesBE(UType, b)
      return (cast[T](u), sz)
    else:
      let (u, n) = decodeBincodeVarintU64(data, config, start)
      let v = zigzagDecode(u)
      if v < T.low.int64 or v > T.high.int64:
        raise newException(BincodeError, "Integer value out of range")
      return (T(v), n)

# Generic Enums

proc encode*[T: enum](
    stream: OutputStreamHandle, value: T, config: BincodeConfig = standard()
) {.raises: [IOError].} =
  encodeBincodeEnumDiscriminant(stream, ord(value), config)

func decodeAt*[T: enum](
    data: openArray[byte],
    tParam: typedesc[T],
    config: BincodeConfig = standard(),
    start: int = 0,
): (T, int) {.raises: [BincodeError].} =
  let (disc, used) = decodeBincodeEnumDiscriminant(data, config, start)
  when compiles(
    for v in low(T) .. high(T):
      discard
  ):
    for v in low(T) .. high(T):
      if ord(v).uint32 == disc:
        return (v, used)
    raise
      newException(BincodeError, "Invalid enum discriminant for " & $T & ": " & $disc)
  else:
    if disc <= high(T).ord.uint32:
      return (cast[T](disc.int), used)
    raise
      newException(BincodeError, "Invalid enum discriminant for " & $T & ": " & $disc)

# Generic Option[T]

proc encode*[T](
    stream: OutputStreamHandle, value: Option[T], config: BincodeConfig = standard()
) {.raises: [BincodeError, IOError].} =
  if value.isSome:
    stream.write([1'u8])
    encode(stream, value.get(), config)
  else:
    stream.write([0'u8])

func decodeAt*[T](
    data: openArray[byte],
    tParam: typedesc[Option[T]],
    config: BincodeConfig = standard(),
    start: int = 0,
): (Option[T], int) {.raises: [BincodeError].} =
  if start < 0 or start >= data.len:
    raise newException(BincodeError, "Insufficient data for Option")
  let tag = data[start]
  case tag
  of 0'u8:
    (none(T), 1)
  of 1'u8:
    let (v, n) = decodeAt(data, typedesc[T], config, start + 1)
    (some(v), 1 + n)
  else:
    raise newException(BincodeError, "Invalid Option tag byte: " & $tag)

# Generic array[N, T]

proc encode*[N: static[int], T](
    stream: OutputStreamHandle, value: array[N, T], config: BincodeConfig = standard()
) {.raises: [BincodeError, IOError].} =
  when T is byte:
    if N > 0:
      stream.write(value)
  else:
    for item in value:
      encode(stream, item, config)

func decodeAt*[N: static[int], T](
    data: openArray[byte],
    tParam: typedesc[array[N, T]],
    config: BincodeConfig = standard(),
    start: int = 0,
): (array[N, T], int) {.raises: [BincodeError].} =
  when T is byte:
    if start < 0 or data.len - start < N:
      raise newException(BincodeError, "Insufficient data for array")
    var res: array[N, T]
    if N > 0:
      copyMem(res[0].addr, data[start].unsafeAddr, N)
    (res, N)
  else:
    var cur = start
    var res: array[N, T]
    for i in 0 ..< N:
      let (item, used) = decodeAt(data, typedesc[T], config, cur)
      res[i] = item
      cur += used
    (res, cur - start)

# Generic seq[T] and openArray[T]

proc encode*[T](
    stream: OutputStreamHandle, value: seq[T], config: BincodeConfig = standard()
) {.raises: [BincodeError, IOError].} =
  when T is byte:
    encodePrefixedByteSeq(stream, value, config)
  else:
    checkSizeLimit(value.len.uint64, config.sizeLimit)
    encodeLength(stream, value.len.uint64, config)
    for item in value:
      encode(stream, item, config)

proc encode*(
    stream: OutputStreamHandle,
    data: openArray[byte],
    config: BincodeConfig = standard(),
) {.raises: [BincodeError, IOError].} =
  encodePrefixedByteSeq(stream, data, config)

func decodeAt*[T](
    data: openArray[byte],
    tParam: typedesc[seq[T]],
    config: BincodeConfig = standard(),
    start: int = 0,
): (seq[T], int) {.raises: [BincodeError].} =
  when T is byte:
    decodePrefixedByteSeq(data, config, start)
  else:
    if start < 0 or start > data.len:
      raise newException(BincodeError, "Invalid start offset")
    let (lenVal, prefixSize) = decodeLength(data.toOpenArray(start, data.high), config)
    checkSizeLimit(lenVal, config.sizeLimit)
    var cur = start + prefixSize
    var res = newSeq[T](lenVal.int)
    for i in 0 ..< lenVal.int:
      let (item, used) = decodeAt(data, typedesc[T], config, cur)
      res[i] = item
      cur += used
    (res, cur - start)

# Generic distinct types

proc encode*[T: distinct](
    stream: OutputStreamHandle, value: T, config: BincodeConfig = standard()
) {.raises: [BincodeError, IOError].} =
  encode(stream, distinctBase(value), config)

proc decodeAt*[T: distinct](
    data: openArray[byte],
    tParam: typedesc[T],
    config: BincodeConfig = standard(),
    start: int = 0,
): (T, int) {.raises: [BincodeError].} =
  let (v, n) = decodeAt(data, typedesc[distinctBase(T)], config, start)
  (T(v), n)

# Global Top-Level encode and decode procedures

proc encode*[T](
    value: T, config: BincodeConfig = standard()
): seq[byte] {.raises: [BincodeError].} =
  when T is bool:
    @[if value: 1'u8 else: 0'u8]
  elif T is char:
    @[value.byte]
  elif sizeof(T) == 1 and (T is (uint8 | int8 | byte)):
    @[cast[byte](value)]
  elif T is float32:
    let b =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(cast[uint32](value))
      of BigEndian:
        toBytesBE(cast[uint32](value))
    @b
  elif T is float64:
    let b =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(cast[uint64](value))
      of BigEndian:
        toBytesBE(cast[uint64](value))
    @b
  elif (T is SomeUnsignedInt) and (not (T is distinct)):
    if config.intSize > 0:
      let b =
        case config.byteOrder
        of LittleEndian:
          toBytesLE(value)
        of BigEndian:
          toBytesBE(value)
      @b
    else:
      var stream = memoryOutput()
      try:
        encode(stream, value, config)
      except IOError as exc:
        raise newException(BincodeError, exc.msg)
      stream.getOutput()
  elif (T is SomeSignedInt) and (not (T is distinct)):
    when sizeof(T) == 2:
      type UType = uint16
    elif sizeof(T) == 4:
      type UType = uint32
    else:
      type UType = uint64
    if config.intSize > 0:
      let b =
        case config.byteOrder
        of LittleEndian:
          toBytesLE(cast[UType](value))
        of BigEndian:
          toBytesBE(cast[UType](value))
      @b
    else:
      var stream = memoryOutput()
      try:
        encode(stream, value, config)
      except IOError as exc:
        raise newException(BincodeError, exc.msg)
      stream.getOutput()
  else:
    var stream = memoryOutput()
    try:
      encode(stream, value, config)
    except IOError as exc:
      raise newException(BincodeError, exc.msg)
    stream.getOutput()

proc decode*[T](
    data: openArray[byte], tParam: typedesc[T], config: BincodeConfig = standard()
): T {.raises: [BincodeError].} =
  let (res, n) = decodeAt(data, tParam, config, 0)
  checkNoTrailingBytes(data.len, 0, n)
  res

func decode*(
    data: openArray[byte], config: BincodeConfig = standard()
): seq[byte] {.raises: [BincodeError].} =
  let (length, prefixSize) = decodeLength(data, config)
  checkSizeLimit(length, config.sizeLimit)
  checkMinimumSize(data.len, prefixSize + length.int)
  checkNoTrailingBytes(data.len, prefixSize, length.int)
  if length == 0:
    return @[]
  var output = newSeq[byte](length)
  copyMem(output[0].addr, data[prefixSize].unsafeAddr, length.int)
  output

proc decode*[T](
    data: openArray[byte], value: var T, config: BincodeConfig = standard()
) {.raises: [BincodeError].} =
  value = decode(data, typedesc[T], config)

{.pop.}
