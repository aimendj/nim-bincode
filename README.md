# Bincode Nim Bindings

This project provides Nim bindings for the Rust [bincode](https://crates.io/crates/bincode) serialization library through a C-compatible FFI interface.

## Prerequisites

- Rust (with cargo) - [Install Rust](https://www.rust-lang.org/tools/install)
- Nim compiler - [Install Nim](https://nim-lang.org/install.html)
- cbindgen (installed automatically via build dependencies)

## Building

### 1. Build the Rust library

```bash
cargo build --release
```

This will:
- Compile the Rust wrapper library as a shared library (`.so` on Linux, `.dylib` on macOS, `.dll` on Windows)
- Generate the C header file `bincode_wrapper.h` automatically via `build.rs`

The compiled library will be located at:
- Linux: `target/release/libbincode_wrapper.so`
- macOS: `target/release/libbincode_wrapper.dylib`
- Windows: `target/release/bincode_wrapper.dll`

### 2. Use in your Nim project

The `bincode.nim` module provides bindings to the Rust library. You can use it in your Nim code:

```nim
import bincode

# Serialize bytes
let data = @[byte(1), 2, 3, 4, 5]
let serialized = serialize(data)
let deserialized = deserialize(serialized)

# Serialize strings
let text = "Hello, world!"
let serializedText = serializeString(text)
let deserializedText = deserializeString(serializedText)
```

### 3. Compile your Nim program

When compiling your Nim program, make sure the library path is correct:

```bash
nim c -L:target/release your_program.nim
```

Or use the example:

```bash
nim c -L:target/release example.nim
./example
```

### 4. Run Rust examples

The project includes Rust examples:

```bash
# Example matching the Nim example.nim (bytes and strings)
cargo run --example simple_example

# Example showing struct serialization (like direct_example.rs)
cargo run --example direct_example
```

**Note:** The FFI functions in `lib.rs` are designed for calling from other languages (like Nim, C, Python, etc.). If you're using Rust, you should use bincode directly as shown in the examples, not through the FFI layer.

### 5. Run Nim examples

The project includes Nim examples:

```bash
# Simple example (bytes and strings)
nim c example.nim
./example

# Struct example (matching Rust direct_example.rs)
nim c struct_example.nim
./struct_example
```

## Project Structure

```
.
├── Cargo.toml          # Rust project configuration
├── cbindgen.toml       # Configuration for C header generation
├── build.rs            # Build script that generates C headers
├── src/
│   └── lib.rs          # Rust FFI wrapper implementation
├── examples/
│   ├── simple_example.rs  # Rust example matching example.nim
│   └── direct_example.rs  # Rust example with struct serialization
├── bincode.nim         # Nim bindings module
├── example.nim         # Nim example (bytes and strings)
├── struct_example.nim  # Nim example matching direct_example.rs
└── README.md           # This file
```

## API Overview

### Low-level FFI Functions

- `bincode_serialize(data, len, out_len)`: Serialize bytes to bincode format
- `bincode_deserialize(data, len, out_len)`: Deserialize bincode data to bytes
- `bincode_free_buffer(ptr, len)`: Free memory allocated by bincode functions
- `bincode_get_serialized_length(data, len)`: Get the length of serialized data

### High-level Nim API

- `serialize(data: seq[byte]): seq[byte]`: Serialize a sequence of bytes
- `deserialize(data: seq[byte]): seq[byte]`: Deserialize bincode-encoded data
- `serializeString(s: string): seq[byte]`: Serialize a string (converts to UTF-8 bytes)
- `deserializeString(data: seq[byte]): string`: Deserialize a string (interprets bytes as UTF-8)

## Memory Management

The Rust FFI functions allocate memory that must be freed using `bincode_free_buffer`. The high-level Nim API (`serialize`, `deserialize`, etc.) handles memory management automatically, so you don't need to manually free memory when using those functions.

## Notes

- The current implementation serializes/deserializes `Vec<u8>` (byte vectors), which provides a generic way to work with arbitrary binary data
- For more complex types, you would need to extend the Rust wrapper to handle specific serde-serializable types
- The library uses bincode's standard configuration

## License

This project follows the same license as the bincode crate (MIT/Apache-2.0).

