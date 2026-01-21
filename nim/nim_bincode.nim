{.push raises: [], gcsafe.}

import os
import stew/endians2

type BincodeError* = object of CatchableError
  ## Exception raised when bincode operations fail

const projectRoot = parentDir(parentDir(currentSourcePath()))
const libPath = projectRoot / "target" / "release"

{.passc: "-I" & projectRoot.}
{.passl: "-L" & libPath.}
{.passl: "-lbincode_wrapper".}

proc bincode_serialize*(
  data: ptr uint8, len: csize_t, out_len: ptr csize_t
): ptr uint8 {.importc.}

proc bincode_deserialize*(
  data: ptr uint8, len: csize_t, out_len: ptr csize_t
): ptr uint8 {.importc.}

proc bincode_free_buffer*(
  buffer: ptr uint8, len: csize_t
) {.importc: "bincode_free_buffer".}

proc bincode_get_serialized_length*(data: ptr uint8, len: csize_t): csize_t {.importc.}

proc serialize*(data: openArray[byte]): seq[byte] {.raises: [BincodeError].} =
  var outLen: csize_t = 0
  let dataPtr =
    if data.len > 0:
      data[0].unsafeAddr
    else:
      nil
  let bufferPtr = bincode_serialize(dataPtr, data.len.csize_t, outLen.addr)

  if bufferPtr == nil:
    raise newException(BincodeError, "Serialization failed")

  var output = newSeq[byte](outLen)
  if outLen > 0:
    copyMem(output[0].addr, bufferPtr, outLen)
    bincode_free_buffer(bufferPtr, outLen)
  return output

proc deserialize*(data: openArray[byte]): seq[byte] {.raises: [BincodeError].} =
  if data.len == 0:
    raise newException(BincodeError, "Cannot deserialize empty data")

  var outLen: csize_t = 0
  let dataPtr =
    if data.len > 0:
      data[0].unsafeAddr
    else:
      nil
  let bufferPtr = bincode_deserialize(dataPtr, data.len.csize_t, outLen.addr)

  if bufferPtr == nil:
    raise newException(BincodeError, "Deserialization failed")

  var output = newSeq[byte](outLen)
  if outLen > 0:
    copyMem(output[0].addr, bufferPtr, outLen)
    bincode_free_buffer(bufferPtr, outLen)
  return output

proc serializeString*(s: string): seq[byte] {.raises: [BincodeError].} =
  if s.len == 0:
    return serialize(@[])
  var bytes = newSeq[byte](s.len)
  for i in 0 ..< s.len:
    bytes[i] = byte(s[i])
  serialize(bytes)

proc deserializeString*(data: openArray[byte]): string {.raises: [BincodeError].} =
  let bytes = deserialize(data)
  if bytes.len == 0:
    return ""
  var output = newString(bytes.len)
  copyMem(output[0].addr, bytes[0].addr, bytes.len)
  return output

proc serializeInt32*(value: int32): seq[byte] {.raises: [BincodeError].} =
  serialize(@(toBytesLE(value.uint32)))

proc deserializeInt32*(data: openArray[byte]): int32 {.raises: [BincodeError].} =
  let bytes = deserialize(data)
  if bytes.len < 4:
    raise newException(BincodeError, "Cannot deserialize int32: insufficient data")
  return cast[int32](fromBytesLE(uint32, bytes))

proc serializeUint32*(value: uint32): seq[byte] {.raises: [BincodeError].} =
  serialize(@(toBytesLE(value)))

proc deserializeUint32*(data: openArray[byte]): uint32 {.raises: [BincodeError].} =
  let bytes = deserialize(data)
  if bytes.len < 4:
    raise newException(BincodeError, "Cannot deserialize uint32: insufficient data")
  return fromBytesLE(uint32, bytes)

proc serializeInt64*(value: int64): seq[byte] {.raises: [BincodeError].} =
  serialize(@(toBytesLE(value.uint64)))

proc deserializeInt64*(data: openArray[byte]): int64 {.raises: [BincodeError].} =
  let bytes = deserialize(data)
  if bytes.len < 8:
    raise newException(BincodeError, "Cannot deserialize int64: insufficient data")
  return cast[int64](fromBytesLE(uint64, bytes))

template serializeType*[T](value: T, toBytes: proc(x: T): seq[byte]): seq[byte] =
  serialize(toBytes(value))

template deserializeType*[T](
    data: openArray[byte], fromBytes: proc(x: seq[byte]): T {.closure.}
): T =
  fromBytes(deserialize(data))

{.pop.}
