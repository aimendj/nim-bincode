# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import faststreams
import ../bincode
import ../bincode_config
import ../bincode_derive

type Person* = object
  name*: string
  age*: uint32
  email*: string

deriveBincode(Person)

type Status* = enum
  Active
  Inactive
  Pending

deriveBincode(Status)

type Packet* = object
  id*: uint32
  flags*: seq[byte]
  score*: float32

deriveBincode(Packet)

proc main() {.raises: [BincodeError, IOError, BincodeConfigError].} =
  echo "=== Struct example (deriveBincode) ===\n"

  let cfg =
    standard().withLittleEndian().withFixedIntEncoding(8).withLimit(65536'u64)

  let person = Person(name: "Alice", age: 30'u32, email: "alice@example.com")
  let personWire = serializePersonToSeq(person, cfg)
  let personBack = deserializePerson(personWire, cfg)
  echo "Person roundtrip: ",
    personBack.name, " ", personBack.age, " ", personBack.email,
    " (", personWire.len, " bytes)"

  let statusWire = serializeStatusToSeq(Status.Pending, cfg)
  doAssert deserializeStatus(statusWire, cfg) == Status.Pending
  echo "Status roundtrip OK (", statusWire.len, " byte(s))"

  let packet = Packet(id: 7'u32, flags: @[byte(1), 2, 3], score: 3.14'f32)
  let packetWire = serializePacketToSeq(packet, cfg)
  let packetBack = deserializePacket(packetWire, cfg)
  echo "Packet roundtrip: id=", packetBack.id, " flags=", packetBack.flags,
    " score=", packetBack.score, " (", packetWire.len, " bytes)"

  let data = @[byte(1), 2, 3, 4, 5]
  var dataStream = memoryOutput()
  serialize(dataStream, data, cfg)
  echo "Raw bytes roundtrip: ", deserialize(dataStream.getOutput(), cfg) == data

main()

{.pop.}
