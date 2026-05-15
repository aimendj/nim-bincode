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

type BlockHeader* = object
  author*: FakePublicKey
  height*: uint64

deriveBincode(BlockHeader)

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

{.pop.}
