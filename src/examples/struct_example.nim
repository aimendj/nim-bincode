# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import faststreams # Uses: memoryOutput, getOutput
import ../bincode
import ../bincode_config

type Person* = object
  name*: string
  age*: uint32
  email*: string

proc serializePerson*(
    stream: OutputStreamHandle, p: Person, config: BincodeConfig
) {.raises: [BincodeError, IOError].} =
  ## Serialize ``Person`` in Rust bincode v2 field order: ``name``, ``age``, ``email``.
  ## Strings use the same length-prefixed UTF-8 layout as `serializeString`_.
  ## ``age`` uses a plain ``u32`` (see `serializeBincodeU32`_), not ``Vec<u8>``.
  serializeString(stream, p.name, config)
  serializeBincodeU32(stream, p.age, config)
  serializeString(stream, p.email, config)

func deserializePerson*(data: openArray[byte], config: BincodeConfig): Person {.raises: [BincodeError].} =
  var off = 0
  let (name, n1) = decodePrefixedString(data, config, off)
  off += n1
  let (age, n2) = decodeBincodeU32(data, config, off)
  off += n2
  let (email, n3) = decodePrefixedString(data, config, off)
  off += n3
  if off != data.len:
    raise newException(BincodeError, "Trailing bytes after struct fields")
  Person(name: name, age: age, email: email)

proc serializePersonToSeq*(p: Person, config: BincodeConfig): seq[byte] {.raises: [BincodeError, IOError].} =
  var stream = memoryOutput()
  serializePerson(stream, p, config)
  stream.getOutput()

proc main() {.raises: [BincodeError, IOError, BincodeConfigError].} =
  echo "=== Struct example (Rust bincode v2 field layout) ===\n"

  let cfg =
    standard().withLittleEndian().withFixedIntEncoding(8).withLimit(65536'u64)

  let person = Person(name: "Alice", age: 30'u32, email: "alice@example.com")

  echo "Original person:"
  echo "  name: ", person.name
  echo "  age: ", person.age
  echo "  email: ", person.email

  let encoded = serializePersonToSeq(person, cfg)
  echo "\nSerialized length: ", encoded.len, " bytes"

  let decoded = deserializePerson(encoded, cfg)
  echo "\nDeserialized person:"
  echo "  name: ", decoded.name
  echo "  age: ", decoded.age
  echo "  email: ", decoded.email
  echo "Match: ",
    (
      person.name == decoded.name and person.age == decoded.age and
      person.email == decoded.email
    )

  let data = @[byte(1), 2, 3, 4, 5, 100, 200, 255]
  echo "\nOriginal bytes: ", data

  var dataStream = memoryOutput()
  serialize(dataStream, data, cfg)
  let encodedBytes = dataStream.getOutput()
  echo "Encoded length: ", encodedBytes.len, " bytes"

  let decodedBytes2 = deserialize(encodedBytes, cfg)
  echo "Decoded bytes: ", decodedBytes2
  echo "Match: ", data == decodedBytes2

main()

{.pop.}
