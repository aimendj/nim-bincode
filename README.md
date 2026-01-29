# Bincode Nim Bindings

Nim bindings for the Rust [bincode](https://crates.io/crates/bincode) serialization library through a C-compatible FFI interface.

## Prerequisites

- Rust (with cargo) - [Install Rust](https://www.rust-lang.org/tools/install)
- Nim compiler - [Install Nim](https://nim-lang.org/install.html)
- Make - Usually pre-installed on Unix systems
- cbindgen (installed automatically via build dependencies)

## Building

### Build the Rust library

```bash
make build
# or
cargo build --release
```

This compiles the Rust wrapper as a static library and generates the C header file `bincode_wrapper.h`:

- Linux/macOS: `target/release/libbincode_wrapper.a`
- Windows: `target/release/bincode_wrapper.lib`

The Nim bindings use static linking by default, producing self-contained executables without runtime dependencies.

### Install Nim dependencies

Before building Nim code, initialize the git submodules:

```bash
make install-deps
```

This initializes the `stew` git submodule (required for endian conversion utilities) in the `nim-stew` directory.

Alternatively, if cloning the repository for the first time:

```bash
git clone --recursive <repository-url>
# or after cloning
git submodule update --init --recursive
```

### Makefile Targets

The project includes a Makefile for common tasks:

- `make help` - Show all available targets
- `make build` or `make rust-build` - Build Rust library and generate C header
- `make install-deps` - Initialize git submodules (stew)
- `make nim-build` - Build Nim examples
- `make examples` - Build and run Nim examples
- `make test` - Run all tests (Rust and Nim)
- `make test-rust` - Run only Rust tests
- `make test-nim` - Run only Nim tests
- `make format` - Format all Nim files
- `make format-check` - Check if Nim files are formatted
- `make clean` - Clean all build artifacts

## Usage

### In Nim

First, install dependencies and build the Rust library:

```bash
make install-deps
make build
```

The `nim/nim_bincode.nim` module provides bindings to the Rust library:

```nim
import nim/nim_bincode

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
nim c -L:target/release your_program.nim
```

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
# Install dependencies and build
make install-deps
make build

# Build and run examples
make examples

# Or build examples manually
make nim-build
./bin/example
./bin/struct_example
```

## Testing

Run tests to verify FFI functions match native bincode behavior:

```bash
# Run all tests (Rust and Nim)
make test

# Run only Rust tests
make test-rust
# or
cargo test

# Run only Nim tests
make test-nim

# Run Rust tests with output
cargo test -- --nocapture

# Run only FFI integration tests
cargo test --test ffi_tests
```

Tests verify:
- FFI serialization/deserialization matches native bincode
- Roundtrip serialization works correctly
- Various data types (strings, integers, structs, mixed data)
- Edge cases (empty vectors, null pointers)

## Formatting

This project uses [nph](https://github.com/arnetheduck/nph) for formatting Nim source code. All Nim files should be formatted before committing.

### Installation

Install `nph` (optional, for code formatting):

```bash
nimble install nph
```

### Format all Nim files

```bash
make format
```

### Check formatting (useful in CI)

```bash
make format-check
```

### Format individual files

```bash
# Format a single file
nph nim/nim_bincode.nim

# Format an entire directory
nph nim/

# Show diff of formatting changes
nph --diff nim/nim_bincode.nim
```

## Project Structure

```
.
├── Cargo.toml          # Rust project configuration
├── Makefile            # Build automation
├── cbindgen.toml       # C header generation config
├── build.rs            # Build script
├── src/
│   └── lib.rs          # Rust FFI wrapper
├── nim/
│   ├── nim_bincode.nim # Nim bindings
│   ├── examples/
│   │   ├── example.nim
│   │   └── struct_example.nim
│   └── tests/          # Nim tests
├── nim-stew/           # Git submodule (stew dependency)
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
