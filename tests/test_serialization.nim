import unittest2
import std/[tables, sets]
import bincode
import faststreams
import serialization

type Account* = object
  id*: uint64
  balance*: uint64
  owner*: string

deriveBincode(Account)

type TransferMessage* = object
  sender*: string
  receiver*: string
  amount*: uint64

deriveBincode(TransferMessage)

type ErrorMsg* = object
  code*: int32
  message*: string

deriveBincode(ErrorMsg)

type
  DistinctErrorMsg* = distinct string
  BlockNumber* = distinct uint64
  PeerId* = distinct array[4, byte]
  MyList*[T] = distinct seq[T]

suite "nim-serialization Bincode format":
  test "Bincode.encode and Bincode.decode roundtrip":
    let acc = Account(id: 1001'u64, balance: 50000'u64, owner: "Satoshi")
    let bytes = Bincode.encode(acc)
    check bytes.len > 0

    let decoded = Bincode.decode(bytes, Account)
    check decoded.id == 1001'u64
    check decoded.balance == 50000'u64
    check decoded.owner == "Satoshi"

  test "BincodeWriter and BincodeReader sequential stream writing":
    var outStream = memoryOutput()
    var writer = BincodeWriter.init(outStream)

    let msg1 = TransferMessage(sender: "Alice", receiver: "Bob", amount: 250'u64)
    let msg2 = TransferMessage(sender: "Bob", receiver: "Charlie", amount: 100'u64)

    writer.writeValue(msg1)
    writer.writeValue(msg2)

    let serialized = writer.getOutput()
    check serialized.len > 0

    var inStream = unsafeMemoryInput(serialized)
    var reader = BincodeReader.init(inStream)

    var read1, read2: TransferMessage
    reader.readValue(read1)
    reader.readValue(read2)

    check read1.sender == "Alice"
    check read1.receiver == "Bob"
    check read1.amount == 250'u64

    check read2.sender == "Bob"
    check read2.receiver == "Charlie"
    check read2.amount == 100'u64

  test "Bincode primitive writeValue / readValue overloads":
    var outStream = memoryOutput()
    var writer = BincodeWriter.init(outStream)

    writer.writeValue(42'u32)
    writer.writeValue("hello bincode")
    writer.writeValue(true)

    let bytes = writer.getOutput()
    var inStream = unsafeMemoryInput(bytes)
    var reader = BincodeReader.init(inStream)

    var valU32: uint32
    var valStr: string
    var valBool: bool

    reader.readValue(valU32)
    reader.readValue(valStr)
    reader.readValue(valBool)

    check valU32 == 42'u32
    check valStr == "hello bincode"
    check valBool == true

  test "BincodeReader raises SerializationError on truncated stream":
    let truncatedBytes = @[0x01'u8, 0x02] # Insufficient data for uint32
    var reader = BincodeReader.init(truncatedBytes)
    var valU32: uint32
    expect SerializationError:
      reader.readValue(valU32)

  test "BincodeReader raises SerializationError when reading past end":
    let emptyBytes: seq[byte] = @[]
    var reader = BincodeReader.init(emptyBytes)
    var valBool: bool
    expect SerializationError:
      reader.readValue(valBool)

  test "Bincode.encode/decode Table and HashSet":
    var t = initTable[string, int32]()
    t["one"] = 1'i32
    t["two"] = 2'i32
    let wireT = Bincode.encode(t)
    let backT = Bincode.decode(wireT, Table[string, int32])
    check backT["one"] == 1'i32
    check backT["two"] == 2'i32

    var s = initHashSet[uint32]()
    s.incl(10'u32)
    s.incl(20'u32)
    let wireS = Bincode.encode(s)
    let backS = Bincode.decode(wireS, HashSet[uint32])
    check backS.contains(10'u32)
    check backS.contains(20'u32)

  test "Bincode.decode raises SerializationError on trailing bytes":
    let acc = Account(id: 1'u64, balance: 10'u64, owner: "test")
    let wire = Bincode.encode(acc)
    let badWire = wire & @[0xAA'u8, 0xBB]
    expect SerializationError:
      discard Bincode.decode(badWire, Account)

  test "Bincode.encode/decode Option[T]":
    let optSome = some("hello option")
    let wireSome = Bincode.encode(optSome)
    let backSome = Bincode.decode(wireSome, Option[string])
    check backSome.isSome and backSome.get() == "hello option"

    let optNone = none(string)
    let wireNone = Bincode.encode(optNone)
    let backNone = Bincode.decode(wireNone, Option[string])
    check backNone.isNone

  test "Bincode.encode/decode seq[T] and seq[byte]":
    let items =
      @[
        Account(id: 1, balance: 100, owner: "A"),
        Account(id: 2, balance: 200, owner: "B"),
      ]
    let wire = Bincode.encode(items)
    let back = Bincode.decode(wire, seq[Account])
    check back.len == 2
    check back[0].owner == "A"
    check back[1].balance == 200

    let rawBytes: seq[byte] = @[byte(10), 20, 30]
    let wireBytes = Bincode.encode(rawBytes)
    let backBytes = Bincode.decode(wireBytes, seq[byte])
    check backBytes == rawBytes

  test "Bincode.encode/decode array[N, T]":
    let arr: array[3, uint32] = [10'u32, 20'u32, 30'u32]
    let wire = Bincode.encode(arr)
    let back = Bincode.decode(wire, array[3, uint32])
    check back == arr

    let byteArr: array[4, byte] = [1'u8, 2, 3, 4]
    let wireByteArr = Bincode.encode(byteArr)
    let backByteArr = Bincode.decode(wireByteArr, array[4, byte])
    check backByteArr == byteArr

  test "Bincode.encode/decode ErrorMsg-like custom types":
    let err = ErrorMsg(code: 404'i32, message: "Not found")
    let wire = Bincode.encode(err)
    let back = Bincode.decode(wire, ErrorMsg)
    check back.code == 404'i32
    check back.message == "Not found"

  test "Bincode.encode/decode distinct types forwarding":
    let dMsg = DistinctErrorMsg("connection reset")
    let wireMsg = Bincode.encode(dMsg)
    let backMsg = Bincode.decode(wireMsg, DistinctErrorMsg)
    check string(backMsg) == "connection reset"

    let bNum = BlockNumber(123456789'u64)
    let wireNum = Bincode.encode(bNum)
    let backNum = Bincode.decode(wireNum, BlockNumber)
    check uint64(backNum) == 123456789'u64

    let peer = PeerId([1'u8, 2, 3, 4])
    let wirePeer = Bincode.encode(peer)
    let backPeer = Bincode.decode(wirePeer, PeerId)
    check array[4, byte](backPeer) == [1'u8, 2, 3, 4]

    let list = MyList[string](@["item1", "item2"])
    let wireList = Bincode.encode(list)
    let backList = Bincode.decode(wireList, MyList[string])
    check seq[string](backList) == @["item1", "item2"]

  test "Bincode stream-based encode and decode":
    var outStream = memoryOutput()
    var writer = BincodeWriter.init(outStream)
    let acc = Account(id: 99'u64, balance: 12345'u64, owner: "Alice")
    writer.writeValue(acc)
    let bytes = writer.getOutput()
    check bytes.len > 0

    var inStream = unsafeMemoryInput(bytes)
    var reader = BincodeReader.init(inStream)
    var back: Account
    reader.readValue(back)
    check back.id == 99'u64
    check back.balance == 12345'u64
    check back.owner == "Alice"

  test "Bincode decode with generic type parameter (MsgType)":
    proc genericNetworkDecode[MsgType](data: seq[byte]): MsgType =
      decode(Bincode, data, MsgType)

    let origMsg = ErrorMsg(code: 404, message: "Not Found")
    let wire = Bincode.encode(origMsg)
    let back = genericNetworkDecode[ErrorMsg](wire)
    check back.code == 404
    check back.message == "Not Found"
