# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

type
  BincodeConfigError* = object of CatchableError
    ## Exception raised when bincode configuration is invalid

  ByteOrder* = enum
    LittleEndian
    BigEndian

  # Compile-time encoding configuration
  VariableEncoding* = object ## Variable-length encoding (LEB128)

  FixedEncoding*[Size: static int] = object
    ## Fixed-size encoding with specified byte size

const BINCODE_SIZE_LIMIT* = 65536'u64 # Default 64 KiB limit (matches bincode v2 default)

type
  # Generic compile-time configuration
  BincodeConfig*[
    Encoding: VariableEncoding | FixedEncoding,
    Order: static ByteOrder,
    Limit: static uint64 = BINCODE_SIZE_LIMIT,
  ] = object
    ## Configuration for bincode serialization/deserialization.
    ##
    ## All parameters are compile-time for maximum optimization:
    ## - Encoding: VariableEncoding or FixedEncoding[Size]
    ## - Order: LittleEndian or BigEndian (static)
    ## - Limit: Size limit as compile-time constant (default: BINCODE_SIZE_LIMIT)
    ##
    ## When Limit is known at compile-time, the compiler can optimize size checks.
    ## For dynamic limits, pass `limit` as a separate parameter to serialize/deserialize functions.

# Convenience type aliases for common configurations
type
  VariableLEConfig* = BincodeConfig[VariableEncoding, LittleEndian]
  VariableBEConfig* = BincodeConfig[VariableEncoding, BigEndian]
  Fixed8LEConfig* = BincodeConfig[FixedEncoding[8], LittleEndian]
  Fixed8BEConfig* = BincodeConfig[FixedEncoding[8], BigEndian]
  Fixed4LEConfig* = BincodeConfig[FixedEncoding[4], LittleEndian]
  Fixed4BEConfig* = BincodeConfig[FixedEncoding[4], BigEndian]
  Fixed2LEConfig* = BincodeConfig[FixedEncoding[2], LittleEndian]
  Fixed2BEConfig* = BincodeConfig[FixedEncoding[2], BigEndian]
  Fixed1LEConfig* = BincodeConfig[FixedEncoding[1], LittleEndian]
  Fixed1BEConfig* = BincodeConfig[FixedEncoding[1], BigEndian]

func standard*(): Fixed8LEConfig =
  ## Create a standard bincode configuration with default settings:
  ## - Little-endian byte order
  ## - Fixed integer encoding (8-byte integers)
  ## - 64 KiB size limit (compile-time constant)
  Fixed8LEConfig()

func withLittleEndian*[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](config: BincodeConfig[E, O, L]): BincodeConfig[E, LittleEndian, L] =
  ## Set byte order to little-endian.
  BincodeConfig[E, LittleEndian, L]()

func withBigEndian*[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](config: BincodeConfig[E, O, L]): BincodeConfig[E, BigEndian, L] =
  ## Set byte order to big-endian.
  BincodeConfig[E, BigEndian, L]()

template withFixedIntEncoding*[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](config: BincodeConfig[E, O, L], size: static int = 8): untyped =
  ## Set integer encoding to fixed-size.
  ##
  ## `size` must be a compile-time constant: 1, 2, 4, or 8.
  when size notin [1, 2, 4, 8]:
    {.error: "Fixed encoding size must be 1, 2, 4, or 8".}
  else:
    BincodeConfig[FixedEncoding[size], O, L]()

func withVariableIntEncoding*[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](config: BincodeConfig[E, O, L]): BincodeConfig[VariableEncoding, O, L] =
  ## Set integer encoding to variable-length (LEB128).
  BincodeConfig[VariableEncoding, O, L]()

template withLimit*[
    E: VariableEncoding | FixedEncoding, O: static ByteOrder, L: static uint64
](config: BincodeConfig[E, O, L], limit: static uint64): untyped =
  ## Set the maximum size limit for serialized data.
  ##
  ## `limit` must be a compile-time constant for optimal performance.
  ## For runtime limits, pass `limit` as a separate parameter to serialize/deserialize functions.
  BincodeConfig[E, O, limit]()

{.pop.}
