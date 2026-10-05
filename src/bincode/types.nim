# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [], gcsafe.}

import std/typetraits

# Bounded sequences

type BoundedSeq*[T; maxLen: static int] = distinct seq[T]
  ## A ``seq[T]`` that the decoder accepts with ``maxLen`` elements at most.

template asSeq*(x: BoundedSeq): auto =
  distinctBase(x)

template len*(x: BoundedSeq): auto =
  len(distinctBase(x))

template `[]`*(x: BoundedSeq, idx: auto): untyped =
  distinctBase(x)[idx]

template `==`*(a, b: BoundedSeq): bool =
  distinctBase(a) == distinctBase(b)

template items*(x: BoundedSeq): untyped =
  items(distinctBase(x))

template pairs*(x: BoundedSeq): untyped =
  pairs(distinctBase(x))

template `$`*(x: BoundedSeq): auto =
  $(distinctBase(x))

{.pop.}
