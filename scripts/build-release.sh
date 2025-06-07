#!/usr/bin/env bash
set -euo pipefail

# Build script for creating a single-executable distribution of Aiex
# This script builds both the Elixir OTP application and Rust TUI, 
# then packages them as a portable release.

echo "🚀 Building Aiex Release..."

# Build Rust TUI (if needed)
if [ -d "tui" ]; then
    echo "📦 Building Rust TUI..."
    cd tui
    cargo build --release
    cd ..
fi

# Build Elixir release  
echo "⚡ Building Elixir OTP release..."
MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix compile
MIX_ENV=prod mix release

echo "✅ Release built successfully!"
echo ""
echo "📁 Release location: _build/prod/rel/aiex/"
echo ""
echo "🎯 Usage:"
echo "  ./_build/prod/rel/aiex/bin/aiex start        # Start as daemon"
echo "  ./_build/prod/rel/aiex/bin/aiex start_iex    # Start with IEx"
echo "  ./_build/prod/rel/aiex/bin/aiex version      # Show version"
echo "  ./_build/prod/rel/aiex/bin/aiex-tui          # Start TUI (if available)"
echo ""
echo "📦 To create a portable archive:"
echo "  tar -czf aiex-release.tar.gz -C _build/prod/rel aiex"