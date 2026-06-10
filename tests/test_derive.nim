# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import std/unittest
import faststreams
import bincode
import bincode_config
import bincode_derive

type Person = object
  name: string
  age: uint32

deriveBincode(Person)

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

suite "deriveBincode":
  let cfg =
    standard().withLittleEndian().withFixedIntEncoding(8).withLimit(65536'u64)

  test "roundtrip Person":
    let p = Person(name: "Bob", age: 25'u32)
    let wire = serializePersonToSeq(p, cfg)
    let back = deserializePerson(wire, cfg)
    check back.name == "Bob"
    check back.age == 25'u32

  test "roundtrip Status":
    let wire = serializeStatusToSeq(Status.Pending, cfg)
    check deserializeStatus(wire, cfg) == Status.Pending

  test "roundtrip Packet":
    let pkt = Packet(id: 1'u32, flags: @[byte(9), 8], score: 1.5'f32)
    let wire = serializePacketToSeq(pkt, cfg)
    let back = deserializePacket(wire, cfg)
    check back.id == 1'u32
    check back.flags == @[byte(9), 8]
    check abs(back.score - 1.5'f32) < 1e-5'f32

  test "roundtrip BlockHeader with byte-wrapper pubkey":
    var key: FakePublicKey
    for i in 0 ..< FakeKeySize:
      key.data[i] = byte(i + 1)
    let hdr = BlockHeader(author: key, height: 42'u64)
    let wire = serializeBlockHeaderToSeq(hdr, cfg)
    check wire.len == FakeKeySize + 8
    let back = deserializeBlockHeader(wire, cfg)
    check back.height == 42'u64
    check back.author.data == key.data

  test "roundtrip FakeSignature with lengthPrefixed":
    var sig: FakeSignature
    for i in 0 ..< FakeSigSize:
      sig.data[i] = byte(i)
    let wire = serializeFakeSignatureToSeq(sig, cfg)
    check wire.len == 8 + FakeSigSize
    let back = deserializeFakeSignature(wire, cfg)
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
    let wire = serializeSignedBlockHeaderToSeq(signed, cfg)
    check wire.len == FakeKeySize + 8 + 8 + FakeSigSize
    let back = deserializeSignedBlockHeader(wire, cfg)
    check back.header.height == 7'u64
    check back.header.author.data == key.data
    check back.sig.data == sig.data

  test "parent A serializes nested B via serializeB (lengthPrefixed sig)":
    var sig: FakeSignature
    for i in 0 ..< FakeSigSize:
      sig.data[i] = byte(i + 10)
    let parent = SigWrapper(sig: sig)
    check serializeSigWrapperToSeq(parent, cfg) == serializeFakeSignatureToSeq(sig, cfg)

  test "parent A serializes nested B via serializeB (raw pubkey)":
    var key: FakePublicKey
    for i in 0 ..< FakeKeySize:
      key.data[i] = byte(i + 20)
    let parent = KeyWrapper(key: key)
    check serializeKeyWrapperToSeq(parent, cfg) == serializeFakePublicKeyToSeq(key, cfg)

  test "parent A first field bytes match standalone serializeB (BlockHeader)":
    var key: FakePublicKey
    for i in 0 ..< FakeKeySize:
      key.data[i] = byte(i + 30)
    let hdr = BlockHeader(author: key, height: 99'u64)
    let hdrWire = serializeBlockHeaderToSeq(hdr, cfg)
    let keyWire = serializeFakePublicKeyToSeq(key, cfg)
    check hdrWire.len == keyWire.len + 8
    check hdrWire[0 ..< keyWire.len] == keyWire

  test "parent A deserializes nested B via deserializeBAt (lengthPrefixed sig)":
    var sig: FakeSignature
    for i in 0 ..< FakeSigSize:
      sig.data[i] = byte(i + 40)
    let sigWire = serializeFakeSignatureToSeq(sig, cfg)
    let pad = @[byte(0xAA), byte(0xBB)]
    let data = pad & sigWire & pad
    let (fromParent, nParent) = deserializeSigWrapperAt(data, cfg, pad.len)
    let (fromChild, nChild) = deserializeFakeSignatureAt(data, cfg, pad.len)
    check fromParent.sig.data == sig.data
    check fromChild.data == sig.data
    check nParent == sigWire.len
    check nChild == nParent

  test "parent A deserializes nested B via deserializeBAt (raw pubkey)":
    var key: FakePublicKey
    for i in 0 ..< FakeKeySize:
      key.data[i] = byte(i + 50)
    let keyWire = serializeFakePublicKeyToSeq(key, cfg)
    let pad = @[byte(0xCC)]
    let data = pad & keyWire & pad
    let (fromParent, nParent) = deserializeKeyWrapperAt(data, cfg, pad.len)
    let (fromChild, nChild) = deserializeFakePublicKeyAt(data, cfg, pad.len)
    check fromParent.key.data == key.data
    check fromChild.data == key.data
    check nParent == keyWire.len
    check nChild == nParent

  test "Packet flags still length-prefixed when lengthPrefixed false":
    let pkt = Packet(id: 0'u32, flags: @[byte(1), 2, 3], score: 0'f32)
    let wire = serializePacketToSeq(pkt, cfg)
    check wire.len > 3 + 8

{.pop.}
