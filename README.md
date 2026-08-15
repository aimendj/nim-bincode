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

Before building Nim code, install dependencies from `bincode.nimble` (including [stew](https://github.com/status-im/nim-stew) for endian/LEB128 utilities and `deriveBincode` macro helpers):

```bash
make install-deps
```

This runs `nimble develop`, which fetches stew, faststreams, and other Nimble deps and wires them into the local build.

Alternatively:

```bash
nimble develop
```

### Makefile Targets

The project includes a Makefile for common tasks:

- `make help` - Show all available targets
- `make build` - Build Nim examples
- `make examples` - Build and run Nim examples
- `make test` - Run all tests (Nim + format + cross-verification + markers)
- `make test-nim` - Run Nim tests (config, basic, derive macro)
- `make test-format` - Run Rust bincode format verification tests
- `make test-cross` - Run all Nim↔Rust cross-verification tests
- `make test-cross-variable` - Run variable-length encoding cross-verification tests
- `make test-cross-fixed8` - Run fixed 8-byte encoding cross-verification tests
- `make test-cross-fixed4` - Run Nim fixed 4-byte length-prefix roundtrip tests (no Rust)
- `make test-markers` - Run marker byte prefix verification tests (0xfb, 0xfc, 0xfd)
- `make benchmark` - Run performance benchmarks (Rust vs Nim)
- `make install-deps` - Install Nim dependencies (`nimble develop`)
- `make format` - Format all Nim files
- `make format-check` - Check if Nim files are formatted
- `make clean` - Clean all build artifacts

## Usage

### In Nim

First, install dependencies:

```bash
make install-deps
```

The `src/bincode.nim` module provides the native Nim implementation. With this repository’s `nim.cfg` (or after `nimble install`), use a single import:

```nim
import bincode

# Encode bytes
let data = @[byte(1), 2, 3, 4, 5]
let encoded = encode(data)
let decoded = decode(encoded, seq[byte])

# Encode strings
let text = "Hello, world!"
let encodedText = encode(text)
let decodedText = decode(encodedText, string)
```

Compile your Nim program with:

```bash
nim c your_program.nim
```

### Structs and enums (`deriveBincode`)

For Rust-like `#[derive(Encode, Decode)]`, use the `deriveBincode` macro on types you define. It generates uniform `encode`, `decode`, `decodeAt`, `writeValue`, and `readValue` procedures for your types. You can also use `Bincode.encode(val)` / `Bincode.decode(bytes, Type)` via `nim-serialization`.

Supported field types:

- Scalars: `bool`, `char`, `byte`, signed/unsigned integers, `float32`, `float64`
- `string`, `seq[byte]`, `seq[T]` (length-prefixed elements)
- Fixed-size `array[N, T]` (raw `N * sizeof(T)` bytes on the wire)
- Nested objects (call `deriveBincode` on each nested object type)
- Plain enums and case objects (enum discriminant is a **plain 4-byte `u32`**, not length-prefixed, matching Rust bincode)

```nim
import bincode
import bincode_config
import bincode_derive

type Person* = object
  name*: string
  age*: uint32

deriveBincode(Person)

type Status* = enum
  Active
  Inactive

deriveBincode(Status)

# Match Rust: little-endian, fixed 8-byte container lengths
let cfg =
  standard().withLittleEndian().withFixedIntEncoding(8).withLimit(65536'u64)

let wire = encode(Person(name: "Alice", age: 30'u32), cfg)
let back = decode(wire, Person, cfg)

# Or via nim-serialization API:
let serWire = Bincode.encode(Person(name: "Bob", age: 25'u32))
let serBack = Bincode.decode(serWire, Person)
```

See `examples/derive_example.nim` for strings, enums, `seq[byte]`, `seq[string]`, mixed structs, and hex dumps of the wire format.

### Custom Encoded Types (`deriveBincodeCustom`)

For domain-specific types with their own binary serialization (e.g. custom transactions, cryptographic signatures, or domain wrappers), use `deriveBincodeCustom(Type, encodeProc, decodeProc, [errorType])`. On the wire, these types are represented as length-prefixed byte sequences (`Vec<u8>` layout), seamlessly integrating into outer structs derived with `deriveBincode`:

```nim
type CustomPayload* = object
  raw*: string

func toBytes*(c: CustomPayload): seq[byte] =
  @(c.raw.toOpenArrayByte(0, c.raw.high))

func fromBytes*(b: openArray[byte]): CustomPayload =
  var s = newString(b.len)
  if b.len > 0:
    copyMem(s[0].addr, b[0].unsafeAddr, b.len)
  CustomPayload(raw: s)

# Single-line registration:
deriveBincodeCustom(CustomPayload, toBytes, fromBytes)

type Envelope* = object
  id*: uint64
  payload*: CustomPayload
  extra*: seq[CustomPayload]

# Seamlessly integrates with deriveBincode on outer types:
deriveBincode(Envelope)

let env = Envelope(
  id: 42'u64,
  payload: CustomPayload(raw: "hello"),
  extra: @[CustomPayload(raw: "world")]
)

let wire = encode(env)
let back = decode(wire, Envelope)
assert back == env
```

### Configuration

Use `bincode_config` builders to control endianness, fixed vs variable-length integer encoding, and size limits:

```nim
import bincode_config

let cfg = standard()
  .withLittleEndian()
  .withFixedIntEncoding(8)   # 8-byte length prefixes for Vec/String
  .withLimit(65536'u64)
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
./bin/derive_example
```

| Example | Description |
|---------|-------------|
| `example.nim` | Basic `Vec<u8>` and string serialization |
| `struct_example.nim` | `deriveBincode` on simple structs, enums, and packets |
| `derive_example.nim` | Wire-format walkthrough with hex output |

## Testing

Run tests to verify the Nim implementation matches Rust bincode behavior:

```bash
# Run all tests (Nim + format + cross-verification + markers)
make test

# Run only Nim tests (config, basic, derive)
make test-nim

# Run cross-verification tests (Nim ↔ Rust)
make test-cross

# Run marker byte prefix verification tests
make test-markers

# Run specific cross-verification test suites
make test-cross-variable  # Variable-length encoding
make test-cross-fixed8    # Fixed 8-byte encoding
make test-cross-fixed4    # Fixed 4-byte length prefixes (Nim-only)
```

Tests verify:

- Nim serialization/deserialization matches Rust bincode (for covered types and configs)
- Roundtrip serialization works correctly
- `deriveBincode` roundtrips (`tests/test_derive.nim`)
- Marker byte prefixes (0xfb, 0xfc, 0xfd) are correctly used in variable-length encoding
- Various data types (strings, integers, structs, mixed data)
- Edge cases (empty vectors, large arrays up to 4GB+)

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
nph src/bincode.nim

# Format an entire directory
nph src/

# Show diff of formatting changes
nph --diff src/bincode.nim
```

## Project Structure

```
.
├── bincode.nimble          # Nim package manifest (stew, faststreams, …)
├── Cargo.toml              # Rust test harness configuration
├── Makefile                # Build and test automation
├── src/
│   ├── bincode.nim         # Main public API (re-exports submodules)
│   ├── bincode_common.nim  # Core byte serialization/deserialization
│   ├── bincode_helpers.nim # Strings, Vec<u8>-wrapped ints, plain u32
│   ├── bincode_fields.nim  # Per-field scalar/enum serializers
│   ├── bincode_config.nim  # Configuration types and builders
│   ├── bincode_derive.nim  # deriveBincode macro
│   └── examples/
│       ├── example.nim
│       ├── struct_example.nim
│       └── derive_example.nim
├── tests/
│   ├── bincode_format.rs
│   ├── cross_verification.rs
│   ├── test_bincode.nim
│   ├── test_bincode_config.nim
│   ├── test_cross_verification.nim
│   └── test_derive.nim
└── README.md
```

## API

### Nim API

**Top-level** (`bincode.nim`):

- `serialize` / `deserialize` — length-prefixed `seq[byte]` blobs
- `serializeString` / `deserializeString` — UTF-8 strings
- `serializeType` / `deserializeType` — custom types via `toBytes` / `fromBytes`
- `deriveBincode(Type)` — generate `serializeType` / `deserializeType` for a type

**Field helpers** (`bincode_fields.nim`, exported via `bincode`):

- `serializeBincode*` / `deserializeBincode*` for scalars, `bool`, `char`, enums
- `serializeBincodeEnumDiscriminant` / `deserializeBincodeEnumDiscriminant` — plain 4-byte `u32`

**Helpers** (`bincode_helpers.nim`):

- `serializeBincodeU32` / `deserializeBincodeU32` — plain fixed-width `u32` (not length-prefixed)
- String and prefixed-byte helpers used by the macro and manual struct code

**Config** (`bincode_config.nim`):

- `standard()`, `withLittleEndian()`, `withBigEndian()`, `withFixedIntEncoding()`, `withVariableIntEncoding()`, `withLimit()`, etc.

## Notes

- The implementation targets a **subset** of bincode v2. Generic `Vec<u8>` / string encoding is cross-verified against Rust; derived structs and enums should be checked per type (see `derive_example.nim` hex output and `make test-cross`).
- Enum discriminants use a **plain 4-byte `u32`**, not a length-prefixed integer, to match Rust `bincode` for enums.
- Container lengths (`String`, `Vec<T>`) follow `BincodeConfig.intSize` (variable LEB128 or fixed 4/8 bytes).
- Uses a bincode v2-compatible configuration; the exact wire format is exercised and verified in the Rust and Nim tests in `tests/`.

## License

MIT/Apache-2.0 (same as bincode crate)
