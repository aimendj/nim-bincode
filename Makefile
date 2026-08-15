.PHONY: help build examples test test-nim test-cross format format-check install-deps clean
.DEFAULT_GOAL := build

# Variables
NIM_SRC = src
NIM_EXAMPLES = examples
NIM_TESTS = tests

# Help target
help:
	@echo "Available targets:"
	@echo "  make build        - Compile library (default)"
	@echo "  make help         - Show this help message"
	@echo "  make test-nim     - Run all Nim unit tests (single summary report)"
	@echo "  make test-cross   - Run Rust ↔ Nim cross-verification (bidirectional)"
	@echo "  make test         - Run both Nim tests and cross-verification tests"
	@echo "  make examples     - Build and run Nim examples"
	@echo "  make format       - Format all Nim files with nph"
	@echo "  make format-check - Check if Nim files are formatted"
	@echo "  make install-deps - Install Nim dependencies via nimble develop"
	@echo "  make clean        - Clean build artifacts"

# Install Nim dependencies via nimble
install-deps:
	@echo "Installing Nim dependencies..."
	nimble develop -y
	@echo "Dependencies installed."

# Run Nim unit tests
test-nim: install-deps
	@echo "Running Nim unit tests..."
	nim c -r $(NIM_TESTS)/test_all.nim

# Run bidirectional Rust ↔ Nim cross-verification tests
test-cross: install-deps
	@nim c -r $(NIM_TESTS)/test_cross_runner.nim

# Run all tests (Nim unit tests + cross-verification)
test: test-nim test-cross

# Compile library
build: install-deps
	@echo "Compiling library..."
	nim c -c -d:release $(NIM_SRC)/bincode.nim
	@echo "Build successful."

# Build and run Nim examples
examples: install-deps
	@echo "Building Nim examples..."
	@mkdir -p bin
	nim c -d:release $(NIM_EXAMPLES)/example.nim
	nim c -d:release $(NIM_EXAMPLES)/struct_example.nim
	nim c -d:release $(NIM_EXAMPLES)/derive_example.nim
	@echo "Running example..."
	@./bin/example
	@echo "\nRunning struct_example..."
	@./bin/struct_example
	@echo "\nRunning derive_example..."
	@./bin/derive_example

# Format all Nim source and test files
format:
	@echo "Formatting Nim files..."
	nph src/bincode.nim
	nph src/bincode/config.nim
	nph src/bincode/codecs.nim
	nph src/bincode/derive.nim
	nph src/bincode/serialization.nim
	nph examples/example.nim
	nph examples/struct_example.nim
	nph examples/derive_example.nim
	nph tests/test_all.nim
	nph tests/test_config.nim
	nph tests/test_codecs.nim
	nph tests/test_derive.nim
	nph tests/test_serialization.nim
	nph tests/test_cross_runner.nim
	nph tests/test_cross_verification.nim
	@echo "Formatting complete."

# Check if Nim files are formatted
format-check:
	@echo "Checking formatting of Nim files..."
	@nph --check src/bincode.nim && \
	 nph --check src/bincode/config.nim && \
	 nph --check src/bincode/codecs.nim && \
	 nph --check src/bincode/derive.nim && \
	 nph --check src/bincode/serialization.nim && \
	 nph --check examples/example.nim && \
	 nph --check examples/struct_example.nim && \
	 nph --check examples/derive_example.nim && \
	 nph --check tests/test_all.nim && \
	 nph --check tests/test_config.nim && \
	 nph --check tests/test_codecs.nim && \
	 nph --check tests/test_derive.nim && \
	 nph --check tests/test_serialization.nim && \
	 nph --check tests/test_cross_runner.nim && \
	 nph --check tests/test_cross_verification.nim && \
	 echo "All files are properly formatted." || \
	 (echo "Some files are not formatted. Run 'make format' to fix." && exit 1)

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	cargo clean --manifest-path rust/Cargo.toml
	rm -rf bin/
	rm -rf target/
	rm -rf rust/target/
	rm -rf nimcache/
	@echo "Clean complete."
