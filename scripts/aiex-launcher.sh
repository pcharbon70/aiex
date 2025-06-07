#!/usr/bin/env bash
# Aiex - Single Executable Launcher
# This script serves as a unified entry point for the Aiex distributed coding assistant

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELEASE_DIR="${SCRIPT_DIR}/../_build/prod/rel/aiex"
AIEX_BIN="${RELEASE_DIR}/bin/aiex"
TUI_BIN="${RELEASE_DIR}/bin/aiex-tui"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if release exists
check_release() {
    if [ ! -f "$AIEX_BIN" ]; then
        log_error "Release not found. Please build the release first:"
        echo "  ./scripts/build-release.sh"
        exit 1
    fi
}

# Show usage information
show_usage() {
    cat << EOF
🤖 Aiex - Distributed AI-powered Elixir Coding Assistant

USAGE:
    $0 <COMMAND> [OPTIONS]

COMMANDS:
    start           Start Aiex OTP server as daemon
    start-iex       Start Aiex with interactive IEx shell
    stop            Stop running Aiex daemon
    restart         Restart Aiex daemon
    status          Show Aiex daemon status
    
    tui             Launch the Terminal User Interface (TUI)
    cli <args>      Run CLI commands (create, analyze, etc.)
    
    version         Show version information
    help            Show this help message

EXAMPLES:
    $0 start-iex                          # Interactive development
    $0 cli create module Calculator        # Generate module via CLI
    $0 tui                                # Launch visual TUI
    $0 start && $0 tui                    # Start server + TUI

ARCHITECTURE:
    Aiex runs as a distributed OTP application with multiple interfaces:
    - OTP Server: Core distributed AI services (context, LLM coordination)
    - CLI: Command-line interface for quick operations  
    - TUI: Rich terminal interface for interactive development
    - Future: Web UI (LiveView) and VS Code LSP

For more information: https://github.com/your-org/aiex
EOF
}

# Main command dispatcher
main() {
    case "${1:-help}" in
        "start")
            check_release
            log_info "Starting Aiex OTP server..."
            exec "$AIEX_BIN" start
            ;;
        "start-iex")
            check_release
            log_info "Starting Aiex with IEx shell..."
            exec "$AIEX_BIN" start_iex
            ;;
        "stop")
            check_release
            log_info "Stopping Aiex daemon..."
            exec "$AIEX_BIN" stop
            ;;
        "restart")
            check_release
            log_info "Restarting Aiex daemon..."
            exec "$AIEX_BIN" restart
            ;;
        "status"|"ping")
            check_release
            exec "$AIEX_BIN" ping
            ;;
        "tui")
            if [ -f "$TUI_BIN" ]; then
                log_info "Launching Aiex TUI..."
                exec "$TUI_BIN"
            else
                log_error "TUI binary not found. Build with Rust TUI support:"
                echo "  cd tui && cargo build --release"
                echo "  ./scripts/build-release.sh"
                exit 1
            fi
            ;;
        "cli")
            check_release
            shift # Remove 'cli' from arguments
            log_info "Executing CLI command: $*"
            exec "$AIEX_BIN" eval "Aiex.CLI.main([$(printf '"%s",' "$@" | sed 's/,$//')]))"
            ;;
        "version")
            check_release
            exec "$AIEX_BIN" version
            ;;
        "help"|"--help"|"-h")
            show_usage
            ;;
        *)
            log_error "Unknown command: $1"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Handle signals gracefully
trap 'log_warning "Interrupted"; exit 130' INT TERM

# Run main function
main "$@"