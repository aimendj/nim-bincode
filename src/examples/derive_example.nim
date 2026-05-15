# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH
#
# ``deriveBincode`` demo: string, enum, Vec-like ``seq[T]``, bytes newtypes, mixed structs.
# (In Rust you would use ``String``, an enum, ``Vec<u8>`` / ``Vec<String>``, and a struct.)
#
# Run: nim c -r src/examples/derive_example.nim
#  or: make examples

{.push gcsafe.}

import faststreams
import stew/byteutils
import ../bincode
import ../bincode_config
import ../bincode_derive

# --- Single-kind types (one field each, easy to read on the wire) -------------

type Named* = object
  ## ``String`` on the wire: length prefix + UTF-8 bytes.
  label*: string

deriveBincode(Named)

type Status* = enum
  ## Enum on the wire: plain ``u32`` discriminant (declaration order).
  Active
  Paused
  Done

deriveBincode(Status)

type Blob* = object
  ## ``Vec<u8>`` on the wire: length prefix + raw bytes (``seq[byte]``).
  data*: seq[byte]

deriveBincode(Blob)

type TagList* = object
  ## ``Vec<String>`` on the wire: length + each string (length-prefixed UTF-8).
  names*: seq[string]

deriveBincode(TagList)

# --- Mixed struct: string + enum + Vec<u8> + Vec<String> + nested object ------

type Record* = object
  title*: string
  state*: Status
  payload*: seq[byte]
  aliases*: seq[string]
  extra*: Named

deriveBincode(Record)

# --- Bytes newtype (e.g. libp2p ``EdPublicKey``: ``data: array[N, byte]``) -------

const DigestSize = 32

type Digest* = object
  ## Fixed-size blob in one field — same shape as ``EdPublicKey``; no extra derive.
  data*: array[DigestSize, byte]

type Row* = object
  id*: Digest
  seq*: uint64

deriveBincode(Row)

proc demoString(cfg: BincodeConfig) {.raises: [BincodeError, IOError].} =
  echo "== string (Named.label) =="
  let v = Named(label: "hello-bincode")
  let wire = serializeNamedToSeq(v, cfg)
  echo "  wire (", wire.len, " bytes): ", wire.toHex
  let back = deserializeNamed(wire, cfg)
  echo "  back: ", back.label
  doAssert back == v
  echo "  OK\n"

proc demoEnum(cfg: BincodeConfig) {.raises: [BincodeError, IOError].} =
  echo "== enum (Status) =="
  let v = Status.Paused
  let wire = serializeStatusToSeq(v, cfg)
  echo "  wire (", wire.len, " bytes): ", wire.toHex
  let back = deserializeStatus(wire, cfg)
  echo "  back: ", back
  doAssert back == v
  echo "  OK\n"

proc demoVecByte(cfg: BincodeConfig) {.raises: [BincodeError, IOError].} =
  echo "== Vec<u8> / seq[byte] (Blob.data) =="
  let v = Blob(data: @[byte(1), 2, 3, 0xFF])
  var stream = memoryOutput()
  serializeBlob(stream, v, cfg)
  let wire = stream.getOutput()
  echo "  wire (", wire.len, " bytes): ", wire.toHex
  let back = deserializeBlob(wire, cfg)
  echo "  back: ", back.data
  doAssert back == v
  echo "  OK\n"

proc demoVecString(cfg: BincodeConfig) {.raises: [BincodeError, IOError].} =
  echo "== Vec<String> / seq[string] (TagList.names) =="
  let v = TagList(names: @["alpha", "beta", "gamma"])
  let wire = serializeTagListToSeq(v, cfg)
  echo "  wire (", wire.len, " bytes): ", wire.toHex
  let back = deserializeTagList(wire, cfg)
  echo "  back: ", back.names
  doAssert back == v
  echo "  OK\n"

proc demoMixedRecord(cfg: BincodeConfig) {.raises: [BincodeError, IOError].} =
  echo "== mixed struct (Record: string + enum + seq[byte] + seq[string] + nested) =="
  let v = Record(
    title: "widget",
    state: Status.Active,
    payload: @[byte(0xCA), 0xFE],
    aliases: @["w1", "primary"],
    extra: Named(label: "nested-string"),
  )
  let wire = serializeRecordToSeq(v, cfg)
  echo "  wire (", wire.len, " bytes): ", wire.toHex
  let back = deserializeRecord(wire, cfg)
  echo "  title=", back.title, " state=", back.state
  echo "  payload=", back.payload, " aliases=", back.aliases
  echo "  extra.label=", back.extra.label
  doAssert back == v
  echo "  OK\n"

proc demoBytesNewtype(cfg: BincodeConfig) {.raises: [BincodeError, IOError].} =
  echo "== bytes newtype (Digest.data → ", DigestSize, " raw bytes + Row.seq) =="
  var digest: Digest
  for i in 0 ..< DigestSize:
    digest.data[i] = byte(i + 1)
  let v = Row(id: digest, seq: 100'u64)
  let wire = serializeRowToSeq(v, cfg)
  echo "  wire (", wire.len, " bytes): ", wire.toHex
  echo "  layout: ", DigestSize, " byte id + 8 byte seq (fixed u64)"
  let back = deserializeRow(wire, cfg)
  echo "  back.seq=", back.seq
  echo "  back.id.data=", back.id.data.toHex
  doAssert back == v
  echo "  OK\n"

proc demoDeserializeAt(cfg: BincodeConfig) {.raises: [BincodeError, IOError].} =
  echo "== two Records in one buffer (deserializeRecordAt) =="
  let r1 = Record(
    title: "a",
    state: Status.Done,
    payload: @[1'u8],
    aliases: @["x"],
    extra: Named(label: "e1"),
  )
  let r2 = Record(
    title: "bb",
    state: Status.Paused,
    payload: @[2'u8, 3],
    aliases: @["y", "z"],
    extra: Named(label: "e2"),
  )
  let blob = serializeRecordToSeq(r1, cfg) & serializeRecordToSeq(r2, cfg)
  echo "  blob (", blob.len, " bytes): ", blob.toHex
  var off = 0
  let (a, n1) = deserializeRecordAt(blob, cfg, off)
  off += n1
  let (b, n2) = deserializeRecordAt(blob, cfg, off)
  off += n2
  doAssert off == blob.len
  echo "  first.title=", a.title, " second.title=", b.title
  echo "  consumed ", n1 + n2, " / ", blob.len, " bytes\n"

proc main() {.raises: [BincodeError, IOError, BincodeConfigError].} =
  echo "deriveBincode example: string, enum, Vec (seq), bytes newtype, mixed structs\n"
  echo "Wire layout: fields in declaration order, no field names on the wire."
  echo "Config: little-endian, fixed 8-byte length prefixes\n"

  let cfg =
    standard().withLittleEndian().withFixedIntEncoding(8).withLimit(65536'u64)

  demoString(cfg)
  demoEnum(cfg)
  demoVecByte(cfg)
  demoVecString(cfg)
  demoMixedRecord(cfg)
  demoBytesNewtype(cfg)
  demoDeserializeAt(cfg)

  echo "All demos passed."

main()

{.pop.}
