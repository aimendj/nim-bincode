# Package

version = "0.1.0"
author = "Status Research & Development GmbH"
description = "Native Nim implementation of the Rust bincode serialization format"
license = "Apache-2.0 OR MIT"
srcDir = "src"

# Dependencies

requires "nim >= 2.2.4"
requires "stew >= 0.4.2"
requires "unittest2"
requires "faststreams"

# Tasks

task test, "Run all Nim tests":
  exec "nim c -r tests/test_bincode_config.nim"
  exec "nim c -r tests/test_bincode.nim"
  exec "nim c -r tests/test_derive.nim"