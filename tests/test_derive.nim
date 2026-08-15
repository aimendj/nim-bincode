# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import unittest2
import faststreams
import std/options
import bincode

type CustomId = distinct uint64

type OptionItem = object
  id: CustomId
  optTag: Option[string]
  optVal: Option[uint32]

deriveBincode(OptionItem)

type Person = object
  name: string
  age: uint32

deriveBincode(Person)

type RefNodeObj = object
  val: int32
  label: string

type RefNode = ref RefNodeObj

deriveBincode(RefNodeObj)

type HoleyEnum = enum
  HoleyA = 10
  HoleyB = 20

deriveBincode(HoleyEnum)

type Status = enum
  Active
  Inactive
  Pending

deriveBincode(Status)

type Packet = object
  id: uint32
  flags: seq[byte]
  score: float32

deriveBincode(Packet)

const FakeKeySize = 32

type FakePublicKey* = object
  data*: array[FakeKeySize, byte]

deriveBincode(FakePublicKey)

type BlockHeader* = object
  author*: FakePublicKey
  height*: uint64

deriveBincode(BlockHeader)

const FakeSigSize = 64

type FakeSignature* = object
  data*: array[FakeSigSize, byte]

deriveBincode(FakeSignature, lengthPrefixed = true)

type SignedBlockHeader* = object
  header*: BlockHeader
  sig*: FakeSignature

deriveBincode(SignedBlockHeader)

type SigWrapper* = object
  sig*: FakeSignature

deriveBincode(SigWrapper)

type KeyWrapper* = object
  key*: FakePublicKey

deriveBincode(KeyWrapper)

type
  Hash32* = array[32, byte]
  References* = array[4, Hash32]
  Proposal* = object
    references*: References
    value*: uint64

deriveBincode(Proposal)

type SeqArrayObj* = object
  matrix*: seq[array[3, uint32]]

deriveBincode(SeqArrayObj)

type
  ActionTag* = enum
    atPing
    atTransfer

  ActionMsg* = object
    case tag*: ActionTag
    of atPing:
      nonce*: uint64
    of atTransfer:
      recipient*: string
      amount*: uint64

deriveBincode(ActionMsg)

type
  CustomPayload* = object
    raw*: string

  CustomDecodeError* = object of CatchableError

func toBytes*(c: CustomPayload): seq[byte] =
  result = newSeq[byte](c.raw.len)
  if c.raw.len > 0:
    copyMem(result[0].addr, c.raw[0].unsafeAddr, c.raw.len)

func fromBytes*(b: openArray[byte]): CustomPayload {.raises: [CustomDecodeError].} =
  if b.len == 1 and b[0] == 0xFF'u8:
    raise (ref CustomDecodeError)(msg: "Corrupted custom payload")
  var s = newString(b.len)
  if b.len > 0:
    copyMem(s[0].addr, b[0].unsafeAddr, b.len)
  CustomPayload(raw: s)

deriveBincodeCustom(CustomPayload, toBytes, fromBytes, CustomDecodeError)

type Envelope* = object
  id*: uint64
  payload*: CustomPayload
  extra*: seq[CustomPayload]

deriveBincode(Envelope)

suite "deriveBincode":
  let cfg = standard().withLittleEndian().withFixedIntEncoding(8).withLimit(65536'u64)

  test "roundtrip Person":
    let p = Person(name: "Bob", age: 25'u32)
    let wire = encode(p, cfg)
    let back = decode(wire, Person, cfg)
    check back.name == "Bob"
    check back.age == 25'u32

  test "roundtrip Person via Bincode.encode/decode":
    let p = Person(name: "Alice", age: 30'u32)
    let wire = Bincode.encode(p)
    let back = Bincode.decode(wire, Person)
    check back.name == "Alice"
    check back.age == 30'u32

  test "roundtrip Status":
    let wire = encode(Status.Pending, cfg)
    check decode(wire, Status, cfg) == Status.Pending

  test "roundtrip Packet":
    let pkt = Packet(id: 1'u32, flags: @[byte(9), 8], score: 1.5'f32)
    let wire = encode(pkt, cfg)
    let back = decode(wire, Packet, cfg)
    check back.id == 1'u32
    check back.flags == @[byte(9), 8]
    check abs(back.score - 1.5'f32) < 1e-5'f32

  test "roundtrip BlockHeader with byte-wrapper pubkey":
    var key: FakePublicKey
    for i in 0 ..< FakeKeySize:
      key.data[i] = byte(i + 1)
    let hdr = BlockHeader(author: key, height: 42'u64)
    let wire = encode(hdr, cfg)
    check wire.len == FakeKeySize + 8
    let back = decode(wire, BlockHeader, cfg)
    check back.height == 42'u64
    check back.author.data == key.data

  test "roundtrip FakeSignature with lengthPrefixed":
    var sig: FakeSignature
    for i in 0 ..< FakeSigSize:
      sig.data[i] = byte(i)
    let wire = encode(sig, cfg)
    check wire.len == 8 + FakeSigSize
    let back = decode(wire, FakeSignature, cfg)
    check back.data == sig.data

  test "nested FakeSignature uses its own lengthPrefixed flag":
    var key: FakePublicKey
    for i in 0 ..< FakeKeySize:
      key.data[i] = byte(i + 1)
    var sig: FakeSignature
    for i in 0 ..< FakeSigSize:
      sig.data[i] = byte(i)
    let hdr = BlockHeader(author: key, height: 7'u64)
    let signed = SignedBlockHeader(header: hdr, sig: sig)
    let wire = encode(signed, cfg)
    check wire.len == FakeKeySize + 8 + 8 + FakeSigSize
    let back = decode(wire, SignedBlockHeader, cfg)
    check back.header.height == 7'u64
    check back.header.author.data == key.data
    check back.sig.data == sig.data

  test "parent A serializes nested B via encode (lengthPrefixed sig)":
    var sig: FakeSignature
    for i in 0 ..< FakeSigSize:
      sig.data[i] = byte(i + 10)
    let parent = SigWrapper(sig: sig)
    check encode(parent, cfg) == encode(sig, cfg)

  test "parent A serializes nested B via encode (raw pubkey)":
    var key: FakePublicKey
    for i in 0 ..< FakeKeySize:
      key.data[i] = byte(i + 20)
    let parent = KeyWrapper(key: key)
    check encode(parent, cfg) == encode(key, cfg)

  test "parent A first field bytes match standalone encode (BlockHeader)":
    var key: FakePublicKey
    for i in 0 ..< FakeKeySize:
      key.data[i] = byte(i + 30)
    let hdr = BlockHeader(author: key, height: 99'u64)
    let hdrWire = encode(hdr, cfg)
    let keyWire = encode(key, cfg)
    check hdrWire.len == keyWire.len + 8
    check hdrWire[0 ..< keyWire.len] == keyWire

  test "parent A deserializes nested B via decodeAt (lengthPrefixed sig)":
    var sig: FakeSignature
    for i in 0 ..< FakeSigSize:
      sig.data[i] = byte(i + 40)
    let sigWire = encode(sig, cfg)
    let pad = @[byte(0xAA), byte(0xBB)]
    let data = pad & sigWire & pad
    let (fromParent, nParent) = decodeAt(data, SigWrapper, cfg, pad.len)
    let (fromChild, nChild) = decodeAt(data, FakeSignature, cfg, pad.len)
    check fromParent.sig.data == sig.data
    check fromChild.data == sig.data
    check nParent == sigWire.len
    check nChild == nParent

  test "parent A deserializes nested B via decodeAt (raw pubkey)":
    var key: FakePublicKey
    for i in 0 ..< FakeKeySize:
      key.data[i] = byte(i + 50)
    let keyWire = encode(key, cfg)
    let pad = @[byte(0xCC)]
    let data = pad & keyWire & pad
    let (fromParent, nParent) = decodeAt(data, KeyWrapper, cfg, pad.len)
    let (fromChild, nChild) = decodeAt(data, FakePublicKey, cfg, pad.len)
    check fromParent.key.data == key.data
    check fromChild.data == key.data
    check nParent == keyWire.len
    check nChild == nParent

  test "Packet flags still length-prefixed when lengthPrefixed false":
    let pkt = Packet(id: 0'u32, flags: @[byte(1), 2, 3], score: 0'f32)
    let wire = encode(pkt, cfg)
    check wire.len > 3 + 8

  test "roundtrip Proposal (nested 2D array)":
    var prop: Proposal
    for i in 0 ..< 4:
      for j in 0 ..< 32:
        prop.references[i][j] = byte(i * 32 + j)
    prop.value = 1337'u64
    let wire = encode(prop, cfg)
    check wire.len == 4 * 32 + 8
    let back = decode(wire, Proposal, cfg)
    check back.value == 1337'u64
    check back.references == prop.references

  test "roundtrip SeqArrayObj (sequence of arrays)":
    var obj = SeqArrayObj(matrix: @[[1'u32, 2, 3], [4'u32, 5, 6]])
    let wire = encode(obj, cfg)
    check wire.len == 32
    let back = decode(wire, SeqArrayObj, cfg)
    check back.matrix == obj.matrix

  test "roundtrip empty Packet flags (empty nested seq)":
    let pkt = Packet(id: 10'u32, flags: @[], score: 1.23'f32)
    let wire = encode(pkt, cfg)
    let back = decode(wire, Packet, cfg)
    check back.id == 10'u32
    check back.flags.len == 0
    check back.score == 1.23'f32

  test "roundtrip RefNodeObj (object behind ref)":
    let node = RefNode(val: 99'i32, label: "test-ref")
    let wire = encode(node[], cfg)
    let back = decode(wire, RefNodeObj, cfg)
    check back.val == 99'i32
    check back.label == "test-ref"

  test "roundtrip OptionItem (Option[T] and distinct type)":
    let item1 =
      OptionItem(id: CustomId(42'u64), optTag: some("tag-a"), optVal: some(100'u32))
    let wire1 = encode(item1, cfg)
    let back1 = decode(wire1, OptionItem, cfg)
    check back1.id.uint64 == 42'u64
    check back1.optTag.isSome and back1.optTag.get() == "tag-a"
    check back1.optVal.isSome and back1.optVal.get() == 100'u32

    let item2 =
      OptionItem(id: CustomId(99'u64), optTag: none(string), optVal: none(uint32))
    let wire2 = encode(item2, cfg)
    let back2 = decode(wire2, OptionItem, cfg)
    check back2.id.uint64 == 99'u64
    check back2.optTag.isNone
    check back2.optVal.isNone

  test "roundtrip HoleyEnum and reject unassigned discriminant hole":
    let wireA = encode(HoleyEnum.HoleyA, cfg)
    check decode(wireA, HoleyEnum, cfg) == HoleyEnum.HoleyA

    let wireB = encode(HoleyEnum.HoleyB, cfg)
    check decode(wireB, HoleyEnum, cfg) == HoleyEnum.HoleyB

    let invalidHoleWire =
      @[0x05'u8, 0x00, 0x00, 0x00]
        # Discriminant 5 is an unassigned hole between 10 and 20
    expect BincodeError:
      discard decode(invalidHoleWire, HoleyEnum, cfg)

  test "roundtrip ActionMsg variant with custom discriminant name (tag)":
    let msg1 = ActionMsg(tag: atPing, nonce: 12345'u64)
    let wire1 = encode(msg1, cfg)
    let back1 = decode(wire1, ActionMsg, cfg)
    check back1.tag == atPing
    check back1.nonce == 12345'u64

    let msg2 = ActionMsg(tag: atTransfer, recipient: "Alice", amount: 500'u64)
    let wire2 = encode(msg2, cfg)
    let back2 = decode(wire2, ActionMsg, cfg)
    check back2.tag == atTransfer
    check back2.recipient == "Alice"
    check back2.amount == 500'u64

  test "decode into var T rejects trailing bytes":
    let p = Person(name: "Charlie", age: 40'u32)
    let wire = encode(p, cfg)
    let badWire = wire & @[0xFF'u8, 0xFE]
    var back: Person
    expect BincodeError:
      decode(badWire, back, cfg)

  test "roundtrip deriveBincodeCustom standalone":
    let cp = CustomPayload(raw: "hello custom")
    let wire = encode(cp, cfg)
    let back = decode(wire, CustomPayload, cfg)
    check back.raw == "hello custom"

  test "roundtrip deriveBincodeCustom via Bincode.encode/decode":
    let cp = CustomPayload(raw: "via nim-serialization")
    let wire = Bincode.encode(cp)
    let back = Bincode.decode(wire, CustomPayload)
    check back.raw == "via nim-serialization"

  test "roundtrip deriveBincode with nested deriveBincodeCustom":
    let env = Envelope(
      id: 42'u64,
      payload: CustomPayload(raw: "nested payload"),
      extra: @[CustomPayload(raw: "item 1"), CustomPayload(raw: "item 2")],
    )
    let wire = encode(env, cfg)
    let back = decode(wire, Envelope, cfg)
    check back.id == 42'u64
    check back.payload.raw == "nested payload"
    check back.extra.len == 2
    check back.extra[0].raw == "item 1"
    check back.extra[1].raw == "item 2"

  test "deriveBincodeCustom re-raises custom decode error as BincodeError":
    # 0xFF as payload triggers CustomDecodeError in fromBytes
    let badPayloadWire = encode(@[0xFF'u8], cfg) # length-prefixed seq of 0xFF
    expect BincodeError:
      discard decode(badPayloadWire, CustomPayload, cfg)

  test "deriveBincodeCustom rejects trailing bytes":
    let cp = CustomPayload(raw: "valid")
    let wire = encode(cp, cfg)
    let badWire = wire & @[0x12'u8, 0x34]
    expect BincodeError:
      discard decode(badWire, CustomPayload, cfg)

type UnderivedStruct = object
  x: int32
  y: string

deriveBincode(UnderivedStruct)

# Complex generic protocol & network types
type
  NodeId = array[20, byte]
  PacketHash = array[32, byte]

  MessageKind = enum
    mkPing
    mkRequest
    mkResponse
    mkBatch

  NetworkMessage = object
    case kind: MessageKind
    of mkPing:
      nonce: uint64
      timestamp: uint64
      sender: Option[NodeId]
      extraData: seq[byte]
    of mkRequest, mkResponse:
      requestId: uint64
      channel: uint32
      target: Option[NodeId]
      payload: seq[byte]
      routePath: seq[NodeId]
    of mkBatch:
      batchId: uint64
      hashes: seq[PacketHash]

deriveBincode(NetworkMessage)

suite "Complex Multi-Variant and Nested Protocol Messages":
  test "roundtrip mkPing message":
    let msg = NetworkMessage(
      kind: mkPing,
      nonce: 10'u64,
      timestamp: 1700000000'u64,
      sender:
        some([1'u8, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]),
      extraData: @[0xa9'u8, 0x05, 0x9c, 0xbb],
    )
    let wire = encode(msg)
    let back = decode(wire, NetworkMessage)
    check back.kind == mkPing
    check back.nonce == 10'u64
    check back.timestamp == 1700000000'u64
    check back.sender.isSome
    check back.sender.get()[0] == 1'u8
    check back.extraData == @[0xa9'u8, 0x05, 0x9c, 0xbb]

  test "roundtrip mkResponse message via Bincode.encode/decode":
    let msg = NetworkMessage(
      kind: mkResponse,
      requestId: 42'u64,
      channel: 1'u32,
      target: none(NodeId),
      payload: @[],
      routePath:
        @[[0xaa'u8, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19]],
    )
    let wire = Bincode.encode(msg)
    let back = Bincode.decode(wire, NetworkMessage)
    check back.kind == mkResponse
    check back.requestId == 42'u64
    check back.channel == 1'u32
    check back.target.isNone
    check back.routePath.len == 1
    check back.routePath[0][0] == 0xaa'u8

  test "roundtrip mkBatch with multiple 32-byte hashes":
    var h1, h2: PacketHash
    h1[0] = 0x01
    h2[0] = 0x02
    let msg = NetworkMessage(kind: mkBatch, batchId: 99'u64, hashes: @[h1, h2])
    let wire = encode(msg)
    let back = decode(wire, NetworkMessage)
    check back.kind == mkBatch
    check back.batchId == 99'u64
    check back.hashes.len == 2
    check back.hashes[0][0] == 0x01
    check back.hashes[1][0] == 0x02

{.pop.}
