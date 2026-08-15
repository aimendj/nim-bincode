# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import faststreams
import bincode

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

  let cfg = standard().withLittleEndian().withFixedIntEncoding(8).withLimit(65536'u64)

  let person = Person(name: "Alice", age: 30'u32, email: "alice@example.com")
  let personWire = encode(person, cfg)
  let personBack = decode(personWire, Person, cfg)
  echo "Person roundtrip: ",
    personBack.name, " ", personBack.age, " ", personBack.email, " (", personWire.len,
    " bytes)"

  let statusWire = encode(Status.Pending, cfg)
  doAssert decode(statusWire, Status, cfg) == Status.Pending
  echo "Status roundtrip OK (", statusWire.len, " byte(s))"

  let packet = Packet(id: 7'u32, flags: @[byte(1), 2, 3], score: 3.14'f32)
  let packetWire = encode(packet, cfg)
  let packetBack = decode(packetWire, Packet, cfg)
  echo "Packet roundtrip: id=",
    packetBack.id, " flags=", packetBack.flags, " score=", packetBack.score, " (",
    packetWire.len, " bytes)"

  let data = @[byte(1), 2, 3, 4, 5]
  var dataStream = memoryOutput()
  encode(dataStream, data, cfg)
  echo "Raw bytes roundtrip: ", decode(dataStream.getOutput(), cfg) == data

main()

{.pop.}
