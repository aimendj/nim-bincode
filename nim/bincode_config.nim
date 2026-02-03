{.push raises: [], gcsafe.}

type
  ByteOrder* = enum
    LittleEndian
    BigEndian

  BincodeConfig* = object
    ## Configuration for bincode serialization/deserialization.
    ##
    ## Use `standard()` to get the default configuration, or build a custom
    ## configuration using the builder methods.
    byteOrder*: ByteOrder
    intSize*: int ## Integer encoding:
                    ## - -1 = variable-length encoding (LEB128)
                    ## - 0 = fixed encoding with natural size (4 for int32/uint32, 8 for int64)
                    ## - 1, 2, 4, or 8 = fixed encoding with that byte size
    sizeLimit*: uint64

const BINCODE_SIZE_LIMIT* = 65536'u64

proc standard*(): BincodeConfig {.raises: [].} =
  ## Create a standard bincode configuration with default settings:
  ## - Little-endian byte order
  ## - Fixed integer encoding (uses natural size: 4 bytes for int32/uint32, 8 bytes for int64)
  ## - 64 KiB size limit
  ##
  ## This matches the current default behavior for backward compatibility.
  ##
  ## Note: intSize = 0 means fixed encoding with natural size.
  result = BincodeConfig(
    byteOrder: LittleEndian,
    intSize: 0, ## 0 means fixed encoding with natural size
    sizeLimit: BINCODE_SIZE_LIMIT
  )

proc withLittleEndian*(config: BincodeConfig): BincodeConfig {.raises: [].} =
  ## Set byte order to little-endian.
  result = config
  result.byteOrder = LittleEndian

proc withBigEndian*(config: BincodeConfig): BincodeConfig {.raises: [].} =
  ## Set byte order to big-endian.
  result = config
  result.byteOrder = BigEndian

proc withFixedIntEncoding*(config: BincodeConfig,
    size: int = 0): BincodeConfig {.raises: [].} =
  ## Set integer encoding to fixed-size.
  ##
  ## `size` specifies the number of bytes to use (1, 2, 4, or 8).
  ## If `size` is 0 (default), uses the natural size of the integer type
  ## (4 bytes for int32/uint32, 8 bytes for int64/uint64).
  result = config
  result.intSize = size

proc withVariableIntEncoding*(config: BincodeConfig): BincodeConfig {.raises: [].} =
  ## Set integer encoding to variable-length (LEB128).
  ##
  ## This sets intSize to -1 to indicate variable encoding.
  result = config
  result.intSize = -1

proc withLimit*(config: BincodeConfig, limit: uint64): BincodeConfig {.raises: [].} =
  ## Set the maximum size limit for serialized data.
  result = config
  result.sizeLimit = limit

{.pop.}
