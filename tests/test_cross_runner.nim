# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

import std/[os, osproc, strutils, strformat]

type StageResult = object
  name: string
  command: string
  exitCode: int
  passed: int
  failed: int

proc parseRustSummary(output: string, res: var StageResult) =
  for line in output.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("test result:"):
      let words = trimmed.splitWhitespace()
      for i, w in words:
        if (w == "passed" or w == "passed;") and i > 0:
          try:
            res.passed = parseInt(words[i - 1])
          except ValueError:
            discard
        elif (w == "failed" or w == "failed;") and i > 0:
          try:
            res.failed = parseInt(words[i - 1])
          except ValueError:
            discard

proc parseNimSummary(output: string, res: var StageResult) =
  for line in output.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("[Summary]"):
      let words = trimmed.splitWhitespace()
      for i, w in words:
        if (w == "OK" or w == "OK,") and i > 0:
          try:
            res.passed = parseInt(words[i - 1])
          except ValueError:
            discard
        elif (w == "FAILED" or w == "FAILED,") and i > 0:
          try:
            res.failed = parseInt(words[i - 1])
          except ValueError:
            discard

proc runStage(
    stepNum: int, totalSteps: int, name: string, cmd: string, isNim: bool
): StageResult =
  result.name = name
  result.command = cmd
  echo ""
  echo fmt"--- [{stepNum}/{totalSteps}] {name} ---"

  let (output, exitCode) = execCmdEx(cmd)
  echo output.strip()
  result.exitCode = exitCode

  if isNim:
    parseNimSummary(output, result)
  else:
    parseRustSummary(output, result)

proc main() =
  createDir("target/test_data")
  echo "=== Running Rust ↔ Nim Cross-Verification ==="

  var stages: seq[StageResult] = @[]
  var hasFailure = false

  stages.add runStage(
    1,
    4,
    "Rust serializing test fixtures to disk",
    "cargo test --manifest-path rust/Cargo.toml --test cross_verification test_rust_serialize",
    isNim = false,
  )

  stages.add runStage(
    2,
    4,
    "Nim decoding Rust fixtures & encoding Nim fixtures",
    "nim c -r tests/test_cross_verification.nim",
    isNim = true,
  )

  stages.add runStage(
    3,
    4,
    "Rust decoding Nim fixtures",
    "cargo test --manifest-path rust/Cargo.toml --test cross_verification test_nim_serialize",
    isNim = false,
  )

  stages.add runStage(
    4,
    4,
    "Rust bincode format specification tests",
    "cargo test --manifest-path rust/Cargo.toml --test bincode_format",
    isNim = false,
  )

  var totalPassed = 0
  var totalFailed = 0

  for s in stages:
    totalPassed += s.passed
    totalFailed += s.failed
    if s.exitCode != 0 or s.failed > 0:
      hasFailure = true

  echo ""
  echo repeat('=', 80)
  echo "                   Rust ↔ Nim Cross-Verification Summary"
  echo repeat('=', 80)

  let stageLabels = [
    "1. Rust Fixture Generation (var + fixed8)", "2. Nim Cross-Decoding & Roundtrip",
    "3. Rust Verification of Nim Fixtures", "4. Rust Format Specification Tests",
  ]

  for i, s in stages:
    let icon = if s.exitCode == 0 and s.failed == 0: "[✓]" else: "[✗]"
    let statusText =
      if s.exitCode == 0 and s.failed == 0:
        fmt"{s.passed} passed, 0 failed"
      else:
        fmt"{s.passed} passed, {max(s.failed, 1)} FAILED"
    echo fmt"  {icon} {stageLabels[i]:<44}: {statusText}"

  echo repeat('-', 80)
  let totalTests = totalPassed + totalFailed
  if not hasFailure:
    echo fmt"  TOTAL: {totalTests} checks run: {totalPassed} PASSED, 0 FAILED (All stages OK)"
  else:
    echo fmt"  TOTAL: {totalTests} checks run: {totalPassed} PASSED, {totalFailed} FAILED (Cross-verification FAILED)"
  echo repeat('=', 80)

  if hasFailure:
    quit(1)
  else:
    quit(0)

when isMainModule:
  main()
