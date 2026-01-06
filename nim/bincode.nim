import os
import stew/endians2

const projectRoot = parentDir(parentDir(currentSourcePath()))
const libPath = projectRoot / "target" / "release"

{.passc: "-I" & projectRoot.}
{.passl: "-L" & libPath}
{.passl: "-lbincode_wrapper"}

type
  BincodeError* = enum
    Success = 0
    NullPointer = 1
    SerializationError = 2
    DeserializationError = 3

proc bincode_serialize*(
    data: ptr uint8,
    len: csize_t,
    out_len: ptr csize_t
): ptr uint8 {.importc.}

proc bincode_deserialize*(
    data: ptr uint8,
    len: csize_t,
    out_len: ptr csize_t
): ptr uint8 {.importc.}

proc bincode_free_buffer*(
    buffer: ptr uint8,
    len: csize_t
) {.importc: "bincode_free_buffer".}

proc bincode_get_serialized_length*(
    data: ptr uint8,
    len: csize_t
): csize_t {.importc.}

proc serialize*(data: seq[byte]): seq[byte] =
  if data.len == 0:
    return @[]
  
  var outLen: csize_t = 0
  let bufferPtr = bincode_serialize(
    data[0].unsafeAddr,
    data.len.csize_t,
    outLen.addr
  )
  
  if bufferPtr == nil:
    return @[]
  
  result = newSeq[byte](outLen)
  if outLen > 0:
    copyMem(result[0].addr, bufferPtr, outLen)
    bincode_free_buffer(bufferPtr, outLen)

proc deserialize*(data: seq[byte]): seq[byte] =
  if data.len == 0:
    return @[]
  
  var outLen: csize_t = 0
  let bufferPtr = bincode_deserialize(
    data[0].unsafeAddr,
    data.len.csize_t,
    outLen.addr
  )
  
  if bufferPtr == nil:
    return @[]
  
  result = newSeq[byte](outLen)
  if outLen > 0:
    copyMem(result[0].addr, bufferPtr, outLen)
    bincode_free_buffer(bufferPtr, outLen)

proc serializeString*(s: string): seq[byte] =
  if s.len == 0:
    return serialize(@[])
  var bytes = newSeq[byte](s.len)
  for i in 0..<s.len:
    bytes[i] = byte(s[i])
  serialize(bytes)

proc deserializeString*(data: seq[byte]): string =
  let bytes = deserialize(data)
  if bytes.len == 0:
    return ""
  result = newString(bytes.len)
  copyMem(result[0].addr, bytes[0].addr, bytes.len)

proc serializeInt32*(value: int32): seq[byte] =
  serialize(@(toBytesLE(value.uint32)))

proc deserializeInt32*(data: seq[byte]): int32 =
  let bytes = deserialize(data)
  if bytes.len >= 4:
    result = fromBytesLE(uint32, bytes).int32

proc serializeUint32*(value: uint32): seq[byte] =
  serialize(@(toBytesLE(value)))

proc deserializeUint32*(data: seq[byte]): uint32 =
  let bytes = deserialize(data)
  if bytes.len >= 4:
    result = fromBytesLE(uint32, bytes)

proc serializeInt64*(value: int64): seq[byte] =
  serialize(@(toBytesLE(value.uint64)))

proc deserializeInt64*(data: seq[byte]): int64 =
  let bytes = deserialize(data)
  if bytes.len >= 8:
    result = fromBytesLE(uint64, bytes).int64

template serializeType*[T](value: T, toBytes: proc(x: T): seq[byte]): seq[byte] =
  serialize(toBytes(value))

template deserializeType*[T](data: seq[byte], fromBytes: proc(x: seq[byte]): T): T =
  fromBytes(deserialize(data))

