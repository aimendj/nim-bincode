# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import std/[tables, sets, options, typetraits]
import faststreams
import pkg/serialization
export serialization
export options
export typetraits
import ./config
import ./codecs

## Integration adapter for ``nim-serialization`` framework.

serializationFormat Bincode
const MimeType* = "application/octet-stream"

type
  BincodeWriter* = object
    stream*: OutputStreamHandle
    config*: BincodeConfig

  BincodeReader* = object
    stream*: InputStreamHandle
    hasStream*: bool
    buffer*: seq[byte]
    offset*: int
    config*: BincodeConfig

Bincode.setWriter BincodeWriter, PreferredOutput = seq[byte]
Bincode.setReader BincodeReader

proc init*(
    T: type BincodeWriter,
    stream: OutputStreamHandle,
    config: BincodeConfig = standard(),
): BincodeWriter =
  BincodeWriter(stream: stream, config: config)

proc init*(
    T: type BincodeReader, stream: InputStreamHandle, config: BincodeConfig = standard()
): BincodeReader =
  BincodeReader(stream: stream, hasStream: true, buffer: @[], offset: 0, config: config)

proc init*(
    T: type BincodeReader, buffer: openArray[byte], config: BincodeConfig = standard()
): BincodeReader =
  BincodeReader(hasStream: false, buffer: @buffer, offset: 0, config: config)

proc getOutput*(w: var BincodeWriter): seq[byte] {.inline.} =
  w.stream.getOutput()

proc ensureBuffer*(r: var BincodeReader) {.raises: [IOError].} =
  if r.hasStream:
    while r.stream.readable():
      r.buffer.add r.stream.read()
    r.hasStream = false

# Stdlib collections codecs for BincodeWriter & BincodeReader

proc writeValue*[K, V](w: var BincodeWriter, t: Table[K, V]) {.raises: [IOError].} =
  try:
    encodeLength(w.stream, t.len.uint64, w.config)
  except BincodeError as exc:
    raiseAssert(exc.msg)
  for k, v in t.pairs:
    w.writeValue(k)
    w.writeValue(v)

proc readValue*[K, V](
    r: var BincodeReader, t: var Table[K, V]
) {.raises: [SerializationError, IOError].} =
  r.ensureBuffer()
  if r.offset >= r.buffer.len:
    raise (ref SerializationError)(msg: "Unexpected end of stream")
  try:
    let (lenVal, nLen) =
      decodeLength(r.buffer.toOpenArray(r.offset, r.buffer.high), r.config)
    r.offset += nLen
    t = initTable[K, V](lenVal.int)
    for _ in 0 ..< lenVal.int:
      var k: K
      var v: V
      r.readValue(k)
      r.readValue(v)
      t[k] = v
  except BincodeError as exc:
    raise (ref SerializationError)(msg: exc.msg)

proc writeValue*[T](w: var BincodeWriter, s: HashSet[T]) {.raises: [IOError].} =
  try:
    encodeLength(w.stream, s.len.uint64, w.config)
  except BincodeError as exc:
    raiseAssert(exc.msg)
  for item in s:
    w.writeValue(item)

proc readValue*[T](
    r: var BincodeReader, s: var HashSet[T]
) {.raises: [SerializationError, IOError].} =
  r.ensureBuffer()
  if r.offset >= r.buffer.len:
    raise (ref SerializationError)(msg: "Unexpected end of stream")
  try:
    let (lenVal, nLen) =
      decodeLength(r.buffer.toOpenArray(r.offset, r.buffer.high), r.config)
    r.offset += nLen
    s = initHashSet[T](lenVal.int)
    for _ in 0 ..< lenVal.int:
      var item: T
      r.readValue(item)
      s.incl(item)
  except BincodeError as exc:
    raise (ref SerializationError)(msg: exc.msg)

# Generic writeValue and readValue fallback for all types (scalars, containers, distinct, derived)

proc writeValue*[T](w: var BincodeWriter, value: T) {.raises: [IOError].} =
  try:
    encode(w.stream, value, w.config)
  except BincodeError as exc:
    raiseAssert(exc.msg)

proc readValue*[T](
    r: var BincodeReader, value: var T
) {.raises: [SerializationError, IOError].} =
  r.ensureBuffer()
  if r.offset >= r.buffer.len and r.buffer.len > 0:
    raise (ref SerializationError)(msg: "Unexpected end of stream")
  try:
    let (v, n) = decodeAt(r.buffer, typedesc[T], r.config, r.offset)
    r.offset += n
    value = v
  except BincodeError as exc:
    raise (ref SerializationError)(msg: exc.msg)

proc handleTrailingData*(r: var BincodeReader) {.raises: [SerializationError].} =
  if r.offset != r.buffer.len:
    raise (ref SerializationError)(msg: "Trailing bytes after decoded value")

proc encode*[T](
    flavor: type Bincode, value: T, config: BincodeConfig = standard()
): seq[byte] {.raises: [].} =
  var stream = memoryOutput()
  var writer = BincodeWriter.init(stream, config)
  try:
    writer.writeValue(value)
  except IOError:
    raiseAssert "memoryOutput doesn't raise IOError"
  writer.getOutput()

template encode*(
    flavor: type Bincode,
    stream: OutputStreamHandle,
    value: auto,
    config: BincodeConfig = standard(),
) =
  var writer = BincodeWriter.init(stream, config)
  writer.writeValue(value)

template decode*(
    flavor: type Bincode,
    data: openArray[byte],
    target: type,
    config: BincodeConfig = standard(),
): auto =
  var reader = BincodeReader.init(data, config)
  var res: target
  try:
    reader.readValue(res)
  except IOError as exc:
    raise (ref SerializationError)(msg: exc.msg)
  reader.handleTrailingData()
  res

template decode*(
    flavor: type Bincode,
    data: openArray[byte],
    value: var auto,
    config: BincodeConfig = standard(),
) =
  value = decode(flavor, data, typeof(value), config)

{.pop.}
