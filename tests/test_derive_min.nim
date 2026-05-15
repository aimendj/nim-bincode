import bincode_derive, bincode_config, bincode_common, bincode_helpers, bincode_fields, faststreams
type T = object
  x: uint32
deriveBincode(T)
