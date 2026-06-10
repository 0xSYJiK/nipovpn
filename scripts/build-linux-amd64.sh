#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  --docker    Build using Docker (requires Docker installed)"
    echo "  --help      Show this help message"
    echo ""
    echo "Without --docker, requires Linux cross-compiler (x86_64-linux-gnu-gcc) to be installed"
}

build_with_docker() {
    echo "Building NipoVPN for Linux amd64 using Docker..."
    
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker not found. Please install Docker first."
        exit 1
    fi
    
    docker build -f Dockerfile.linux-amd64 -t nipovpn-linux-amd64 .
    
    CONTAINER_ID=$(docker create nipovpn-linux-amd64)
    docker cp "$CONTAINER_ID:/src/build/core/nipovpn" nipovpn-linux-amd64
    docker rm "$CONTAINER_ID"
    
    chmod +x nipovpn-linux-amd64
    echo "Build complete. Executable: $(pwd)/nipovpn-linux-amd64"
}

build_native() {
    echo "Building NipoVPN for Linux amd64 natively..."
    
    if ! command -v x86_64-linux-gnu-gcc &> /dev/null; then
        echo "Error: Linux cross-compiler (x86_64-linux-gnu-gcc) not found."
        echo "Install with: sudo apt install gcc-x86-64-linux-gnu g++-x86-64-linux-gnu"
        echo "Or use --docker for containerized build."
        exit 1
    fi
    
    mkdir -p build
    cd build
    
    cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE="$PROJECT_ROOT/toolchain-linux-amd64.cmake" \
        ..
    
    make -j"$(nproc 2>/dev/null || echo 4)"
    
    echo "Build complete. Executable at: build/core/nipovpn"
}

case "${1:-}" in
    --docker)
        build_with_docker
        ;;
    --help|-h)
        usage
        ;;
    "")
        build_native
        ;;
    *)
        echo "Unknown option: $1"
        usage
        exit 1
        ;;
esac