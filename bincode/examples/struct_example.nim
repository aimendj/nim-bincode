# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import ../nim_bincode

type Person* = object
  name*: string
  age*: uint32
  email*: string

proc personToBytes(p: Person): seq[byte] =
  var nameLenBytes =
    @[
      byte(p.name.len and 0xFF),
      byte((p.name.len shr 8) and 0xFF),
      byte((p.name.len shr 16) and 0xFF),
      byte((p.name.len shr 24) and 0xFF),
    ]
  var nameBytes = newSeq[byte](p.name.len)
  for i in 0 ..< p.name.len:
    nameBytes[i] = byte(p.name[i])

  var ageBytes =
    @[
      byte(p.age and 0xFF),
      byte((p.age shr 8) and 0xFF),
      byte((p.age shr 16) and 0xFF),
      byte((p.age shr 24) and 0xFF),
    ]

  var emailLenBytes =
    @[
      byte(p.email.len and 0xFF),
      byte((p.email.len shr 8) and 0xFF),
      byte((p.email.len shr 16) and 0xFF),
      byte((p.email.len shr 24) and 0xFF),
    ]
  var emailBytes = newSeq[byte](p.email.len)
  for i in 0 ..< p.email.len:
    emailBytes[i] = byte(p.email[i])

  return nameLenBytes & nameBytes & ageBytes & emailLenBytes & emailBytes

proc bytesToPerson(data: openArray[byte]): Person =
  var offset = 0
  var person: Person

  if data.len >= offset + 4:
    let nameLen =
      (data[offset].uint32) or (data[offset + 1].uint32 shl 8) or
      (data[offset + 2].uint32 shl 16) or (data[offset + 3].uint32 shl 24)
    offset += 4

    if data.len >= offset + int(nameLen):
      person.name = newString(int(nameLen))
      for i in 0 ..< int(nameLen):
        person.name[i] = char(data[offset + i])
      offset += int(nameLen)

  if data.len >= offset + 4:
    person.age =
      (data[offset].uint32) or (data[offset + 1].uint32 shl 8) or
      (data[offset + 2].uint32 shl 16) or (data[offset + 3].uint32 shl 24)
    offset += 4

  if data.len >= offset + 4:
    let emailLen =
      (data[offset].uint32) or (data[offset + 1].uint32 shl 8) or
      (data[offset + 2].uint32 shl 16) or (data[offset + 3].uint32 shl 24)
    offset += 4

    if data.len >= offset + int(emailLen):
      person.email = newString(int(emailLen))
      for i in 0 ..< int(emailLen):
        person.email[i] = char(data[offset + i])

  return person

proc main() =
  echo "=== Struct Example (like Rust direct_example.rs) ===\n"

  let person = Person(name: "Alice", age: 30'u32, email: "alice@example.com")

  echo "Original person:"
  echo "  name: ", person.name
  echo "  age: ", person.age
  echo "  email: ", person.email

  let encoded = serializeType(person, personToBytes)

  echo "\nSerialized length: ", encoded.len, " bytes"
  echo "Serialized bytes: ", encoded

  let decoded = deserializeType(encoded, bytesToPerson)

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

  let encodedBytes = serialize(data)
  echo "Encoded length: ", encodedBytes.len, " bytes"

  let decodedBytes2 = deserialize(encodedBytes)
  echo "Decoded bytes: ", decodedBytes2
  echo "Match: ", data == decodedBytes2

main()

{.pop.}
