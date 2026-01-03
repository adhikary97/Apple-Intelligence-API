#!/bin/bash

# Apple Intelligence API - Server + UI Launcher
# This script starts the server and launches the UI once the server is ready

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_PORT=8080
MAX_WAIT_SECONDS=120
SERVER_PID=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup() {
    if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        log_info "Shutting down server (PID: $SERVER_PID)..."
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
}

trap cleanup EXIT INT TERM

wait_for_server() {
    local elapsed=0
    log_info "Waiting for server to be ready on port $SERVER_PORT..."

    while [ $elapsed -lt $MAX_WAIT_SECONDS ]; do
        if curl -s "http://localhost:$SERVER_PORT/api/v1/models" > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))

        # Check if server process is still running
        if [ -n "$SERVER_PID" ] && ! kill -0 "$SERVER_PID" 2>/dev/null; then
            log_error "Server process died unexpectedly"
            return 1
        fi

        # Show progress every 5 seconds
        if [ $((elapsed % 5)) -eq 0 ]; then
            log_info "Still waiting... ($elapsed seconds elapsed)"
        fi
    done

    log_error "Server did not become ready within $MAX_WAIT_SECONDS seconds"
    return 1
}

# Main script
cd "$SCRIPT_DIR"

log_info "=========================================="
log_info "  Apple Intelligence API Launcher"
log_info "=========================================="
echo ""

# Check if server is already running
if curl -s "http://localhost:$SERVER_PORT/api/v1/models" > /dev/null 2>&1; then
    log_warn "Server is already running on port $SERVER_PORT"
    SERVER_ALREADY_RUNNING=true
else
    SERVER_ALREADY_RUNNING=false

    # Build the server
    log_info "Building server..."
    if ! swift build 2>&1 | tail -5; then
        log_error "Failed to build server"
        exit 1
    fi
    log_success "Server built successfully"

    # Start the server in background
    log_info "Starting server..."
    swift run AppleIntelligenceApi &
    SERVER_PID=$!
    log_info "Server started with PID: $SERVER_PID"

    # Wait for server to be ready
    if ! wait_for_server; then
        log_error "Failed to start server"
        exit 1
    fi
    log_success "Server is ready!"
fi

echo ""

# Build and run the UI
log_info "Building UI app..."
cd "$SCRIPT_DIR/AppleIntelligenceChat"

if ! swift build 2>&1 | tail -5; then
    log_error "Failed to build UI app"
    exit 1
fi
log_success "UI app built successfully"

echo ""
log_info "Launching UI app..."
log_info "Press Ctrl+C to stop both server and UI"
echo ""

# Run the UI app (this will block until UI is closed)
swift run AppleIntelligenceChat

# If we started the server, it will be cleaned up by the trap
if [ "$SERVER_ALREADY_RUNNING" = false ]; then
    log_info "UI closed. Stopping server..."
fi
