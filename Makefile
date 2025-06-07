# Aiex - Distributed AI Coding Assistant
# Build and distribution targets

.PHONY: help build release package clean dev test

# Default target
help:
	@echo "🤖 Aiex - Distributed AI Coding Assistant"
	@echo ""
	@echo "TARGETS:"
	@echo "  dev        Start development server (iex -S mix)"
	@echo "  build      Build development version"
	@echo "  release    Build production release"
	@echo "  package    Create distribution packages"
	@echo "  test       Run test suite"
	@echo "  clean      Clean build artifacts"
	@echo ""
	@echo "SINGLE EXECUTABLE OPTIONS:"
	@echo "  make release && make package"
	@echo "  ./scripts/build-release.sh"
	@echo "  ./_build/packages/aiex-*-installer.sh"

# Development
dev:
	@echo "🚀 Starting Aiex development server..."
	iex -S mix

build:
	@echo "📦 Building Aiex..."
	mix deps.get
	mix compile

# Production release
release:
	@echo "⚡ Building production release..."
	./scripts/build-release.sh

# Create distribution packages
package: release
	@echo "📦 Creating distribution packages..."
	./scripts/package-release.sh

# Testing
test:
	@echo "🧪 Running test suite..."
	mix test

# Cleanup
clean:
	@echo "🧹 Cleaning build artifacts..."
	mix clean
	rm -rf _build/prod
	rm -rf _build/packages
	@if [ -d "tui" ]; then \
		echo "🧹 Cleaning Rust artifacts..."; \
		cd tui && cargo clean; \
	fi

# Install dependencies
deps:
	@echo "📥 Installing dependencies..."
	mix deps.get
	@if [ -d "tui" ]; then \
		echo "📥 Installing Rust dependencies..."; \
		cd tui && cargo fetch; \
	fi

# Format code
fmt:
	@echo "✨ Formatting code..."
	mix format
	@if [ -d "tui" ]; then \
		cd tui && cargo fmt; \
	fi

# Development helpers
escript:
	@echo "📜 Building escript..."
	mix escript.build

docker:
	@echo "🐳 Building Docker image..."
	@if [ ! -d "_build/packages" ]; then \
		echo "❌ No packages found. Run 'make package' first."; \
		exit 1; \
	fi
	cd _build/packages && docker build -t aiex:latest .

# Quick start for new users
quick-start: deps build
	@echo ""
	@echo "✅ Aiex is ready!"
	@echo ""
	@echo "🎯 Quick start:"
	@echo "  make dev                    # Start development"
	@echo "  ./aiex version              # Test escript"
	@echo "  make release && make package # Create installer"