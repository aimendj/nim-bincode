.PHONY: help build rust-build nim-build examples test test-rust test-nim clean format format-check install-deps

# Variables
RUST_TARGET = target/release
NIM_SRC = nim
NIM_EXAMPLES = nim/examples
NIM_TESTS = nim/tests
LIB_NAME = libbincode_wrapper.a

# Detect OS for library extension
ifeq ($(OS),Windows_NT)
    LIB_EXT = .lib
else
    LIB_EXT = .a
endif

# Default target
help:
	@echo "Available targets:"
	@echo "  make build          - Build Rust library and generate C header"
	@echo "  make examples       - Build and run Nim examples"
	@echo "  make test           - Run all tests (Rust and Nim)"
	@echo "  make test-rust      - Run Rust tests"
	@echo "  make test-nim       - Run Nim tests"
	@echo "  make format         - Format all Nim files"
	@echo "  make format-check   - Check if Nim files are formatted"
	@echo "  make install-deps   - Install/vendor Nim dependencies (stew)"
	@echo "  make clean          - Clean build artifacts"

# Build Rust library and generate C header
rust-build:
	@echo "Building Rust library..."
	cargo build --release
	@echo "Rust library built: $(RUST_TARGET)/$(LIB_NAME)"

# Build is an alias for rust-build (for compatibility)
build: rust-build

# Install/vendor Nim dependencies
install-deps:
	@echo "Initializing git submodules..."
	@git submodule update --init --recursive
	@echo "Dependencies installed via git submodules"

# Build Nim examples
nim-build: install-deps rust-build
	@echo "Building Nim examples..."
	@mkdir -p bin
	nim c -d:release -o:bin/example $(NIM_EXAMPLES)/example.nim
	nim c -d:release -o:bin/struct_example $(NIM_EXAMPLES)/struct_example.nim
	@echo "Nim examples built in bin/"

# Build and run examples
examples: nim-build
	@echo "Running example..."
	@./bin/example
	@echo "\nRunning struct_example..."
	@./bin/struct_example

# Run all tests
test: test-rust test-nim

# Run Rust tests
test-rust: rust-build
	@echo "Running Rust tests..."
	cargo test

# Run Nim tests
test-nim: install-deps rust-build
	@echo "Running Nim tests..."
	nim c -r $(NIM_TESTS)/test_bincode.nim

# Format all Nim files
format:
	@echo "Formatting Nim files..."
	nph nim/bincode.nim
	nph nim/examples/example.nim
	nph nim/examples/struct_example.nim
	nph nim/tests/test_bincode.nim
	@echo "Formatting complete."

# Check if Nim files are formatted
format-check:
	@echo "Checking Nim file formatting..."
	@nph --check nim/bincode.nim && \
	 nph --check nim/examples/example.nim && \
	 nph --check nim/examples/struct_example.nim && \
	 nph --check nim/tests/test_bincode.nim && \
	 echo "All files are properly formatted." || \
	 (echo "Some files are not formatted. Run 'make format' to fix." && exit 1)

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	cargo clean
	rm -rf bin/
	rm -f nim/examples/example nim/examples/struct_example
	rm -f nim/tests/test_bincode
	rm -rf nimcache/
	rm -f bincode_wrapper.h
	@echo "Clean complete."
