# Bincode Nim Library

Native Nim implementation of the Rust [bincode](https://crates.io/crates/bincode)
serialization format, plus Rust tests for cross-verification.

## Prerequisites

For using the Nim library:

- Nim compiler - [Install Nim](https://nim-lang.org/install.html)
- Make - Usually pre-installed on Unix systems

For running the optional Rust test harness and cross-verification:

- Rust (with cargo) - [Install Rust](https://www.rust-lang.org/tools/install)

## Building

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
- `make build` - Build Nim examples
- `make examples` - Build and run Nim examples
- `make test` - Run all unit tests (Rust + Nim)
- `make test-rust` - Run Rust test harness only
- `make test-nim` - Run Nim tests only
- `make test-cross` - Run all Nim↔Rust cross-verification tests
- `make test-cross-variable` - Run variable-length encoding cross-verification tests
- `make test-cross-fixed8` - Run fixed 8-byte encoding cross-verification tests
- `make install-deps` - Initialize git submodules (stew)
- `make format` - Format all Nim files
- `make format-check` - Check if Nim files are formatted
- `make clean` - Clean all build artifacts

## Usage

### In Nim

First, install dependencies:

```bash
make install-deps
```

The `nim/nim_bincode.nim` module provides the native Nim implementation:

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
nim c your_program.nim
```

### In Rust

Rust is used in this repository for cross-verification tests. In Rust, use bincode directly:

```rust
use bincode;

let data = vec![1u8, 2, 3, 4, 5];
let encoded = bincode::encode_to_vec(&data, bincode::config::standard())?;
let (decoded, _): (Vec<u8>, _) = bincode::decode_from_slice(&encoded, bincode::config::standard())?;
```

## Examples

### Nim examples

```bash
# Install dependencies
make install-deps

# Build and run examples
make examples

# Or build examples manually
make build
./bin/example
./bin/struct_example
```

## Testing

Run tests to verify the Nim implementation matches Rust bincode behavior:

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
```

Tests verify:
- Nim serialization/deserialization matches Rust bincode
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
├── Cargo.toml          # Rust test harness configuration
├── Makefile            # Build and test automation
├── nim/
│   ├── nim_bincode.nim # Native Nim bincode implementation
│   ├── examples/
│   │   ├── example.nim
│   │   └── struct_example.nim
│   └── tests/          # Nim tests (including cross-verification)
├── nim-stew/           # Git submodule (stew dependency)
├── tests/              # Rust tests for format and cross-verification
└── README.md
```

## API

### Nim API

- `serialize(data: seq[byte]): seq[byte]`: Serialize a sequence of bytes
- `deserialize(data: seq[byte]): seq[byte]`: Deserialize bincode-encoded data
- `serializeString(s: string): seq[byte]`: Serialize a string (UTF-8)
- `deserializeString(data: seq[byte]): string`: Deserialize a string (UTF-8)

## Notes

- The implementation serializes/deserializes `Vec<u8>` (byte vectors) for generic binary data handling
- Uses a bincode v2-compatible configuration; the exact wire format is exercised and verified in the Rust tests in `tests/` and the Nim tests in `nim/tests/`

## License

MIT/Apache-2.0 (same as bincode crate)
