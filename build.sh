#!/bin/bash
# Build script for bincode Nim bindings

set -e

echo "Building Rust library..."
cargo build --release

echo ""
echo "Build complete!"
echo ""
echo "The library is located at:"
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "  target/release/libbincode_wrapper.dylib"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "  target/release/libbincode_wrapper.so"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
    echo "  target/release/bincode_wrapper.dll"
fi
echo ""
echo "C header generated at: bincode_wrapper.h"
echo ""
echo "To compile a Nim program using these bindings:"
echo "  nim c -L:target/release your_program.nim"

