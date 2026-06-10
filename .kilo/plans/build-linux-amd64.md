# Build NipoVPN for Linux amd64

## Overview
Build the NipoVPN C++ proxy tool for Linux x86_64 architecture.

## Prerequisites Check
- CMake 3.22+
- C++20 compiler (gcc 11+ or clang 14+)
- libssl-dev (OpenSSL)
- libboost-all-dev (Boost libraries)
- libyaml-cpp-dev (yaml-cpp)

## Method 1: Using Docker (Recommended for Windows hosts)

### Prerequisites
Install Docker Desktop and ensure it's running.

### Build Steps
```powershell
# From project root
docker build -f Dockerfile.linux-amd64 -t nipovpn-build .
docker create --name temp-build nipovpn-build
docker cp temp-build:/src/build/core/nipovpn nipovpn-linux-amd64
docker rm temp-build
```

## Method 2: On Linux (Native build)

### 1. Install Dependencies
```bash
sudo apt update
sudo apt install -y cmake build-essential libssl-dev libboost-all-dev libyaml-cpp-dev
```

### 2. Create Build Directory
```bash
mkdir -p build
cd build
```

### 3. Configure CMake
```bash
cmake -DCMAKE_BUILD_TYPE=Release ..
```

### 4. Build
```bash
make -j$(nproc)
```

### 5. Verify Build
The executable will be at `build/core/nipovpn`

## Method 3: Using WSL on Windows

1. Install WSL: `wsl --install -d Ubuntu-24.04`
2. In WSL, follow Method 2 steps

## Method 4: Cross-compilation on Windows (Advanced)

Requires Linux cross-compiler toolchain (x86_64-linux-gnu-gcc) and Linux sysroot.

### Using the toolchain
```bash
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE=../toolchain-linux-amd64.cmake ..
make -j$(nproc)
```

## Post-Build Setup

### Create Log Directory
```bash
sudo mkdir -p /var/log/nipovpn
sudo touch /var/log/nipovpn/nipovpn.log
```

### Prepare Configuration
The config template is at `nipovpn/etc/nipovpn/config.yaml`. Copy to a system location:
```bash
sudo mkdir -p /etc/nipovpn
sudo cp nipovpn/etc/nipovpn/config.yaml /etc/nipovpn/config.yaml
```

### Run (optional)
```bash
./build/core/nipovpn server /etc/nipovpn/config.yaml
```

## Notes
- Default config uses HTTP protocol, port 80 for server
- Agent mode listens on port 8080 and connects to server
- Build type can be Debug for development or Release for production
- For WSL installation issues, ensure Windows Subsystem for Linux optional feature is enabled