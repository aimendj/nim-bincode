# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

type
  BincodeConfigError* = object of CatchableError
    ## Exception raised when bincode configuration is invalid

  ByteOrder* = enum
    LittleEndian
    BigEndian

  BincodeConfig* = object
    ## Configuration for bincode serialization/deserialization.
    ##
    ## Use `standard()` to get the default configuration, or build a custom
    ## configuration using the builder methods.
    byteOrder*: ByteOrder
    intSize*: int
      ## Integer encoding:
      ## - 0 = variable-length encoding (Rust bincode varint for lengths and wrapped integers)
      ## - 1, 2, 4, or 8 = fixed width for **container length prefixes** (``Vec``/string/blob)
    sizeLimit*: uint64

const BINCODE_SIZE_LIMIT* = 65536'u64 # Default 64 KiB limit (matches bincode v2 default)

func standard*(): BincodeConfig =
  ## Create a standard bincode configuration with default settings:
  ## - Little-endian byte order
  ## - Fixed integer encoding (8-byte integers by default)
  ## - 64 KiB size limit
  BincodeConfig(byteOrder: LittleEndian, intSize: 8, sizeLimit: BINCODE_SIZE_LIMIT)

func withLittleEndian*(config: BincodeConfig): BincodeConfig =
  ## Set byte order to little-endian.
  var output = config
  output.byteOrder = LittleEndian
  output

func withBigEndian*(config: BincodeConfig): BincodeConfig =
  ## Set byte order to big-endian.
  var output = config
  output.byteOrder = BigEndian
  output

func withFixedIntEncoding*(
    config: BincodeConfig, size: int = 8
): BincodeConfig {.raises: [BincodeConfigError].} =
  ## Set integer encoding to fixed-size.
  var output = config
  if size == 0:
    output.intSize = 0
  else:
    if size notin [1, 2, 4, 8]:
      raise
        newException(BincodeConfigError, "Invalid fixedIntSize: must be 1, 2, 4, or 8")
    output.intSize = size
  output

func withVariableIntEncoding*(config: BincodeConfig): BincodeConfig =
  ## Set integer encoding to variable-length (LEB128).
  var output = config
  output.intSize = 0
  output

func withLimit*(config: BincodeConfig, limit: uint64): BincodeConfig =
  ## Set the maximum size limit for serialized data.
  var output = config
  output.sizeLimit = limit
  output

{.pop.}
