.PHONY: help build examples test test-nim test-format test-cross test-cross-variable test-cross-fixed8 test-markers clean format format-check install-deps

# Variables
NIM_SRC = nim
NIM_EXAMPLES = nim/examples
NIM_TESTS = nim/tests

# Default target
help:
	@echo "Available targets:"
	@echo "  make build          - Build Nim examples"
	@echo "  make examples       - Build and run Nim examples"
	@echo "  make test           - Run all tests (Nim + format + cross-verification + markers)"
	@echo "  make test-nim       - Run Nim tests (config + basic)"
	@echo "  make test-format    - Run Rust bincode format verification tests"
	@echo "  make test-cross     - Run all Nim↔Rust cross-verification tests"
	@echo "  make test-cross-variable - Run variable-length encoding cross-verification tests"
	@echo "  make test-cross-fixed8 - Run fixed 8-byte encoding cross-verification tests"
	@echo "  make test-markers   - Run marker byte prefix verification tests (0xfb, 0xfc, 0xfd)"
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
	nim c -d:release $(NIM_EXAMPLES)/example.nim
	nim c -d:release $(NIM_EXAMPLES)/struct_example.nim
	@echo "Nim examples built in bin/"

# Build and run examples
examples: build
	@echo "Running example..."
	@./bin/example
	@echo "\nRunning struct_example..."
	@./bin/struct_example

# Run all tests
test: test-nim test-format test-cross test-markers

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
	@if [ ! -f target/nim_test_variable ] || [ $(NIM_TESTS)/test_cross_verification.nim -nt target/nim_test_variable ]; then \
		echo "Compiling Nim test (variable) with optimizations..."; \
		nim c -d:release -d:testVariable -o:target/nim_test_variable $(NIM_TESTS)/test_cross_verification.nim; \
	fi
	@start=$$(date +%s); if ./target/nim_test_variable 2>&1 | tee /tmp/nim_step2_var.log | grep -A 50 "Rust serialize → Nim deserialize (variable encoding)" | grep -E "\[OK\]|\[FAIL\]|^Deserialized"; then \
		end=$$(date +%s); echo "Nim Step 2 (variable) took $$((end-start))s"; \
	else \
		end=$$(date +%s); echo "Nim Step 2 (variable) took $$((end-start))s"; \
		echo "ERROR: Step 2 failed - check if Rust serialization files exist"; \
		cat /tmp/nim_step2_var.log | tail -50; \
		exit 1; \
	fi
	@echo "Step 3: Nim serializes data (variable)..."
	@start=$$(date +%s); if ./target/nim_test_variable 2>&1 | tee /tmp/nim_step3_var.log | grep -A 50 "Nim serialize → Rust deserialize (variable encoding)" | grep -E "\[OK\]|\[FAIL\]|Created.*variable|^Serialized"; then \
		end=$$(date +%s); echo "Nim Step 3 (variable) took $$((end-start))s"; \
	else \
		end=$$(date +%s); echo "Nim Step 3 (variable) took $$((end-start))s"; \
		echo "ERROR: Step 3 failed"; \
		cat /tmp/nim_step3_var.log | tail -50; \
		exit 1; \
	fi
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
	@if [ ! -f target/nim_test_fixed8 ] || [ $(NIM_TESTS)/test_cross_verification.nim -nt target/nim_test_fixed8 ]; then \
		echo "Compiling Nim test (fixed8) with optimizations..."; \
		nim c -d:release -d:testFixed8 -o:target/nim_test_fixed8 $(NIM_TESTS)/test_cross_verification.nim; \
	fi
	@start=$$(date +%s); if ./target/nim_test_fixed8 2>&1 | tee /tmp/nim_step2_fixed8.log | grep -A 50 "Rust serialize → Nim deserialize (fixed 8-byte)" | grep -E "\[OK\]|\[FAIL\]|^Deserialized"; then \
		end=$$(date +%s); echo "Nim Step 2 (fixed8) took $$((end-start))s"; \
	else \
		end=$$(date +%s); echo "Nim Step 2 (fixed8) took $$((end-start))s"; \
		echo "ERROR: Step 2 failed - check if Rust serialization files exist"; \
		cat /tmp/nim_step2_fixed8.log | tail -50; \
		exit 1; \
	fi
	@echo "Step 3: Nim serializes data (fixed 8-byte)..."
	@start=$$(date +%s); if ./target/nim_test_fixed8 2>&1 | tee /tmp/nim_step3_fixed8.log | grep -A 50 "Nim serialize → Rust deserialize (fixed 8-byte)" | grep -E "\[OK\]|\[FAIL\]|Created.*fixed8|^Serialized"; then \
		end=$$(date +%s); echo "Nim Step 3 (fixed8) took $$((end-start))s"; \
	else \
		end=$$(date +%s); echo "Nim Step 3 (fixed8) took $$((end-start))s"; \
		echo "ERROR: Step 3 failed"; \
		cat /tmp/nim_step3_fixed8.log | tail -50; \
		exit 1; \
	fi
	@echo "Step 4: Rust deserializes Nim data (fixed 8-byte)..."
	@cargo test --test cross_verification test_nim_serialize_rust_deserialize_fixed8 -- --nocapture || (echo "ERROR: Step 4 failed - check if Nim serialization files exist" && exit 1)
	@echo "Fixed 8-byte encoding tests complete!"

# Run Rust bincode format verification tests
test-format: install-deps
	@echo "=== Rust Bincode Format Verification Tests ==="
	@cargo test --test bincode_format -- --nocapture

# Run marker byte prefix verification tests
test-markers: install-deps
	@echo "=== Marker Byte Prefix Verification Tests ==="
	@echo "Testing Rust marker byte prefixes..."
	@cargo test --test cross_verification test_marker_byte_prefixes_variable -- --nocapture
	@echo ""
	@echo "Testing Rust byte-for-byte compatibility (variable)..."
	@cargo test --test cross_verification test_byte_for_byte_compatibility_variable -- --nocapture
	@echo ""
	@echo "Testing Rust byte-for-byte compatibility (fixed8)..."
	@cargo test --test cross_verification test_byte_for_byte_compatibility_fixed8 -- --nocapture
	@echo ""
	@echo "Testing Nim marker byte prefixes..."
	@# Reuse the binary from test-cross-variable if it exists, otherwise compile
	@if [ ! -f target/nim_test_variable ]; then \
		echo "Compiling Nim test (variable) with optimizations..."; \
		nim c -d:release -d:testVariable -o:target/nim_test_variable $(NIM_TESTS)/test_cross_verification.nim; \
	fi
	@./target/nim_test_variable 2>&1 | grep -A 20 "verify marker byte prefixes" || true
	@echo "Marker byte prefix tests complete!"

# Run Nim tests
test-nim: install-deps
	@echo "Running Nim tests..."
	@echo "Running bincode config tests..."
	nim c -r $(NIM_TESTS)/test_bincode_config.nim
	@echo "Running bincode basic tests..."
	nim c -r $(NIM_TESTS)/test_bincode.nim

# Format all Nim files
format:
	@echo "Formatting Nim files..."
	nph nim/nim_bincode.nim
	nph nim/bincode_common.nim
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
	 nph --check nim/bincode_common.nim && \
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
	rm -f target/nim_test_variable target/nim_test_fixed8
	rm -rf nimcache/
	@echo "Clean complete."
