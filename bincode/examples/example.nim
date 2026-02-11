# SPDX-License-Identifier: Apache-2.0 OR MIT
# Copyright (c) Status Research & Development GmbH

{.push raises: [BincodeError, BincodeConfigError], gcsafe.}

import ../nim_bincode
import ../bincode_config

proc main() =
  let original = @[byte(1), 2, 3, 4, 5]
  echo "Original bytes: ", original

  let serialized = serialize(original)
  echo "Serialized length: ", serialized.len
  echo "Serialized bytes: ", serialized

  let deserialized = deserialize(serialized)
  echo "Deserialized bytes: ", deserialized
  echo "Match: ", original == deserialized

  let text = "Hello, bincode!"
  echo "\nOriginal string: ", text

  let serializedText = serializeString(text)
  echo "Serialized length: ", serializedText.len
  echo "Serialized Text: ", serializedText

  let deserializedText = deserializeString(serializedText)
  echo "Deserialized string: ", deserializedText
  echo "Match: ", text == deserializedText

main()

{.pop.}
