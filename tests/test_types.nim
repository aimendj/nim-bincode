# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}
{.used.}

import unittest2
import std/sequtils
import bincode/types

suite "BoundedSeq types":
  test "the helpers read a bounded sequence":
    var list = BoundedSeq[uint32, 4](@[5'u32, 6, 7])
    check list.len == 3
    check list[^1] == 7'u32
    check list == BoundedSeq[uint32, 4](@[5'u32, 6, 7])
    check list != BoundedSeq[uint32, 4](@[5'u32, 6, 8])
    check list.mapIt(it) == @[5'u32, 6, 7]
    check $list == "@[5, 6, 7]"
    for i, item in list:
      check item == uint32(5 + i)
    list.asSeq.add 8'u32
    check list.asSeq == @[5'u32, 6, 7, 8]

  test "the types module does not give the codec":
    let list = BoundedSeq[uint32, 4](@[5'u32, 6, 7])
    check not compiles(encode(list))
    check not compiles(decode(newSeq[byte](), BoundedSeq[uint32, 4]))

{.pop.}
