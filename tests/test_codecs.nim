# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import faststreams # Uses: memoryOutput, getOutput
import unittest2
import std/strutils
import bincode

# ============================================================================
# Basic Encoding/Decoding Tests
# ============================================================================

suite "Basic encode/decode":
  test "encode empty sequence":
    let empty: seq[byte] = @[]
    let encoded = encode(empty)
    check encoded.len == 8
    check encoded == @[byte(0), 0, 0, 0, 0, 0, 0, 0]

  test "decode empty sequence":
    let empty_encoded: seq[byte] = @[byte(0), 0, 0, 0, 0, 0, 0, 0]
    let decoded = decode(empty_encoded, seq[byte])
    check decoded.len == 0
    let empty: seq[byte] = @[]
    check decoded == empty

  test "encode and decode basic byte array":
    let original = @[byte(1), 2, 3, 4, 5]
    let encoded = encode(original)
    check encoded.len == 13 # 8 bytes length + 5 bytes data
    check encoded[0 .. 7] == @[byte(5), 0, 0, 0, 0, 0, 0, 0] # length prefix
    check encoded[8 .. 12] == original # data
    check original == decode(encoded, seq[byte])

  test "encode and decode single byte":
    let original = @[byte(42)]
    let encoded = encode(original)
    check encoded.len == 9 # 8 bytes length + 1 byte data
    check encoded[0 .. 7] == @[byte(1), 0, 0, 0, 0, 0, 0, 0] # length = 1
    check encoded[8] == byte(42)
    check original == decode(encoded, seq[byte])

  test "encode and decode large array":
    var original = newSeq[byte](1000)
    for i in 0 ..< 1000:
      original[i] = byte(i mod 256)
    let encoded = encode(original)
    check original == decode(encoded, seq[byte])

  test "encode and decode with all byte values":
    var original = newSeq[byte](256)
    for i in 0 ..< 256:
      original[i] = byte(i)
    let encoded = encode(original)
    check original == decode(encoded, seq[byte])

  test "encode and decode with zeros":
    let original = @[byte(0), 0, 0, 0, 0]
    let encoded = encode(original)
    check original == decode(encoded, seq[byte])

  test "encode and decode with max byte values":
    let original = @[byte(255), 255, 255]
    let encoded = encode(original)
    check original == decode(encoded, seq[byte])

  test "decode empty data raises exception":
    let empty: seq[byte] = @[]
    expect BincodeError:
      discard decode(empty, seq[byte])

  test "decode with insufficient data raises":
    let insufficient = @[byte(1), 2, 3] # Only 3 bytes, need at least 8
    expect BincodeError:
      discard decode(insufficient, seq[byte])

  test "decode with insufficient content raises":
    # 8 bytes length prefix says length = 5, but only 10 bytes total (need 13)
    let insufficient = @[byte(5), 0, 0, 0, 0, 0, 0, 0, 1, 2]
    expect BincodeError:
      discard decode(insufficient, seq[byte])

  test "decode with trailing bytes raises":
    # 8 bytes length prefix says length = 2, but have 13 bytes total (should be 10)
    let with_trailing = @[byte(2), 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5]
    expect BincodeError:
      discard decode(with_trailing, seq[byte])

  test "encode with data exceeding limit raises":
    var large = newSeq[byte](65537) # 65537 bytes > 65536 limit
    for i in 0 ..< large.len:
      large[i] = byte(i mod 256)
    expect BincodeError:
      discard encode(large)

  test "decode with length exceeding limit raises":
    # Length prefix says 65537, which exceeds limit
    var invalid = newSeq[byte](16)
    invalid[0] = byte(1)
    invalid[1] = byte(0)
    invalid[2] = byte(1)
    invalid[3] = byte(0)
    invalid[4] = byte(0)
    invalid[5] = byte(0)
    invalid[6] = byte(0)
    invalid[7] = byte(0)
    for i in 8 ..< invalid.len:
      invalid[i] = byte(i)
    expect BincodeError:
      discard decode(invalid, seq[byte])

# ============================================================================
# String Encoding Tests
# ============================================================================

suite "String encoding":
  test "encode empty string":
    let empty = ""
    let encoded = encode(empty)
    check encoded.len == 8
    check encoded == @[byte(0), 0, 0, 0, 0, 0, 0, 0]

  test "decode empty string":
    let empty_encoded = @[byte(0), 0, 0, 0, 0, 0, 0, 0]
    let decoded = decode(empty_encoded, string)
    check decoded == ""

  test "encode and decode basic string":
    let original = "Hello, World!"
    let encoded = encode(original)
    check encoded.len == 21 # 8 bytes length + 13 bytes UTF-8
    check encoded[0 .. 7] == @[byte(13), 0, 0, 0, 0, 0, 0, 0] # length prefix
    check original == decode(encoded, string)

  test "roundtrip string encoding":
    let original = "Test string with various characters: !@#$%^&*()"
    let encoded = encode(original)
    let decoded = decode(encoded, string)
    check decoded == original

  test "encode and decode unicode string":
    let original = "Test with émojis 🚀"
    let encoded = encode(original)
    check original == decode(encoded, string)

  test "encode string with various unicode characters":
    let original = "Unicode: 中文 العربية русский 🎉 émoji"
    let encoded = encode(original)
    let decoded = decode(encoded, string)
    check decoded == original

  test "encode and decode long string":
    let original = repeat("Very long string: ", 100)
    let encoded = encode(original)
    check original == decode(encoded, string)

  test "encode and decode string with null bytes":
    let original = "Null\0byte"
    let encoded = encode(original)
    check original == decode(encoded, string)

  test "encode and decode multiline string":
    let original = "Line 1\nLine 2\nLine 3"
    let encoded = encode(original)
    check original == decode(encoded, string)

# ============================================================================
# Integer Encoding Tests
# ============================================================================

suite "Int32 encoding":
  test "encode and decode int32 zero":
    let original: int32 = 0
    let encoded = encode(original)
    check original == decode(encoded, int32)

  test "encode and decode int32 positive":
    let original: int32 = 42
    let encoded = encode(original)
    check original == decode(encoded, int32)

  test "encode and decode int32 negative":
    let original: int32 = -42
    let encoded = encode(original)
    check original == decode(encoded, int32)

  test "encode and decode int32 max":
    let original: int32 = int32.high
    let encoded = encode(original)
    check original == decode(encoded, int32)

  test "encode and decode int32 min":
    let original: int32 = int32.low
    let encoded = encode(original)
    check original == decode(encoded, int32)

  test "decode int32 with insufficient data raises exception":
    let insufficient = @[byte(1), 2, 3] # Only 3 bytes, need 4
    expect BincodeError:
      discard decode(insufficient, int32)

suite "Uint32 encoding":
  test "encode and decode uint32 zero":
    let original: uint32 = 0'u32
    let encoded = encode(original)
    check original == decode(encoded, uint32)

  test "encode and decode uint32 positive":
    let original: uint32 = 42'u32
    let encoded = encode(original)
    check original == decode(encoded, uint32)

  test "encode and decode uint32 max":
    let original: uint32 = uint32.high
    let encoded = encode(original)
    check original == decode(encoded, uint32)

  test "decode uint32 with insufficient data raises exception":
    let insufficient = @[byte(1), 2, 3] # Only 3 bytes, need 4
    expect BincodeError:
      discard decode(insufficient, uint32)

suite "Int64 encoding":
  test "encode and decode int64 zero":
    let original: int64 = 0
    let encoded = encode(original)
    check original == decode(encoded, int64)

  test "encode and decode int64 positive":
    let original: int64 = 42
    let encoded = encode(original)
    check original == decode(encoded, int64)

  test "encode and decode int64 negative":
    let original: int64 = -42
    let encoded = encode(original)
    check original == decode(encoded, int64)

  test "encode and decode int64 max":
    let original: int64 = int64.high
    let encoded = encode(original)
    check original == decode(encoded, int64)

  test "encode and decode int64 min":
    let original: int64 = int64.low
    let encoded = encode(original)
    check original == decode(encoded, int64)

  test "decode int64 with insufficient data raises exception":
    let insufficient = @[byte(1), 2, 3, 4, 5, 6, 7] # Only 7 bytes, need 8
    expect BincodeError:
      discard decode(insufficient, int64)

suite "Container length prefix uses intSize in fixed mode":
  test "intSize 4 uses 4-byte LE length for byte sequences":
    let cfg = standard().withFixedIntEncoding(4)
    let data = @[byte(1), 2, 3]
    let s = encode(data, cfg)
    check s.len == 7
    check s[0 .. 3] == @[byte(3), 0, 0, 0]
    check s[4 .. 6] == data
    check decode(s, seq[byte], cfg) == data

  test "intSize 1 rejects length above 255":
    let cfg = standard().withFixedIntEncoding(1).withLimit(10_000'u64)
    var big = newSeq[byte](300)
    expect BincodeError:
      discard encode(big, cfg)

type PersonTest = object
  name: string
  age: uint32
  email: string

proc encodePersonTest(
    stream: OutputStreamHandle, p: PersonTest, config: BincodeConfig
) {.raises: [BincodeError, IOError].} =
  encode(stream, p.name, config)
  encode(stream, p.age, config)
  encode(stream, p.email, config)

func decodePersonTest(
    data: openArray[byte], config: BincodeConfig
): PersonTest {.raises: [BincodeError].} =
  var off = 0
  let (name, n1) = decodeAt(data, string, config, off)
  off += n1
  let (age, n2) = decodeAt(data, uint32, config, off)
  off += n2
  let (email, n3) = decodeAt(data, string, config, off)
  off += n3
  if off != data.len:
    raise newException(BincodeError, "Trailing bytes after struct fields")
  PersonTest(name: name, age: age, email: email)

suite "Struct-style field composition (Rust bincode layout)":
  test "Person-like struct roundtrip with fixed u8 length prefixes and plain u32 age":
    let cfg = standard().withLittleEndian().withFixedIntEncoding(8).withLimit(65536'u64)
    let p = PersonTest(name: "Alice", age: 30'u32, email: "alice@example.com")
    var st = memoryOutput()
    encodePersonTest(st, p, cfg)
    let wire = st.getOutput()
    check wire.len == 42
    let q = decodePersonTest(wire, cfg)
    check q.name == p.name and q.age == p.age and q.email == p.email

  test "decodeAt string reads consecutive strings with offsets":
    let cfg = standard().withFixedIntEncoding(8)
    let wire = encode("a", cfg) & encode("bc", cfg)
    let (a, n1) = decodeAt(wire, string, cfg, 0)
    let (b, n2) = decodeAt(wire, string, cfg, n1)
    check a == "a" and b == "bc" and n1 + n2 == wire.len

  test "encode uint32 fixed mode writes 4 little-endian bytes":
    let cfg = standard().withFixedIntEncoding(8)
    var st = memoryOutput()
    encode(st, 30'u32, cfg)
    check st.getOutput() == @[byte(0x1E), 0, 0, 0]

  test "encode uint32 variable mode single-byte for 30":
    let cfg = standard().withVariableIntEncoding()
    var st = memoryOutput()
    encode(st, 30'u32, cfg)
    let w = st.getOutput()
    check w == @[30'u8]
    check decodeAt(w, uint32, cfg, 0) == (30'u32, 1)

  # ============================================================================
  # Variable-Length Encoding Tests
  # ============================================================================
  test "variable-length encoding for uint32 roundtrip":
    let config = standard().withVariableIntEncoding()

    let bytes0 = encode(0'u32, config)
    check bytes0.len == 1
    check bytes0[0] == 0x00'u8
    check decode(bytes0, uint32, config) == 0'u32

    let bytes127 = encode(127'u32, config)
    check bytes127.len == 1
    check bytes127[0] == 127'u8
    check decode(bytes127, uint32, config) == 127'u32

    let bytes128 = encode(128'u32, config)
    check bytes128.len == 1
    check bytes128[0] == 128'u8
    check decode(bytes128, uint32, config) == 128'u32

    let bytes16383 = encode(16383'u32, config)
    check decode(bytes16383, uint32, config) == 16383'u32

    let bytes16384 = encode(16384'u32, config)
    check decode(bytes16384, uint32, config) == 16384'u32

  test "variable-length encoding for int64 roundtrip":
    let config = standard().withVariableIntEncoding()

    let bytes0 = encode(0'i64, config)
    check bytes0.len == 1
    check bytes0[0] == 0x00'u8
    check decode(bytes0, int64, config) == 0'i64

    let bytes127 = encode(127'i64, config)
    check decode(bytes127, int64, config) == 127'i64

    let bytes128 = encode(128'i64, config)
    check decode(bytes128, int64, config) == 128'i64

    let bytesNeg1 = encode(-1'i64, config)
    check decode(bytesNeg1, int64, config) == -1'i64

# ============================================================================
# Roundtrip Tests
# ============================================================================

suite "Roundtrip tests":
  test "roundtrip encoding":
    let original = @[byte(1), 2, 3, 4, 5, 100, 200, 255]
    let encoded = encode(original)
    let decoded = decode(encoded, seq[byte])
    check decoded == original

  test "multiple roundtrips preserve data":
    let original = @[byte(1), 2, 3, 4, 5, 100, 200, 255]
    var current = original
    for i in 0 ..< 5:
      current = decode(encode(current), seq[byte])
    check current == original

  test "roundtrip with mixed data":
    let original = @[byte(0), 1, 2, 255, 128, 64, 32, 16, 8, 4, 2, 1, 0]
    let encoded = encode(original)
    check original == decode(encoded, seq[byte])

# ============================================================================
# Edge Cases
# ============================================================================

suite "Edge cases":
  test "encode single zero byte":
    let original = @[byte(0)]
    let encoded = encode(original)
    check original == decode(encoded, seq[byte])

  test "encode single max byte":
    let original = @[byte(255)]
    let encoded = encode(original)
    check original == decode(encoded, seq[byte])

  test "encode pattern bytes":
    let original = @[byte(0xAA), 0x55, 0xAA, 0x55]
    let encoded = encode(original)
    check original == decode(encoded, seq[byte])

  test "reject invalid marker byte 0xff in variable encoding":
    let config = standard().withVariableIntEncoding()
    let invalid = @[byte(0xFF), 0x00, 0x00]
    expect BincodeError:
      discard decode(invalid, seq[byte], config)

suite "encodeType / decodeType with BincodeConfig":
  test "config overload roundtrips single-byte inner payload with fixed 4-byte length":
    proc innerToBytes(x: int): seq[byte] =
      @[byte(x and 0xFF)]

    proc innerFromBytes(s: openArray[byte]): int =
      int(s[0])

    let cfg = standard().withFixedIntEncoding(4)
    let wire = encodeType(200, cfg, innerToBytes)
    check wire.len == 5
    check decodeType(wire, cfg, innerFromBytes) == 200

  test "float32 and float64 NaN bit pattern preservation":
    let nan32Bits: uint32 = 0x7FC00001'u32
    let nan32Val = cast[float32](nan32Bits)
    let encoded32 = encode(nan32Val)
    let decoded32 = decode(encoded32, float32)
    check cast[uint32](decoded32) == nan32Bits

    let nan64Bits: uint64 = 0x7FF8000000000001'u64
    let nan64Val = cast[float64](nan64Bits)
    let encoded64 = encode(nan64Val)
    let decoded64 = decode(encoded64, float64)
    check cast[uint64](decoded64) == nan64Bits

suite "Char encoding":
  test "encode and decode ASCII char":
    let c = 'A'
    let encoded = encode(c)
    check decode(encoded, char) == 'A'

  test "decode char rejecting invalid code point > 0x10FFFF":
    let invalidCodePointWire = @[0x00'u8, 0x00, 0x11, 0x00] # 0x110000 > 0x10FFFF
    expect BincodeError:
      discard decode(invalidCodePointWire, char)

  test "decode char rejecting code point > 255 for Nim 8-bit char":
    let nonAsciiWire = @[0x00'u8, 0x01, 0x00, 0x00] # 256 > 255
    expect BincodeError:
      discard decode(nonAsciiWire, char)

suite "Distinct types encoding":
  type
    TxId = distinct seq[byte]
    Nonce = distinct uint64
    ErrMsg = distinct string

  test "encode and decode distinct primitives":
    let n = Nonce(42'u64)
    let wireN = encode(n)
    let backN = decode(wireN, Nonce)
    check uint64(backN) == 42'u64

    let s = ErrMsg("bad signature")
    let wireS = encode(s)
    let backS = decode(wireS, ErrMsg)
    check string(backS) == "bad signature"

    let tx = TxId(@[1'u8, 2, 3, 4])
    let wireTx = encode(tx)
    let backTx = decode(wireTx, TxId)
    check seq[byte](backTx) == @[1'u8, 2, 3, 4]

suite "Variable-length Integer & ZigZag Codecs":
  test "variable unsigned integers roundtrip":
    let cfg = standard().withVariableIntEncoding()
    for val in [
      0'u64, 42'u64, 250'u64, 251'u64, 1000'u64, 65535'u64, 65536'u64, 1000000'u64,
      uint64.high,
    ]:
      let wire = encode(val, cfg)
      let back = decode(wire, uint64, cfg)
      check back == val

  test "variable signed integers with zigzag roundtrip":
    let cfg = standard().withVariableIntEncoding()
    for val in [
      0'i64, 1'i64, -1'i64, 42'i64, -42'i64, 1000'i64, -1000'i64, int64.high, int64.low
    ]:
      let wire = encode(val, cfg)
      let back = decode(wire, int64, cfg)
      check back == val

suite "Option and Array codecs":
  test "Option[T] encode and decode":
    let noneVal: Option[uint32] = none(uint32)
    let someVal: Option[uint32] = some(12345'u32)
    let wireNone = encode(noneVal)
    let wireSome = encode(someVal)
    check wireNone == @[0'u8]
    check decode(wireNone, Option[uint32]).isNone
    check decode(wireSome, Option[uint32]).get() == 12345'u32

  test "array[N, T] raw bytes vs generic array":
    let rawArr: array[4, byte] = [1'u8, 2, 3, 4]
    let wireRaw = encode(rawArr)
    check wireRaw == @[1'u8, 2, 3, 4]
    check decode(wireRaw, array[4, byte]) == rawArr

    let strArr: array[2, string] = ["hello", "world"]
    let wireStr = encode(strArr)
    check decode(wireStr, array[2, string]) == strArr

{.pop.}
