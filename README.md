# Bincode Nim Bindings

Nim bindings for the Rust [bincode](https://crates.io/crates/bincode) serialization library through a C-compatible FFI interface.

## Prerequisites

- Rust (with cargo) - [Install Rust](https://www.rust-lang.org/tools/install)
- Nim compiler and nimble - [Install Nim](https://nim-lang.org/install.html) (includes nimble)
- cbindgen (installed automatically via build dependencies)

## Building

### Build the Rust library

```bash
cargo build --release
```

This compiles the Rust wrapper as a static library and generates the C header file `bincode_wrapper.h`:

- Linux/macOS: `target/release/libbincode_wrapper.a`
- Windows: `target/release/bincode_wrapper.lib`

The Nim bindings use static linking by default, producing self-contained executables without runtime dependencies.

## Usage

### In Nim

First, set up dependencies:

```bash
nimble develop
```

The `nim/bincode.nim` module provides bindings to the Rust library:

```nim
import nim/bincode

# Serialize bytes
let data = @[byte(1), 2, 3, 4, 5]
let serialized = serialize(data)
let deserialized = deserialize(serialized)

# Serialize strings
let text = "Hello, world!"
let serializedText = serializeString(text)
let deserializedText = deserializeString(serializedText)
```

Compile your Nim program with:

```bash
nimble develop
nim c -L:target/release your_program.nim
```

The `nimble develop` command sets up the environment with all dependencies, then you can use `nim c` to compile your program.

The bindings automatically link the static library (`libbincode_wrapper.a`), producing a single statically-linked binary.

### In Rust

The FFI functions are for calling from other languages. In Rust, use bincode directly:

```rust
use bincode;

let data = vec![1u8, 2, 3, 4, 5];
let encoded = bincode::encode_to_vec(&data, bincode::config::standard())?;
let (decoded, _): (Vec<u8>, _) = bincode::decode_from_slice(&encoded, bincode::config::standard())?;
```

## Examples

### Rust examples

```bash
cargo run --example simple_example
cargo run --example direct_example
```

### Nim examples

```bash
# Set up dependencies with nimble
nimble develop

# Compile and run examples
nim c -L:target/release nim/examples/example.nim
./example

nim c -L:target/release nim/examples/struct_example.nim
./struct_example
```

## Testing

Run tests to verify FFI functions match native bincode behavior:

```bash
# Run all tests
cargo test

# Run only FFI integration tests
cargo test --test ffi_tests

# Run with output
cargo test -- --nocapture
```

Tests verify:
- FFI serialization/deserialization matches native bincode
- Roundtrip serialization works correctly
- Various data types (strings, integers, structs, mixed data)
- Edge cases (empty vectors, null pointers)

## Formatting

This project uses [nph](https://github.com/arnetheduck/nph) for formatting Nim source code. All Nim files should be formatted before committing.

### Installation

Install `nph` using nimble:

```bash
nimble install nph
```

### Format a single file

```bash
nph nim/bincode.nim
```

### Format all Nim files

```bash
# Format an entire directory
nph nim/

# Or format files individually
nph nim/bincode.nim
nph nim/examples/example.nim
nph nim/examples/struct_example.nim
```

### Check formatting (useful in CI)

```bash
nph --check nim/bincode.nim || echo "Not formatted!"
```

### Show diff of formatting changes

```bash
nph --diff nim/bincode.nim
```

## Project Structure

```
.
├── Cargo.toml          # Rust project configuration
├── bincode.nimble      # Nim package configuration
├── cbindgen.toml       # C header generation config
├── build.rs            # Build script
├── src/
│   └── lib.rs          # Rust FFI wrapper
├── nim/
│   ├── bincode.nim     # Nim bindings
│   ├── examples/
│   │   ├── example.nim
│   │   └── struct_example.nim
│   └── tests/          # Nim tests
├── examples/
│   ├── simple_example.rs
│   └── direct_example.rs
├── tests/
│   └── ffi_tests.rs    # Integration tests
└── README.md
```

## API

### Low-level FFI Functions

- `bincode_serialize(data, len, out_len)`: Serialize bytes to bincode format
- `bincode_deserialize(data, len, out_len)`: Deserialize bincode data to bytes
- `bincode_free_buffer(ptr, len)`: Free memory allocated by bincode functions
- `bincode_get_serialized_length(data, len)`: Get serialized data length

### High-level Nim API

- `serialize(data: seq[byte]): seq[byte]`: Serialize a sequence of bytes
- `deserialize(data: seq[byte]): seq[byte]`: Deserialize bincode-encoded data
- `serializeString(s: string): seq[byte]`: Serialize a string (UTF-8)
- `deserializeString(data: seq[byte]): string`: Deserialize a string (UTF-8)

## Memory Management

The Rust FFI functions allocate memory that must be freed using `bincode_free_buffer`. The high-level Nim API handles memory management automatically.

## Notes

- The implementation serializes/deserializes `Vec<u8>` (byte vectors) for generic binary data handling
- Uses bincode's standard configuration
- For complex types, extend the Rust wrapper to handle specific serde-serializable types

## License

MIT/Apache-2.0 (same as bincode crate)
