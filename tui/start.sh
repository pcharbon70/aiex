#!/bin/bash

# Aiex TUI Startup Script
# This script provides an easy way to start the TUI with various options

set -e

# Default configuration
BACKEND_URL="ws://localhost:4000/ws"
DEBUG_MODE=""
LOG_FILE=""
BUILD_TYPE="release"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Functions
print_help() {
    echo "Aiex TUI Startup Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -b, --backend URL       Backend WebSocket URL (default: ws://localhost:4000/ws)"
    echo "  -d, --debug             Enable debug mode"
    echo "  -l, --log FILE          Log to file (default: stderr)"
    echo "  -dev, --development     Use development build"
    echo "  --build                 Force rebuild before starting"
    echo "  --test                  Run tests before starting"
    echo "  --check-deps            Check and install dependencies"
    echo ""
    echo "Examples:"
    echo "  $0                      # Start with default settings"
    echo "  $0 --debug --log tui.log"
    echo "  $0 --backend ws://remote:4000/ws"
    echo "  $0 --development --build"
    echo ""
    echo "Environment Variables:"
    echo "  AIEX_BACKEND_URL        Override backend URL"
    echo "  AIEX_DEBUG             Enable debug mode (true/false)"
    echo "  AIEX_LOG_FILE          Log file path"
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

check_dependencies() {
    print_status "Checking dependencies..."
    
    # Check Go version
    if ! command -v go &> /dev/null; then
        print_error "Go is not installed. Please install Go 1.21 or later."
        exit 1
    fi
    
    GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
    REQUIRED_VERSION="1.21"
    
    if ! printf '%s\n%s\n' "$REQUIRED_VERSION" "$GO_VERSION" | sort -V -C; then
        print_error "Go version $GO_VERSION is too old. Please install Go $REQUIRED_VERSION or later."
        exit 1
    fi
    
    print_success "Go version $GO_VERSION is compatible"
    
    # Check if go.mod exists
    if [ ! -f "go.mod" ]; then
        print_error "go.mod not found. Please run this script from the tui directory."
        exit 1
    fi
    
    # Check and install Go dependencies
    print_status "Installing Go dependencies..."
    go mod download
    go mod verify
    print_success "Dependencies installed"
}

check_backend() {
    print_status "Checking backend connectivity..."
    
    # Extract host and port from WebSocket URL
    HOST_PORT=$(echo "$BACKEND_URL" | sed -E 's/ws[s]?:\/\/([^\/]+).*/\1/')
    HOST=$(echo "$HOST_PORT" | cut -d: -f1)
    PORT=$(echo "$HOST_PORT" | cut -d: -f2)
    
    if [ "$PORT" = "$HOST" ]; then
        PORT="4000"  # Default port
    fi
    
    # Check if backend is responding
    if timeout 5 bash -c "</dev/tcp/$HOST/$PORT" 2>/dev/null; then
        print_success "Backend is reachable at $HOST:$PORT"
    else
        print_warning "Backend may not be running at $HOST:$PORT"
        print_status "To start the Elixir backend:"
        print_status "  cd /home/ducky/code/aiex && make dev"
    fi
}

build_application() {
    print_status "Building application..."
    
    if [ "$BUILD_TYPE" = "development" ]; then
        make build-dev
        BINARY_PATH="build/aiex-tui-dev"
    else
        make build
        BINARY_PATH="build/aiex-tui"
    fi
    
    if [ $? -eq 0 ]; then
        print_success "Build completed successfully"
    else
        print_error "Build failed"
        exit 1
    fi
}

run_tests() {
    print_status "Running tests..."
    
    if make test; then
        print_success "All tests passed"
    else
        print_error "Tests failed"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

start_tui() {
    print_status "Starting Aiex TUI..."
    
    # Build command line arguments
    CMD_ARGS=""
    
    if [ -n "$BACKEND_URL" ]; then
        CMD_ARGS="$CMD_ARGS --backend $BACKEND_URL"
    fi
    
    if [ -n "$DEBUG_MODE" ]; then
        CMD_ARGS="$CMD_ARGS --debug"
    fi
    
    if [ -n "$LOG_FILE" ]; then
        CMD_ARGS="$CMD_ARGS --log $LOG_FILE"
    fi
    
    print_status "Command: $BINARY_PATH $CMD_ARGS"
    print_status "Backend: $BACKEND_URL"
    
    if [ -n "$DEBUG_MODE" ]; then
        print_status "Debug mode: enabled"
    fi
    
    if [ -n "$LOG_FILE" ]; then
        print_status "Logging to: $LOG_FILE"
    fi
    
    echo ""
    print_success "Starting TUI... (Press Ctrl+C to quit)"
    echo ""
    
    # Execute the TUI
    exec ./$BINARY_PATH $CMD_ARGS
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            print_help
            exit 0
            ;;
        -b|--backend)
            BACKEND_URL="$2"
            shift 2
            ;;
        -d|--debug)
            DEBUG_MODE="true"
            shift
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        -dev|--development)
            BUILD_TYPE="development"
            shift
            ;;
        --build)
            FORCE_BUILD="true"
            shift
            ;;
        --test)
            RUN_TESTS="true"
            shift
            ;;
        --check-deps)
            CHECK_DEPS="true"
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            print_help
            exit 1
            ;;
    esac
done

# Use environment variables if set
if [ -n "$AIEX_BACKEND_URL" ]; then
    BACKEND_URL="$AIEX_BACKEND_URL"
fi

if [ "$AIEX_DEBUG" = "true" ]; then
    DEBUG_MODE="true"
fi

if [ -n "$AIEX_LOG_FILE" ]; then
    LOG_FILE="$AIEX_LOG_FILE"
fi

# Main execution flow
echo "Aiex TUI Startup Script"
echo "======================="

# Check dependencies if requested
if [ "$CHECK_DEPS" = "true" ]; then
    check_dependencies
fi

# Check if binary exists and build if needed
if [ "$BUILD_TYPE" = "development" ]; then
    BINARY_PATH="build/aiex-tui-dev"
else
    BINARY_PATH="build/aiex-tui"
fi

if [ ! -f "$BINARY_PATH" ] || [ "$FORCE_BUILD" = "true" ]; then
    if [ "$CHECK_DEPS" != "true" ]; then
        check_dependencies
    fi
    build_application
fi

# Run tests if requested
if [ "$RUN_TESTS" = "true" ]; then
    run_tests
fi

# Check backend connectivity
check_backend

# Start the TUI
start_tui