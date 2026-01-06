# Package

version       = "0.1.0"
author        = "aimendj"
description   = "Nim bindings for Rust bincode serialization library"
license       = "MIT/Apache-2.0"
srcDir        = "nim"
bin           = @["bincode"]

# Dependencies

requires "nim >= 2.0.0"
requires "stew >= 0.4.2"

