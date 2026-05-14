# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import faststreams # Uses: memoryOutput, getOutput
import bincode_common
import bincode_config
import bincode_helpers
export bincode_common
export bincode_config
export bincode_helpers

## Native Nim implementation of a subset of the bincode v2 format.
##
## This module provides the main public API by re-exporting functionality from:
## - `bincode_common`: Core byte serialization/deserialization, including
##   `decodePrefixedByteSeq`_ for reading one length-prefixed blob inside a larger
##   buffer (multi-field / struct layout).
## - `bincode_helpers`: Strings, ``Vec<u8>``-wrapped integers, **plain** ``u32``
##   fields (`serializeBincodeU32`_ / `decodeBincodeU32`_), and related helpers.
##
## **Structs** (composite types) are not generated automatically: compose field
## serializers in declaration order to match Rust ``Encode`` (see
## ``src/examples/struct_example.nim``). For ad-hoc payloads you can still use
## `serializeType`_ / `deserializeType`_ with a custom ``toBytes`` / ``fromBytes``
## (two-argument form uses `standard()`_ for the outer ``Vec<u8>`` wrapper; overloads
## with `BincodeConfig`_ pass that through to `serialize`_ / `deserialize`_).
##
## For `Vec[byte]` / strings the format matches Rust bincode v2 with:
## - little- or big-endian configurable byte order
## - fixed or variable-length integer encoding (see `bincode_config`)
## - a configurable size limit (default 64 KiB)

template serializeType*[T](value: T, toBytes: untyped): seq[byte] =
  ## Serialize a custom type using ``toBytes(value)`` (proc, template, etc.).
  var stream = memoryOutput()
  serialize(stream, toBytes(value))
  stream.getOutput()

template deserializeType*(data: openArray[byte], fromBytes: untyped): untyped =
  ## Deserialize a custom type using ``fromBytes(deserialize(data))`` (proc, template, etc.).
  fromBytes(deserialize(data))

template serializeType*[T](value: T, config: BincodeConfig, toBytes: untyped): seq[byte] =
  ## Same as `serializeType`_(``value``, ``toBytes``) but serializes the outer
  ## length-prefixed blob using ``config`` (endianness, fixed vs variable lengths, limit).
  var stream = memoryOutput()
  serialize(stream, toBytes(value), config)
  stream.getOutput()

template deserializeType*(
    data: openArray[byte], config: BincodeConfig, fromBytes: untyped
): untyped =
  ## Same as `deserializeType`_(``data``, ``fromBytes``) but decodes the outer blob with ``config``.
  fromBytes(deserialize(data, config))

{.pop.}
