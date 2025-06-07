#!/usr/bin/env bash
# Package Aiex as a single distributable archive

set -euo pipefail

# Configuration
VERSION=$(grep 'version:' mix.exs | sed 's/.*version: "\(.*\)".*/\1/')
RELEASE_NAME="aiex-${VERSION}"
BUILD_DIR="_build/prod/rel/aiex"
PACKAGE_DIR="_build/packages"

echo "📦 Packaging Aiex v${VERSION} for distribution..."

# Ensure release is built
if [ ! -d "$BUILD_DIR" ]; then
    echo "❌ Release not found. Building first..."
    ./scripts/build-release.sh
fi

# Create package directory
mkdir -p "$PACKAGE_DIR"
cd "$PACKAGE_DIR"

# Create different package formats
echo "🗜️  Creating distribution packages..."

# 1. Tar.gz archive (Unix/Linux)
echo "  📄 Creating tar.gz archive..."
tar -czf "${RELEASE_NAME}-linux-x64.tar.gz" \
    -C "$(dirname "../$BUILD_DIR")" \
    --transform "s|^aiex|${RELEASE_NAME}|" \
    aiex

# 2. Self-extracting archive
echo "  🚀 Creating self-extracting installer..."
cat > "${RELEASE_NAME}-installer.sh" << 'EOF'
#!/bin/bash
# Aiex Self-Extracting Installer

set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin"
EXTRACT_DIR="/tmp/aiex-install-$$"

# Create extraction directory
mkdir -p "$EXTRACT_DIR"
cd "$EXTRACT_DIR"

# Extract archive (embedded below)
echo "📦 Extracting Aiex..."
tail -n +__ARCHIVE_LINE__ "$0" | tar -xzf -

# Install
echo "⚡ Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

# Copy main executable
cp aiex-*/bin/aiex "$INSTALL_DIR/aiex"
chmod +x "$INSTALL_DIR/aiex"

# Copy the full release if requested
if [[ "${1:-}" == "--full" ]]; then
    FULL_INSTALL_DIR="${HOME}/.local/share/aiex"
    echo "📁 Installing full release to $FULL_INSTALL_DIR..."
    mkdir -p "$FULL_INSTALL_DIR"
    cp -r aiex-*/* "$FULL_INSTALL_DIR/"
    
    # Update launcher to point to full installation
    sed -i "s|RELEASE_DIR=.*|RELEASE_DIR=\"$FULL_INSTALL_DIR\"|" "$INSTALL_DIR/aiex"
fi

# Cleanup
cd /
rm -rf "$EXTRACT_DIR"

echo "✅ Aiex installed successfully!"
echo ""
echo "🎯 Usage:"
echo "  aiex help                  # Show help"
echo "  aiex start-iex             # Start interactive mode"
echo "  aiex cli create module Foo # Create module"
echo ""
echo "Add $INSTALL_DIR to your PATH if not already present:"
echo "  export PATH=\"$INSTALL_DIR:\$PATH\""

exit 0
__ARCHIVE_BELOW__
EOF

# Append the archive to the installer
echo "__ARCHIVE_LINE__=$(wc -l < "${RELEASE_NAME}-installer.sh")" > temp_marker
sed -i "s/__ARCHIVE_LINE__/$(cat temp_marker | cut -d= -f2)/" "${RELEASE_NAME}-installer.sh"
rm temp_marker

cat "${RELEASE_NAME}-linux-x64.tar.gz" >> "${RELEASE_NAME}-installer.sh"
chmod +x "${RELEASE_NAME}-installer.sh"

# 3. Docker image preparation (Dockerfile)
echo "  🐳 Creating Dockerfile..."
cat > "Dockerfile" << EOF
FROM alpine:3.18

# Install runtime dependencies
RUN apk add --no-cache \\
    ncurses-libs \\
    libstdc++ \\
    libgcc \\
    ca-certificates

# Create aiex user
RUN adduser -D -h /app aiex

# Copy release
COPY ${RELEASE_NAME} /app/aiex
RUN chown -R aiex:aiex /app/aiex

USER aiex
WORKDIR /app

# Expose TUI port
EXPOSE 9487

# Default command
CMD ["/app/aiex/bin/aiex", "start"]
EOF

# 4. Usage documentation
cat > "README.md" << EOF
# Aiex v${VERSION} - Distribution Package

This package contains the Aiex distributed AI-powered Elixir coding assistant.

## Installation Options

### 1. Quick Install (Recommended)
\`\`\`bash
# Self-extracting installer
chmod +x ${RELEASE_NAME}-installer.sh
./${RELEASE_NAME}-installer.sh

# Or with full installation
./${RELEASE_NAME}-installer.sh --full
\`\`\`

### 2. Manual Install
\`\`\`bash
# Extract archive
tar -xzf ${RELEASE_NAME}-linux-x64.tar.gz

# Run directly
./${RELEASE_NAME}/bin/aiex help

# Or install to PATH
cp ${RELEASE_NAME}/bin/aiex ~/.local/bin/
\`\`\`

### 3. Docker
\`\`\`bash
# Build image
docker build -t aiex:${VERSION} .

# Run
docker run -it --rm -p 9487:9487 aiex:${VERSION}
\`\`\`

## Usage

\`\`\`bash
aiex help                    # Show all commands
aiex start-iex               # Interactive development  
aiex cli create module Calc  # Generate module
aiex tui                     # Terminal UI (if available)
\`\`\`

## Requirements

- Linux x64
- glibc 2.17+ (most modern distributions)
- Optional: API keys for LLM providers (OpenAI, Anthropic)

## Configuration

Set environment variables:
\`\`\`bash
export OPENAI_API_KEY="your-key"
export ANTHROPIC_API_KEY="your-key"
\`\`\`

For more information: https://github.com/your-org/aiex
EOF

echo "✅ Packages created:"
echo "  📦 ${RELEASE_NAME}-linux-x64.tar.gz (Archive)"
echo "  🚀 ${RELEASE_NAME}-installer.sh (Self-extracting)"
echo "  🐳 Dockerfile (Container)"
echo "  📖 README.md (Documentation)"
echo ""
echo "📁 Location: $PWD"
echo ""
echo "🧪 Test the installer:"
echo "  ./${RELEASE_NAME}-installer.sh"