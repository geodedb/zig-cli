# Makefile for zig-cli library
#
# Usage:
#   make              - Build and run all tests
#   make test         - Run unit tests only
#   make demo         - Build and run the demo
#   make clean        - Clean build artifacts
#   make help         - Show this help message

.PHONY: all build test test-integration test-all demo clean check fmt help ci \
       bench scale-bench bench-save bench-compare bench-baseline

# Default target - build and run all tests
all: build test
	@echo ""
	@echo "All builds and tests completed successfully!"
	@echo ""

# Build the library
build:
	@echo "Building zig-cli library..."
	@zig build

# Run unit tests
test:
	@echo "Running unit tests..."
	@zig build test --summary all

# Run integration tests
test-integration:
	@echo "Running integration tests..."
	@zig build test-integration --summary all

# Run all tests
test-all: test test-integration
	@echo ""
	@echo "All tests completed"

# Build and run demo
demo:
	@echo "Building and running demo..."
	@zig build run -- --help

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf zig-cache zig-out .zig-cache
	@echo "Clean complete"

# Check syntax without building
check:
	@echo "Checking for compilation errors..."
	@zig build check
	@echo "Check complete"

# Format all Zig source files
fmt:
	@echo "Formatting source files..."
	@zig fmt src/ tests/ examples/ build.zig
	@echo "Format complete"

# Run tests with optimization levels
test-release-safe:
	@echo "Running tests with ReleaseSafe optimization..."
	@zig build test -Doptimize=ReleaseSafe --summary all

test-release-fast:
	@echo "Running tests with ReleaseFast optimization..."
	@zig build test -Doptimize=ReleaseFast --summary all

test-release-small:
	@echo "Running tests with ReleaseSmall optimization..."
	@zig build test -Doptimize=ReleaseSmall --summary all

# Run all optimization level tests
test-all-optimizations: test test-release-safe test-release-fast test-release-small
	@echo "All optimization level tests completed"

# Continuous integration target
ci: clean build test test-integration
	@echo ""
	@echo "CI pipeline completed successfully!"

# Development workflow - quick iteration
dev: fmt check test
	@echo "Development checks passed"

# Generate documentation
docs:
	@echo "Generating documentation..."
	@zig build docs
	@echo "Documentation generated in zig-out/docs/"

# Generate shell completions
completions:
	@echo "Generating shell completions..."
	@mkdir -p completions
	@zig build run -- completion --shell bash > completions/demo.bash 2>/dev/null || true
	@zig build run -- completion --shell zsh > completions/_demo 2>/dev/null || true
	@zig build run -- completion --shell fish > completions/demo.fish 2>/dev/null || true
	@echo "Completions generated in completions/"

# Generate man page
man:
	@echo "Generating man page..."
	@mkdir -p man
	@zig build run -- man > man/demo.1 2>/dev/null || true
	@echo "Man page generated in man/"

# ========================================================================
# Benchmarks
# ========================================================================

# Quick benchmarks (human-readable output)
bench:
	@echo "Running quick benchmarks..."
	@zig build bench

# Scale benchmarks with JSON output (human summary on stderr)
scale-bench:
	@zig build scale-bench 2>/dev/null

# Save scale benchmark results with git commit hash
bench-save:
	@echo "Running scale benchmarks and saving results..."
	@zig build scale-bench 2>/dev/null > benchmarks/results/$$(git rev-parse --short HEAD).json
	@echo "Results saved to benchmarks/results/$$(git rev-parse --short HEAD).json"

# Compare current performance against baseline
bench-compare:
	@echo "Running scale benchmarks..."
	@zig build scale-bench 2>/dev/null > /tmp/cli-bench-current.json
	@echo "Comparing against baseline..."
	@zig build compare-bench -- benchmarks/results/baseline.json /tmp/cli-bench-current.json

# Update baseline with current performance
bench-baseline:
	@echo "Running scale benchmarks to establish baseline..."
	@zig build scale-bench 2>/dev/null > benchmarks/results/baseline.json
	@echo "Baseline updated: benchmarks/results/baseline.json"

# Show help message
help:
	@echo "zig-cli - CLI and Config Library for Zig"
	@echo ""
	@echo "Usage:"
	@echo "  make [target]"
	@echo ""
	@echo "Main Targets:"
	@echo "  all              - Build and run all tests (default)"
	@echo "  build            - Build the library"
	@echo "  test             - Run unit tests"
	@echo "  test-integration - Run integration tests"
	@echo "  test-all         - Run all tests"
	@echo "  demo             - Build and run the demo"
	@echo ""
	@echo "Development Targets:"
	@echo "  clean            - Remove build artifacts"
	@echo "  check            - Check for compilation errors"
	@echo "  fmt              - Format all Zig source files"
	@echo "  dev              - Quick development workflow (fmt + check + test)"
	@echo "  docs             - Generate documentation"
	@echo ""
	@echo "Optimization Testing:"
	@echo "  test-release-safe  - Run tests with ReleaseSafe"
	@echo "  test-release-fast  - Run tests with ReleaseFast"
	@echo "  test-release-small - Run tests with ReleaseSmall"
	@echo "  test-all-optimizations - Run tests with all optimization levels"
	@echo ""
	@echo "Benchmarks:"
	@echo "  bench            - Run quick performance benchmarks"
	@echo "  scale-bench      - Run scale benchmarks with JSON output"
	@echo "  bench-save       - Save results keyed by git commit hash"
	@echo "  bench-compare    - Compare current vs baseline (exit 1 on regression)"
	@echo "  bench-baseline   - Update the baseline with current performance"
	@echo ""
	@echo "Code Generation:"
	@echo "  completions      - Generate shell completion scripts"
	@echo "  man              - Generate man page"
	@echo ""
	@echo "CI/CD:"
	@echo "  ci               - Full CI pipeline (clean + build + all tests)"
	@echo ""
	@echo "Requirements:"
	@echo "  - Zig 0.16.0 or compatible"
	@echo ""
	@echo "For more information, see README.md"
