# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import faststreams # Uses: memoryOutput, getOutput
import bincode_common
import bincode_helpers
export bincode_common
export bincode_helpers

## Native Nim implementation of a subset of the bincode v2 format.
##
## This module provides the main public API by re-exporting functionality from:
## - `bincode_common`: Core byte serialization/deserialization
## - `bincode_helpers`: String and integer serialization/deserialization
##
## For `Vec[byte]` / strings the format matches Rust bincode v2 with:
## - little- or big-endian configurable byte order
## - fixed or variable-length integer encoding (see `bincode_config`)
## - a configurable size limit (default 64 KiB)

template serializeType*[T](value: T, toBytes: proc(x: T): seq[byte]): seq[byte] =
  ## Serialize a custom type using a conversion function.
  var stream = memoryOutput()
  serialize(stream, toBytes(value))
  stream.getOutput()

template deserializeType*[T](
    data: openArray[byte], fromBytes: proc(x: openArray[byte]): T
): T =
  ## Deserialize a custom type using a conversion function.
  fromBytes(deserialize(data))

{.pop.}
