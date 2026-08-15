# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import faststreams
import ./bincode/config
import ./bincode/codecs
import ./bincode/derive
import ./bincode/serialization

export config
export codecs
export derive
export serialization

## Native Nim implementation of a subset of the bincode v2 format.
##
## This module provides the main public API:
## - ``encode`` / ``decode`` / ``decodeAt``: Unified encoding/decoding for primitive types,
##   sequences, strings, and types derived via ``deriveBincode`` / ``deriveBincodeCustom``.
## - ``Bincode.encode`` / ``Bincode.decode``: Standard ``nim-serialization`` format interface.
## - ``deriveBincode(MyType)``: Macro for generating Bincode procedures for structs & enums.
## - ``deriveBincodeCustom(MyType, toBytes, fromBytes)``: Macro for custom encoded types.
## - ``BincodeConfig``: Builders for endianness, integer encoding (fixed vs variable), and size limits.

template encodeType*[T](value: T, toBytes: untyped): seq[byte] =
  ## Encode a custom type using ``toBytes(value)`` (proc, template, etc.).
  var stream = memoryOutput()
  encode(stream, toBytes(value))
  stream.getOutput()

template decodeType*(data: openArray[byte], fromBytes: untyped): untyped =
  ## Decode a custom type using ``fromBytes(decode(data))`` (proc, template, etc.).
  fromBytes(decode(data))

template encodeType*[T](value: T, config: BincodeConfig, toBytes: untyped): seq[byte] =
  ## Same as `encodeType`(``value``, ``toBytes``) but encodes the outer
  ## length-prefixed blob using ``config`` (endianness, fixed vs variable lengths, limit).
  var stream = memoryOutput()
  encode(stream, toBytes(value), config)
  stream.getOutput()

template decodeType*(
    data: openArray[byte], config: BincodeConfig, fromBytes: untyped
): untyped =
  ## Same as `decodeType`(``data``, ``fromBytes``) but decodes the outer blob with ``config``.
  fromBytes(decode(data, config))

{.pop.}
