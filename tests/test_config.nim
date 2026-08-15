# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import faststreams
import unittest2
import bincode

proc encodeToSeq(
    data: openArray[byte], config: BincodeConfig = standard()
): seq[byte] {.raises: [BincodeError, IOError].} =
  var stream = memoryOutput()
  encode(stream, data, config)
  stream.getOutput()

suite "Bincode Config Builder":
  test "standard config has correct defaults":
    let config = standard()
    check config.byteOrder == LittleEndian
    check config.intSize == 8
    check config.sizeLimit == BINCODE_SIZE_LIMIT

  test "withLittleEndian sets byte order":
    let config = standard().withLittleEndian()
    check config.byteOrder == LittleEndian

  test "withBigEndian sets byte order":
    let config = standard().withBigEndian()
    check config.byteOrder == BigEndian

  test "withFixedIntEncoding valid sizes":
    check standard().withFixedIntEncoding(1).intSize == 1
    check standard().withFixedIntEncoding(2).intSize == 2
    check standard().withFixedIntEncoding(4).intSize == 4
    check standard().withFixedIntEncoding(8).intSize == 8
    check standard().withFixedIntEncoding(0).intSize == 0

  test "withFixedIntEncoding invalid size raises BincodeConfigError":
    expect BincodeConfigError:
      discard standard().withFixedIntEncoding(3)
    expect BincodeConfigError:
      discard standard().withFixedIntEncoding(5)
    expect BincodeConfigError:
      discard standard().withFixedIntEncoding(7)
    expect BincodeConfigError:
      discard standard().withFixedIntEncoding(9)
    expect BincodeConfigError:
      discard standard().withFixedIntEncoding(-1)

  test "withVariableIntEncoding sets intSize to 0":
    let config = standard().withVariableIntEncoding()
    check config.intSize == 0

  test "withLimit sets size limit":
    let config = standard().withLimit(1024'u64)
    check config.sizeLimit == 1024'u64

  test "config builder chaining":
    let config = standard().withBigEndian().withFixedIntEncoding(4).withLimit(2048'u64)
    check config.byteOrder == BigEndian
    check config.intSize == 4
    check config.sizeLimit == 2048'u64

suite "Config Wire Byte Representations":
  test "little-endian vs big-endian int32 wire output":
    let val: uint32 = 0x12345678'u32
    let leWire = encode(val, standard().withLittleEndian())
    let beWire = encode(val, standard().withBigEndian())
    check leWire == @[0x78'u8, 0x56, 0x34, 0x12]
    check beWire == @[0x12'u8, 0x34, 0x56, 0x78]

  test "little-endian vs big-endian int64 wire output":
    let val: uint64 = 0x123456789ABCDEF0'u64
    let leWire = encode(val, standard().withLittleEndian())
    let beWire = encode(val, standard().withBigEndian())
    check leWire == @[0xF0'u8, 0xDE, 0xBC, 0x9A, 0x78, 0x56, 0x34, 0x12]
    check beWire == @[0x12'u8, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0]

  test "container length prefix uses intSize":
    let data = @[byte(0xAA), 0xBB]

    # 8-byte length prefix (standard default)
    let wire8 = encodeToSeq(data, standard().withFixedIntEncoding(8))
    check wire8 == @[0x02'u8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xAA, 0xBB]

    # 4-byte length prefix
    let wire4 = encodeToSeq(data, standard().withFixedIntEncoding(4))
    check wire4 == @[0x02'u8, 0x00, 0x00, 0x00, 0xAA, 0xBB]

    # 2-byte length prefix
    let wire2 = encodeToSeq(data, standard().withFixedIntEncoding(2))
    check wire2 == @[0x02'u8, 0x00, 0xAA, 0xBB]

    # 1-byte length prefix
    let wire1 = encodeToSeq(data, standard().withFixedIntEncoding(1))
    check wire1 == @[0x02'u8, 0xAA, 0xBB]

  test "variable int encoding wire output":
    let smallVal: uint32 = 42
    let fixedWire = encode(smallVal, standard().withFixedIntEncoding(4))
    let varWire = encode(smallVal, standard().withVariableIntEncoding())

    check fixedWire == @[42'u8, 0, 0, 0] # 4 bytes fixed
    check varWire == @[42'u8] # 1 byte varint (bincode v2 single byte <= 250)

  test "custom size limit enforcement":
    let config = standard().withLimit(5'u64)
    let smallData = @[byte(1), 2, 3]
    let largeData = @[byte(1), 2, 3, 4, 5, 6, 7, 8]

    check decode(encodeToSeq(smallData, config), seq[byte], config) == smallData

    expect BincodeError:
      discard encodeToSeq(largeData, config)

{.pop.}
