# NipoVPN - Agent Development Guide

This document provides comprehensive context for AI agents working on the NipoVPN project. It covers project architecture, code structure, workflows, coding conventions, and development practices.

## Project Overview

**NipoVPN** is a C++ proxy tool that conceals HTTP requests within fake HTTP requests to avoid detection. It supports HTTP and SOCKS5 protocols and uses Boost for networking.

### Core Purpose
- Bypass network filtering by obfuscating legitimate HTTP traffic inside decoy requests
- Hide HTTP requests from network monitoring
- Support both HTTP proxy and SOCKS5 proxy modes

### Architecture Modes
- **Server Mode**: Runs on a server, receives obfuscated requests from agents, forwards to real destinations
- **Agent Mode**: Runs on a client device, intercepts traffic and sends it to server via obfuscated HTTP requests

## Technology Stack

| Component | Technology |
|-----------|------------|
| Language | C++20 |
| Build System | CMake 3.22+ |
| Networking | Boost.Asio (standalone), Boost.Beast |
| Configuration | yaml-cpp (>= 0.8) |
| SSL/TLS | OpenSSL |
| Threading | std::thread / std::jthread (Android) |

### Compiler Flags
```
-Wall -Wextra -ggdb -MMD -MP
```

## Directory Structure

```
nipovpn/
├── core/                    # Main executable source code
│   ├── src/
│   │   ├── main.cpp         # Entry point
│   │   ├── config.hpp/cpp   # Configuration management (YAML parsing)
│   │   ├── runner.hpp/cpp   # Thread pool and IO context management
│   │   ├── tcpserver.hpp/cpp    # TCP server accepting connections
│   │   ├── tcpconnection.hpp/cpp # Connection handler per client
│   │   ├── tcpclient.hpp/cpp # TCP client for outbound connections
│   │   ├── serverhandler.hpp/cpp # Request handler for server mode
│   │   ├── agenthandler.hpp/cpp  # Request handler for agent mode
│   │   ├── http.hpp/cpp     # HTTP/TLS request parsing and generation
│   │   ├── http_utils.hpp   # HTTP utility functions
│   │   ├── log.hpp/cpp      # Thread-safe logging
│   │   └── general.hpp      # Common utilities, types, encryption
│   └── CMakeLists.txt
├── server/                  # Server-specific build config (empty)
├── agent/                   # Agent-specific build config (empty)
├── docs/                    # Documentation
├── files/                   # Images and resources
├── scripts/
│   └── format.sh           # Code formatting script
├── guides/
│   ├── BuildLinux.md       # Linux build instructions
│   └── InstallTermux.md    # Termux installation guide
├── CMakeLists.txt           # Root CMake configuration
├── .clang-format           # Clang formatting rules (Google-based)
└── .clang-tidy             # Clang-tidy static analysis rules
```

## Core Components and Workflows

### 1. Main Entry Point (`main.cpp`)

```
main()
├── validateConfig()         # Validates arguments and config file
├── Config::create()         # Loads YAML configuration
├── Log::create()            # Initializes logging
└── Runner(config, log).run()  # Starts the application
```

**Usage**: `nipovpn <mode> <config_file_path>`
- `mode`: "server" or "agent"
- `config_file_path`: Path to YAML config file

### 2. Configuration (`config.hpp/cpp`)

The `Config` class parses YAML configuration with these sections:

#### General Block
```yaml
general:
  token: <string>              # AES-256 encryption key
  protocol: <"http"|"socks5">  # Proxy protocol mode
  fakeUrls: [<string>, ...]     # Decoy URLs for obfuscation
  methods: [<string>, ...]      # HTTP methods (GET, POST, etc.)
  endPoints: [<string>, ...]    # Random endpoints
  timeout: <unsigned short>     # Connection timeout (seconds)
  pullTimeout: <unsigned short> # Polling timeout for tunnel mode
  tunnelEnable: <bool>          # Enable direct TCP tunneling
  connectionReuse: <bool>       # Reuse connections (keep-alive)
  tlsEnable: <bool>             # Enable TLS
  tlsVerifyPeer: <bool>         # Verify peer certificates
  tlsCertFile: <string>         # TLS certificate file
  tlsKeyFile: <string>          # TLS key file
  tlsCaFile: <string>           # TLS CA file
```

#### Log Block
```yaml
log:
  logFile: <string>             # Log file path
  logLevel: <"INFO"|"TRACE"|"DEBUG"> # Log level
```

#### Server Block (for server mode)
```yaml
server:
  threads: <unsigned short>     # Worker threads
  listenIp: <string>            # Bind IP
  listenPort: <unsigned short>  # Bind port
```

#### Agent Block (for agent mode)
```yaml
agent:
  threads: <unsigned short>
  listenIp: <string>
  listenPort: <unsigned short>
  serverIp: <string>            # Server IP to connect to
  serverPort: <unsigned short>  # Server port
  httpVersion: <string>         # HTTP version (e.g., "1.1")
  userAgent: <string>           # User-Agent header
```

### 3. Runner (`runner.hpp/cpp`)

Manages the thread pool and io_context:

- Creates worker threads based on `config->threads()`
- Each thread runs `io_context::run()`
- Uses `executor_work_guard` to keep io_context alive
- Threads use `std::jthread` on non-Android, `std::thread` on Android

### 4. TCPServer (`tcpserver.hpp/cpp`)

Accepts incoming TCP connections and dispatches to handlers:

```
TCPServer
├── startAccept()              # Begin accepting connections
├── handleAccept()             # Per-connection handler
│   ├── Creates TCPClient and TCPConnection
│   ├── If TLS enabled: initTlsServerContext() + doHandshakeServer()
│   ├── If server mode: connection->startServer()
│   └── If agent mode: connection->startAgent()
```

### 5. TCPConnection (`tcpconnection.hpp/cpp`)

Handles each client connection with async I/O:

**Key Methods**:
- `startAgent()` / `startServer()` - Entry points based on mode
- `doReadAgent()` - Async read in agent mode
- `doReadServer()` - Async read in server mode
- `handleReadAgent()` / `handleReadServer()` - Read completion handlers
- `relayClientToServer()` / `relayServerToClient()` - Direct tunnel relaying (agent mode)
- `relayAgentToTarget()` / `relayTargetToAgent()` - Tunnel relaying (server mode)
- `postTunnelAction(action, body)` - Encodes and sends data to server via HTTP

**HTTP Obfuscation Headers**:
- `X-Nipo-Session`: UUID for session tracking
- `X-Nipo-Action`: Action type (`"open"`, `"request"`, `"send"`, `"recv"`, `"close"`)
- `Host`: Random fake URL (obscures real destination)
- `User-Agent`: Configured user agent

### 6. TCPClient (`tcpclient.hpp/cpp`)

Manages outbound connections:

**States**:
- `tlsEnabled_` - Whether TLS is active
- `closed_` - Socket closed flag

**Key Methods**:
- `doConnect(dstIp, dstPort)` - Connect to destination
- `enableTlsClient()` - Initialize TLS context for client
- `doHandshakeClient()` - Perform TLS handshake
- `doWrite(buffer)` - Write data to socket
- `doReadAgent()` - Read HTTP response from server
- `doReadServer()` - Read arbitrary data from target

### 7. ServerHandler (`serverhandler.hpp/cpp`)

Handles requests received by server mode:

```
handle()
├── detectType() - Detect HTTP/TLS type
├── Decrypt body with AES-256 + Base64
├── Extract X-Nipo-Session and X-Nipo-Action headers
├── Handle actions:
│   ├── "send": Forward data to target client
│   ├── "recv": Poll data from target client
│   ├── "close": Close target client connection
│   ├── Other: Parse inner request
│       ├── If CONNECT: Establish tunnel
│       ├── If HTTP/HTTPS: Forward to target
```

**Session Management**:
Static `sessions_` map tracks active client connections:
```cpp
static std::unordered_map<std::string, TCPClient::pointer> sessions_;
```

### 8. AgentHandler (`agenthandler.hpp/cpp`)

Handles requests in agent mode:

```
handle()
├── detectType() - Detect HTTP/TLS type
├── Connect to server if not already connected
├── Encrypt request body with AES-256
├── Base64 encode encrypted data
├── Send obfuscated HTTP request to server
└── Decrypt and process response
```

### 9. HTTP (`http.hpp/cpp`)

HTTP/TLS request parsing and generation:

**HttpType Enum**:
- `https` - TLS traffic
- `http` - HTTP traffic
- `connect` - HTTP CONNECT method (tunnel)

**TlsTypes Enum**:
- `TLSHandshake` - 0x16 byte prefix
- `ChangeCipherSpec` - 0x14 byte prefix
- `ApplicationData` - 0x17 byte prefix

**Detection Logic**:
```cpp
detectType():
  First 2 hex chars of streambuf:
    "16" → TLSHandshake
    "14" → ChangeCipherSpec
    "17" → ApplicationData
    Other → parseHttp()
```

### 10. HTTP Utils (`http_utils.hpp`)

Utility functions in `http_utils` namespace:

- `toLowerCopy(s)` - Convert to lowercase
- `trimCopy(s)` - Trim whitespace
- `extractHeaders(msg)` - Get headers (before \r\n\r\n)
- `extractBody(msg)` - Get body (after \r\n\r\n)
- `parseContentLength(headers, value)` - Parse Content-Length header
- `isChunked(headers)` - Check for chunked Transfer-Encoding
- `getRawHeader(headers, name)` - Extract specific header value

### 11. General (`general.hpp`)

Shared utilities and cryptographic functions:

**Types**:
```cpp
static constexpr std::size_t BufferSize = 8192;

struct BoolStr { bool ok; std::string message; };

class Uncopyable {
    Uncopyable(const Uncopyable &) = delete;
    Uncopyable &operator=(const Uncopyable &) = delete;
};
```

**Encryption Functions**:
```cpp
aes256Encrypt(plaintext, key) → BoolStr { ciphertext_with_iv }
aes256Decrypt(ciphertext_with_iv, key) → BoolStr { plaintext }
```

Uses OpenSSL EVP API with AES-256-CBC:
- IV prepended to ciphertext
- PKCS#7 padding applied

**Encoding Functions**:
```cpp
encode64(input) → std::string
decode64(input) → std::string
hexArrToStr(data, size) → std::string  // Binary to hex
hexToASCII(hex) → std::string         // Hex to ASCII
hexStreambufToStr(buff) → std::string // Streambuf to hex
```

## Request Flow

### Agent Mode Flow (Client → Server → Target)

```
1. Client connects to Agent (local)
2. Agent reads HTTP/SOCKS5 request
3. Agent encrypts request body with AES-256
4. Agent Base64 encodes encrypted data
5. Agent sends POST to Server with:
   - Random method (GET/POST/etc.)
   - Random endpoint
   - Random fake URL as Host header
   - X-Nipo-Session header (UUID)
   - X-Nipo-Action header ("open" or "request")
   - Encrypted payload in body
6. Server receives request
7. Server decrypts body
8. Server forwards to target destination
9. Response returns through reverse path
```

### Tunnel Mode Flow

When `tunnelEnable: true` and CONNECT is used:

```
Agent Side (Client ↔ Agent ↔ Server):
1. Client sends CONNECT request
2. Agent establishes persistent connection to Server
3. Agent sends "open" action with CONNECT details
4. Server establishes connection to Target
5. Direct data relay:
   - Client → Agent: read, hex encode, send "send" action
   - Server polls with "recv" action at pullTimeout intervals
   - Server reads from Target → Agent → Client

Server Side (Agent ↔ Server ↔ Target):
- For "send": Forward data to target client socket
- For "recv": Read available data from target, encrypt/response
- For "close": Cleanup session
```

## Coding Conventions

### Headers
- Use `#pragma once` instead of include guards
- Include order: related header first, then standard library, then boost/3rd-party
- Private members declared before public members in classes

### Naming Conventions
- Classes: `PascalCase` (e.g., `TCPServer`, `HTTP`)
- Methods: `camelCase` (e.g., `doConnect`, `handleAccept`)
- Variables: `snake_case` or `camelCase` (mixed in codebase)
- Member variables: `_` suffix (e.g., `config_`, `log_`)
- Boolean values: prefix with `is`, `has`, `ok` (e.g., `tlsEnabled_`, `closed_`)
- Shared pointers: `using pointer = std::shared_ptr<ClassName>`

### Memory Management
- Use `std::shared_ptr` for shared ownership
- Use `std::enable_shared_from_this` for self-referencing
- Use `std::unique_ptr` for exclusive ownership (e.g., `tlsSocket_`)
- Thread safety via `std::mutex` and `std::lock_guard`

### Threading
- Use `boost::asio::strand` for thread-safe handlers
- Use `std::atomic<bool>` for atomic flags
- Android uses `std::thread`, others use `std::jthread`

### Error Handling
- Log errors with `log_->write(..., Log::Level::ERROR)`
- Use `BoolStr` struct for operations that can fail with message
- Catch exceptions by reference (`const std::exception &e`)
- Handle `boost::system::error_code` for Boost.Asio operations

### Encryption Format
```
encrypted_data = IV (16 bytes) + ciphertext
transmitted = Base64(IV + ciphertext)
```

IV is extracted during decryption:
```cpp
std::memcpy(iv, ciphertext_with_iv.c_str(), EVP_CIPHER_iv_length(EVP_aes_256_cbc()));
ciphertext = ciphertext_with_iv.substr(EVP_CIPHER_iv_length(EVP_aes_256_cbc()));
```

## Build Instructions

### Linux
```bash
sudo apt install cmake libssl-dev libboost-all-dev
mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Debug ..
make -j$(nproc)
```

### Formatting
```bash
scripts/format.sh
# Uses clang-format with .clang-format settings
```

### Dependencies
- Boost 1.88.0+ (regex, system components)
- yaml-cpp 0.8+
- OpenSSL (for SSL/TLS support)

## Security Notes

1. **Encryption**: AES-256-CBC with random IV
2. **Session Tracking**: UUID-based session identification
3. **TLS Configuration**:
   - Minimum TLS 1.2
   - Strong cipher suites (AES-GCM, ChaCha20-Poly1305)
   - SNI spoofing for obfuscation
   - ALPN for HTTP/1.1 negotiation

## Debugging Tips

1. Set `logLevel: DEBUG` or `TRACE` in config
2. Check log file at configured path
3. UUID is logged with every message for request tracing
4. Session tracking uses UUID as map key

## Example Configuration

The default config is located at `nipovpn/etc/nipovpn/config.yaml`:

```yaml
---
general:
  token: "af445adb-2434-4975-9445-2c1b2231"
  protocol: http
  fakeUrls:
    - nipo.ciron.net
    - sudoer.ir
    - sudoer.net
    - google.com
    - cloudflare.com
  methods:
    - GET
    - POST
    - PUT
    - DELETE
  endPoints:
    - api
    - login
    - user
    - update
  timeout: 10
  pullTimeout: 50
  tunnelEnable: false
  connectionReuse: true
  tlsEnable: false
  tlsVerifyPeer: false
  tlsCertFile: "/etc/nipovpn/server.crt"
  tlsKeyFile: "/etc/nipovpn/server.key"
  tlsCaFile: ""

log:
  logLevel: "DEBUG"
  logFile: "/var/log/nipovpn/nipovpn.log"

server:
  threads: 8
  listenIp: "0.0.0.0"
  listenPort: 80

agent:
  threads: 8
  listenIp: "0.0.0.0"
  listenPort: 8080
  serverIp: "127.0.0.10"
  serverPort: 80
  httpVersion: "1.1"
  userAgent : "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0"
```

## CI/CD Pipelines

GitHub Actions workflows for multi-platform builds:

- `debian-main.yml` - Builds Debian packages for amd64/arm64, Termux packages
- `debian-dev.yml` - Development builds for Debian
- `android-main.yml` - Android release builds
- `android-dev.yml` - Android development builds
- `windows-main.yml` - Windows release builds
- `windows-dev.yml` - Windows development builds

## File Modification Guidelines

- **Adding features**: Modify appropriate handler (ServerHandler/AgentHandler)
- **Protocol changes**: Update HTTP class and related utils
- **Configuration changes**: Update Config struct and parser
- **New relay modes**: Add to TCPConnection relay methods
- **Always format**: Run `scripts/format.sh` before committing