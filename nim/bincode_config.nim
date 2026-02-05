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
    intSize*: int
      ## Integer encoding:
      ## - 0 = variable-length encoding (LEB128)
      ## - 1, 2, 4, or 8 = fixed encoding with that byte size
    sizeLimit*: uint64

const BINCODE_SIZE_LIMIT* = 65536'u64 # Default 64 KiB limit (matches bincode v2 default)

func standard*(): BincodeConfig {.raises: [].} =
  ## Create a standard bincode configuration with default settings:
  ## - Little-endian byte order
  ## - Fixed integer encoding (8-byte integers by default)
  ## - 64 KiB size limit
  ##
  ## This matches the current default behavior for backward compatibility.
  ##
  return
    BincodeConfig(byteOrder: LittleEndian, intSize: 8, sizeLimit: BINCODE_SIZE_LIMIT)

func withLittleEndian*(config: BincodeConfig): BincodeConfig {.raises: [].} =
  ## Set byte order to little-endian.
  var output = config
  output.byteOrder = LittleEndian
  return output

func withBigEndian*(config: BincodeConfig): BincodeConfig {.raises: [].} =
  ## Set byte order to big-endian.
  var output = config
  output.byteOrder = BigEndian
  return output

func withFixedIntEncoding*(
    config: BincodeConfig, size: int = 8
): BincodeConfig {.raises: [].} =
  ## Set integer encoding to fixed-size.
  ##
  ## `size` specifies the number of bytes to use (1, 2, 4, or 8).
  ## If `size` is 0, it is treated as variable-length encoding.
  var output = config
  if size == 0:
    output.intSize = 0
  else:
    output.intSize = size
  return output

func withVariableIntEncoding*(config: BincodeConfig): BincodeConfig {.raises: [].} =
  ## Set integer encoding to variable-length (LEB128).
  ##
  ## This sets intSize to 0 to indicate variable encoding.
  var output = config
  output.intSize = 0
  return output

func withLimit*(config: BincodeConfig, limit: uint64): BincodeConfig {.raises: [].} =
  ## Set the maximum size limit for serialized data.
  var output = config
  output.sizeLimit = limit
  return output

{.pop.}
