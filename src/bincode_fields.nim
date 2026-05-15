# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import faststreams
import stew/[endians2, leb128]
import bincode_config
import bincode_common
import bincode_helpers

## Plain scalar and collection field encoding (Rust ``Encode`` for struct fields).
##
## Used by `deriveBincode`_ and by hand-written serializers. ``Vec<u8>``-wrapped
## integers remain in `bincode_helpers`_.

const BincodeVarintSingleByteMax* = 250'u64
const BincodeVarintU16Tag* = 251'u8
const BincodeVarintU32Tag* = 252'u8
const BincodeVarintU64Tag* = 253'u8

proc writeFixedBytes*(
    stream: OutputStreamHandle, config: BincodeConfig, bytes: openArray[byte]
) {.raises: [IOError].} =
  case config.byteOrder
  of LittleEndian:
    stream.write(bytes)
  of BigEndian:
    var padded: array[8, byte]
    let n = bytes.len
    for i in 0 ..< n:
      padded[8 - n + i] = bytes[i]
    stream.write(padded.toOpenArray(8 - n, 7))

proc serializeBincodeVarintU64*(
    stream: OutputStreamHandle, value: uint64, config: BincodeConfig
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

func deserializeBincodeVarintU64*(
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

proc serializeBincodeBool*(
    stream: OutputStreamHandle, value: bool, config: BincodeConfig = standard()
) {.raises: [IOError].} =
  discard config
  if value:
    stream.write([1'u8])
  else:
    stream.write([0'u8])

func deserializeBincodeBool*(
    data: openArray[byte], config: BincodeConfig, start: int = 0
): (bool, int) {.raises: [BincodeError].} =
  discard config
  if start >= data.len:
    raise newException(BincodeError, "Insufficient data for bool")
  case data[start]
  of 0'u8:
    (false, 1)
  of 1'u8:
    (true, 1)
  else:
    raise newException(BincodeError, "Invalid bool value")

proc serializeBincodeU8*(
    stream: OutputStreamHandle, value: uint8, config: BincodeConfig = standard()
) {.raises: [IOError].} =
  discard config
  stream.write([value])

func deserializeBincodeU8*(
    data: openArray[byte], config: BincodeConfig, start: int = 0
): (uint8, int) {.raises: [BincodeError].} =
  discard config
  if start >= data.len:
    raise newException(BincodeError, "Insufficient data for u8")
  (data[start], 1)

proc serializeBincodeI8*(
    stream: OutputStreamHandle, value: int8, config: BincodeConfig = standard()
) {.raises: [IOError].} =
  discard config
  stream.write([value.byte])

func deserializeBincodeI8*(
    data: openArray[byte], config: BincodeConfig, start: int = 0
): (int8, int) {.raises: [BincodeError].} =
  discard config
  if start >= data.len:
    raise newException(BincodeError, "Insufficient data for i8")
  (data[start].int8, 1)

proc serializeBincodeU16*(
    stream: OutputStreamHandle, value: uint16, config: BincodeConfig = standard()
) {.raises: [IOError].} =
  if config.intSize > 0:
    let b =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(value)
      of BigEndian:
        toBytesBE(value)
    stream.write(b)
  else:
    serializeBincodeVarintU64(stream, value.uint64, config)

func deserializeBincodeU16*(
    data: openArray[byte], config: BincodeConfig, start: int = 0
): (uint16, int) {.raises: [BincodeError].} =
  if config.intSize > 0:
    if data.len - start < 2:
      raise newException(BincodeError, "Insufficient data for u16")
    var b: array[2, byte]
    b[0] = data[start]
    b[1] = data[start + 1]
    let v =
      case config.byteOrder
      of LittleEndian:
        fromBytesLE(uint16, b)
      of BigEndian:
        fromBytesBE(uint16, b)
    return (v, 2)
  else:
    let (u, n) = deserializeBincodeVarintU64(data, config, start)
    if u > uint16.high.uint64:
      raise newException(BincodeError, "u16 value out of range")
    return (u.uint16, n)

proc serializeBincodeI16*(
    stream: OutputStreamHandle, value: int16, config: BincodeConfig = standard()
) {.raises: [IOError].} =
  if config.intSize > 0:
    let b =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(value.int32.uint32)
      of BigEndian:
        toBytesBE(value.int32.uint32)
    stream.write(b.toOpenArray(0, 1))
  else:
    let zz = zigzagEncode(value.int64)
    serializeBincodeVarintU64(stream, zz, config)

func deserializeBincodeI16*(
    data: openArray[byte], config: BincodeConfig, start: int = 0
): (int16, int) {.raises: [BincodeError].} =
  if config.intSize > 0:
    if data.len - start < 2:
      raise newException(BincodeError, "Insufficient data for i16")
    var b: array[2, byte]
    b[0] = data[start]
    b[1] = data[start + 1]
    let v =
      case config.byteOrder
      of LittleEndian:
        fromBytesLE(uint16, b).int16
      of BigEndian:
        fromBytesBE(uint16, b).int16
    return (v, 2)
  else:
    let (u, n) = deserializeBincodeVarintU64(data, config, start)
    let v = zigzagDecode(u)
    if v < int16.low.int64 or v > int16.high.int64:
      raise newException(BincodeError, "i16 value out of range")
    return (v.int16, n)

proc serializeBincodeI32*(
    stream: OutputStreamHandle, value: int32, config: BincodeConfig = standard()
) {.raises: [IOError].} =
  if config.intSize > 0:
    let b =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(value.int64.uint64)
      of BigEndian:
        toBytesBE(value.int64.uint64)
    stream.write(b.toOpenArray(0, 3))
  else:
    serializeBincodeVarintU64(stream, zigzagEncode(value.int64), config)

func deserializeBincodeI32*(
    data: openArray[byte], config: BincodeConfig, start: int = 0
): (int32, int) {.raises: [BincodeError].} =
  if config.intSize > 0:
    if data.len - start < 4:
      raise newException(BincodeError, "Insufficient data for i32")
    var padded: array[8, byte]
    case config.byteOrder
    of LittleEndian:
      copyMem(padded[0].addr, data[start].unsafeAddr, 4)
      if (data[start + 3] and 0x80'u8) != 0:
        for i in 4 .. 7:
          padded[i] = 0xFF'u8
      return (cast[int32](fromBytesLE(uint64, padded)), 4)
    of BigEndian:
      copyMem(padded[4].addr, data[start].unsafeAddr, 4)
      if (data[start] and 0x80'u8) != 0:
        for i in 0 .. 3:
          padded[i] = 0xFF'u8
      return (cast[int32](fromBytesBE(uint64, padded)), 4)
  else:
    let (u, n) = deserializeBincodeVarintU64(data, config, start)
    let v = zigzagDecode(u)
    if v < int32.low.int64 or v > int32.high.int64:
      raise newException(BincodeError, "i32 value out of range")
    return (v.int32, n)

proc serializeBincodeU64*(
    stream: OutputStreamHandle, value: uint64, config: BincodeConfig = standard()
) {.raises: [IOError].} =
  if config.intSize > 0:
    let b =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(value)
      of BigEndian:
        toBytesBE(value)
    stream.write(b)
  else:
    serializeBincodeVarintU64(stream, value, config)

func deserializeBincodeU64*(
    data: openArray[byte], config: BincodeConfig, start: int = 0
): (uint64, int) {.raises: [BincodeError].} =
  if config.intSize > 0:
    if data.len - start < 8:
      raise newException(BincodeError, "Insufficient data for u64")
    var b: array[8, byte]
    copyMem(b[0].addr, data[start].unsafeAddr, 8)
    let v =
      case config.byteOrder
      of LittleEndian:
        fromBytesLE(uint64, b)
      of BigEndian:
        fromBytesBE(uint64, b)
    return (v, 8)
  else:
    deserializeBincodeVarintU64(data, config, start)

proc serializeBincodeI64*(
    stream: OutputStreamHandle, value: int64, config: BincodeConfig = standard()
) {.raises: [IOError].} =
  if config.intSize > 0:
    let b =
      case config.byteOrder
      of LittleEndian:
        toBytesLE(value.uint64)
      of BigEndian:
        toBytesBE(value.uint64)
    stream.write(b)
  else:
    serializeBincodeVarintU64(stream, zigzagEncode(value), config)

func deserializeBincodeI64*(
    data: openArray[byte], config: BincodeConfig, start: int = 0
): (int64, int) {.raises: [BincodeError].} =
  if config.intSize > 0:
    if data.len - start < 8:
      raise newException(BincodeError, "Insufficient data for i64")
    var b: array[8, byte]
    copyMem(b[0].addr, data[start].unsafeAddr, 8)
    let v =
      case config.byteOrder
      of LittleEndian:
        fromBytesLE(uint64, b)
      of BigEndian:
        fromBytesBE(uint64, b)
    return (cast[int64](v), 8)
  else:
    let (u, n) = deserializeBincodeVarintU64(data, config, start)
    return (zigzagDecode(u), n)

proc float32BitsLE(value: float32): array[4, byte] =
  toBytesLE(cast[uint32](value))

proc float32BitsBE(value: float32): array[4, byte] =
  toBytesBE(cast[uint32](value))

proc float64BitsLE(value: float64): array[8, byte] =
  toBytesLE(cast[uint64](value))

proc float64BitsBE(value: float64): array[8, byte] =
  toBytesBE(cast[uint64](value))

proc serializeBincodeF32*(
    stream: OutputStreamHandle, value: float32, config: BincodeConfig = standard()
) {.raises: [IOError].} =
  let b =
    case config.byteOrder
    of LittleEndian:
      float32BitsLE(value)
    of BigEndian:
      float32BitsBE(value)
  stream.write(b)

func deserializeBincodeF32*(
    data: openArray[byte], config: BincodeConfig, start: int = 0
): (float32, int) {.raises: [BincodeError].} =
  if data.len - start < 4:
    raise newException(BincodeError, "Insufficient data for f32")
  var b: array[4, byte]
  copyMem(b[0].addr, data[start].unsafeAddr, 4)
  let v =
    case config.byteOrder
    of LittleEndian:
      cast[float32](fromBytesLE(uint32, b))
    of BigEndian:
      cast[float32](fromBytesBE(uint32, b))
  (v, 4)

proc serializeBincodeF64*(
    stream: OutputStreamHandle, value: float64, config: BincodeConfig = standard()
) {.raises: [IOError].} =
  let b =
    case config.byteOrder
    of LittleEndian:
      float64BitsLE(value)
    of BigEndian:
      float64BitsBE(value)
  stream.write(b)

func deserializeBincodeF64*(
    data: openArray[byte], config: BincodeConfig, start: int = 0
): (float64, int) {.raises: [BincodeError].} =
  if data.len - start < 8:
    raise newException(BincodeError, "Insufficient data for f64")
  var b: array[8, byte]
  copyMem(b[0].addr, data[start].unsafeAddr, 8)
  let v =
    case config.byteOrder
    of LittleEndian:
      cast[float64](fromBytesLE(uint64, b))
    of BigEndian:
      cast[float64](fromBytesBE(uint64, b))
  (v, 8)

proc serializeBincodeChar*(
    stream: OutputStreamHandle, value: char, config: BincodeConfig = standard()
) {.raises: [IOError].} =
  serializeBincodeU32(stream, uint32(value), config)

func deserializeBincodeChar*(
    data: openArray[byte], config: BincodeConfig, start: int = 0
): (char, int) {.raises: [BincodeError].} =
  let (u, n) = deserializeBincodeU32(data, config, start)
  if u > 0x10FFFF'u32:
    raise newException(BincodeError, "Invalid char code point")
  (char(u), n)

proc serializeBincodeEnumDiscriminant*(
    stream: OutputStreamHandle, ordinal: int, config: BincodeConfig = standard()
) {.raises: [IOError].} =
  ## Serialize an enum discriminant as a **plain** ``u32`` (Rust ``Encode`` for enums).
  ##
  ## Not length-prefixed; container ``intSize`` applies only to ``string`` / ``seq`` fields.
  serializeBincodeU32(stream, ordinal.uint32, config)

func deserializeBincodeEnumDiscriminant*(
    data: openArray[byte], config: BincodeConfig, start: int = 0
): (uint32, int) {.raises: [BincodeError].} =
  ## Decode a discriminant written by `serializeBincodeEnumDiscriminant`_.
  deserializeBincodeU32(data, config, start)

{.pop.}
