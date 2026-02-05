.PHONY: help build examples test test-rust test-nim test-cross test-cross-variable test-cross-fixed8 clean format format-check install-deps

# Variables
NIM_SRC = nim
NIM_EXAMPLES = nim/examples
NIM_TESTS = nim/tests

# Default target
help:
	@echo "Available targets:"
	@echo "  make build          - Build Nim examples"
	@echo "  make examples       - Build and run Nim examples"
	@echo "  make test           - Run all unit tests (Rust + Nim)"
	@echo "  make test-rust      - Run Rust test harness only"
	@echo "  make test-nim       - Run Nim tests only"
	@echo "  make test-cross     - Run all Nim↔Rust cross-verification tests"
	@echo "  make test-cross-variable - Run variable-length encoding cross-verification tests"
	@echo "  make test-cross-fixed8 - Run fixed 8-byte encoding cross-verification tests"
	@echo "  make format         - Format all Nim files"
	@echo "  make format-check   - Check if Nim files are formatted"
	@echo "  make install-deps   - Install/vendor Nim dependencies (stew)"
	@echo "  make clean          - Clean build artifacts"

# Install/vendor Nim dependencies
install-deps:
	@echo "Initializing git submodules..."
	@git submodule update --init --recursive
	@echo "Dependencies installed via git submodules"

# Build Nim (examples)
build: install-deps
	@echo "Building Nim examples..."
	@mkdir -p bin
	nim c -d:release -o:bin/example $(NIM_EXAMPLES)/example.nim
	nim c -d:release -o:bin/struct_example $(NIM_EXAMPLES)/struct_example.nim
	@echo "Nim examples built in bin/"

# Build and run examples
examples: build
	@echo "Running example..."
	@./bin/example
	@echo "\nRunning struct_example..."
	@./bin/struct_example

# Run all tests
test: test-rust test-nim

# Run Rust tests
# Note: cargo test will automatically build test executables if needed
test-rust:
	@echo "Running Rust tests..."
	cargo test

# Run all cross-verification tests (requires both Rust and Nim)
test-cross: test-cross-variable test-cross-fixed8
	@echo ""
	@echo "All variable + fixed 8-byte cross-verification tests complete!"

# Run variable-length encoding cross-verification tests
test-cross-variable: install-deps
	@echo "=== Variable-Length Encoding (LEB128) ==="
	@rm -rf target/test_data
	@mkdir -p target/test_data
	@echo "Step 1: Rust serializes data (variable)..."
	cargo test --test cross_verification test_rust_serialize_nim_deserialize_variable -- --nocapture
	@echo "Step 2: Nim deserializes Rust data (variable)..."
	@start=$$(date +%s); nim c -r -d:testVariable $(NIM_TESTS)/test_cross_verification.nim 2>&1 | grep -A 20 "Rust serialize → Nim deserialize (variable encoding)" | grep -E "\[OK\]|\[FAIL\]|^Deserialized" || true; end=$$(date +%s); echo "Nim Step 2 (variable) took $$((end-start))s"
	@if ! nim c -r -d:testVariable $(NIM_TESTS)/test_cross_verification.nim > /dev/null 2>&1; then \
		echo "ERROR: Step 2 failed - check if Rust serialization files exist"; \
		exit 1; \
	fi
	@echo "Step 3: Nim serializes data (variable)..."
	@start=$$(date +%s); nim c -r -d:testVariable $(NIM_TESTS)/test_cross_verification.nim 2>&1 | grep -A 50 "Nim serialize → Rust deserialize (variable encoding)" | grep -E "\[OK\]|\[FAIL\]|Created.*variable|^Serialized" || true; end=$$(date +%s); echo "Nim Step 3 (variable) took $$((end-start))s"
	@echo "Step 4: Rust deserializes Nim data (variable)..."
	@cargo test --test cross_verification test_nim_serialize_rust_deserialize_variable -- --nocapture || (echo "ERROR: Step 4 failed - check if Nim serialization files exist" && exit 1)
	@echo "Variable-length encoding tests complete!"

# Run fixed 8-byte encoding cross-verification tests
test-cross-fixed8: install-deps
	@echo "=== Fixed 8-byte Encoding ==="
	@rm -rf target/test_data
	@mkdir -p target/test_data
	@echo "Step 1: Rust serializes data (fixed 8-byte)..."
	cargo test --test cross_verification test_rust_serialize_nim_deserialize_fixed8 -- --nocapture
	@echo "Step 2: Nim deserializes Rust data (fixed 8-byte)..."
	@start=$$(date +%s); nim c -r -d:testFixed8 $(NIM_TESTS)/test_cross_verification.nim 2>&1 | grep -A 20 "Rust serialize → Nim deserialize (fixed 8-byte)" | grep -E "\[OK\]|\[FAIL\]|^Deserialized" || true; end=$$(date +%s); echo "Nim Step 2 (fixed8) took $$((end-start))s"
	@if ! nim c -r -d:testFixed8 $(NIM_TESTS)/test_cross_verification.nim > /dev/null 2>&1; then \
		echo "ERROR: Step 2 failed - check if Rust serialization files exist"; \
		exit 1; \
	fi
	@echo "Step 3: Nim serializes data (fixed 8-byte)..."
	@start=$$(date +%s); nim c -r -d:testFixed8 $(NIM_TESTS)/test_cross_verification.nim 2>&1 | grep -A 50 "Nim serialize → Rust deserialize (fixed 8-byte)" | grep -E "\[OK\]|\[FAIL\]|Created.*fixed8|^Serialized" || true; end=$$(date +%s); echo "Nim Step 3 (fixed8) took $$((end-start))s"
	@echo "Step 4: Rust deserializes Nim data (fixed 8-byte)..."
	@cargo test --test cross_verification test_nim_serialize_rust_deserialize_fixed8 -- --nocapture || (echo "ERROR: Step 4 failed - check if Nim serialization files exist" && exit 1)
	@echo "Fixed 8-byte encoding tests complete!"

# Run Nim tests
test-nim: install-deps
	@echo "Running Nim tests..."
	nim c -r $(NIM_TESTS)/test_bincode.nim
	nim c -r $(NIM_TESTS)/test_bincode_config.nim

# Format all Nim files
format:
	@echo "Formatting Nim files..."
	nph nim/nim_bincode.nim
	nph nim/bincode_config.nim
	nph nim/examples/example.nim
	nph nim/examples/struct_example.nim
	nph nim/tests/test_bincode.nim
	nph nim/tests/test_bincode_config.nim
	@echo "Formatting complete."

# Check if Nim files are formatted
format-check:
	@echo "Checking Nim file formatting..."
	@nph --check nim/nim_bincode.nim && \
	 nph --check nim/bincode_config.nim && \
	 nph --check nim/examples/example.nim && \
	 nph --check nim/examples/struct_example.nim && \
	 nph --check nim/tests/test_bincode.nim && \
	 nph --check nim/tests/test_bincode_config.nim && \
	 echo "All files are properly formatted." || \
	 (echo "Some files are not formatted. Run 'make format' to fix." && exit 1)

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	cargo clean
	rm -rf bin/
	rm -f nim/examples/example nim/examples/struct_example
	rm -f nim/tests/test_bincode nim/tests/test_bincode_config
	rm -rf nimcache/
	@echo "Clean complete."
