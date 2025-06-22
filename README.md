# DTN7 Swift

![Swift](https://img.shields.io/badge/Swift-6.1-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%20%7C%20macOS%20%7C%20tvOS%20%7C%20watchOS%20%7C%20Linux-lightgray.svg)
![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)
[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)

A Swift implementation of the Delay Tolerant Networking (DTN) Bundle Protocol Version 7 ([RFC 9171](https://datatracker.ietf.org/doc/html/rfc9171)).

DTN7 Swift is a port of the [dtn7-rs](https://github.com/dtn7/dtn7-rs) Rust implementation, providing a cross-platform DTN daemon and library for building delay-tolerant applications in Swift.

## Features

- 🚀 **Full BP7 Support**: Complete implementation of Bundle Protocol Version 7
- 🌐 **Multiple Convergence Layers**: TCP, UDP, HTTP, and HTTP Pull
- 🔄 **Flexible Routing**: Epidemic, Flooding, Static, Spray and Wait, and Sink routing algorithms
- 💾 **Persistent Storage**: SQLite-based bundle storage with in-memory option
- 🔌 **Application Interface**: WebSocket and HTTP APIs for application integration
- 🛡️ **Thread-Safe**: Built with Swift's actor model for safe concurrency
- 📱 **Cross-Platform**: Works on iOS, macOS, tvOS, watchOS, and Linux

## Installation

### Swift Package Manager

Add DTN7 to your `Package.swift` dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/edgeengineer/dtn7.git", from: "0.0.1")
]
```

Then add `DTN7` to your target's dependencies:

```swift
targets: [
    .target(
        name: "YourTarget",
        dependencies: ["DTN7"]
    )
]
```

## Quick Start

### Running the DTN Daemon

```bash
# Build the project
swift build

# Run the daemon with default settings
.build/debug/dtnd --nodeid dtn://node1

# Run with specific convergence layer
.build/debug/dtnd --nodeid dtn://node1 -C tcp:port=4556

# Run with epidemic routing
.build/debug/dtnd --nodeid dtn://node1 --routing epidemic
```

### Building a DTN Application

Here's a simple echo service example:

```swift
import Foundation
import DTN7

// Create a DTN client
let client = DTNClient(
    nodeId: "dtn://node1",
    applicationName: "echo-service"
)

// Connect to the daemon
try await client.connect()

// Register a service endpoint
try await client.registerService("echo") { bundle in
    print("Received: \(bundle.text ?? "non-text bundle")")
    
    // Send response back
    if let message = bundle.text {
        try? await client.sendText(
            to: bundle.source,
            message: "ECHO: \(message)"
        )
    }
}

// Send a bundle
try await client.sendText(
    to: "dtn://node2/echo",
    message: "Hello DTN!"
)
```

## Command Line Tools

DTN7 Swift includes several command-line tools that are built as executable targets. Each tool serves a specific purpose in the DTN ecosystem:

### dtnd - DTN Daemon
The main DTN daemon that runs the node. This is the core executable that implements the Bundle Protocol, manages convergence layers, handles routing, and provides APIs for applications.

```bash
# Start daemon with custom configuration
dtnd --nodeid dtn://mynode \
     --web-port 3000 \
     --db mem \
     --routing flooding

# Common options:
# --nodeid: Set the node's endpoint ID (required)
# --web-port: HTTP/WebSocket API port (default: 3000)
# --db: Storage backend - "mem" or "sqlite" (default: sqlite)
# --routing: Routing algorithm - epidemic, flooding, static, spray, sink
# -C: Configure convergence layers (can be specified multiple times)
# -e: Register local endpoints
# -s: Add static peer connections
```

### dtnsend - Send Bundles
A command-line tool for sending bundles through the DTN network. Supports both interactive input and file transmission.

```bash
# Send a text message via stdin
echo "Hello World" | dtnsend -s dtn://node1/app -d dtn://node2/app

# Send a file
dtnsend -s dtn://node1/files -d dtn://node2/files --file data.txt

# Send with custom lifetime (in seconds)
dtnsend -s dtn://node1/app -d dtn://node2/app -l 3600

# Options:
# -s, --sender: Source endpoint ID
# -d, --destination: Destination endpoint ID
# -l, --lifetime: Bundle lifetime in seconds (default: 86400)
# -p, --port: Daemon web port (default: 3000)
# --file: Send file instead of stdin
```

### dtnrecv - Receive Bundles
A command-line tool for receiving bundles from the DTN network. Can run interactively or save bundles to files.

```bash
# Listen for bundles on an endpoint
dtnrecv -e incoming

# Receive and save to file
dtnrecv -e files --save-to downloads/

# Receive with verbose output
dtnrecv -e myapp -v

# Options:
# -e, --endpoint: Local endpoint to receive on
# -p, --port: Daemon web port (default: 3000)
# -v, --verbose: Show detailed bundle information
# --save-to: Directory to save received bundle payloads
# --delete: Delete bundle after receiving (with bundle ID)
```

### dtnquery - Query Daemon Status
A tool for querying and monitoring the DTN daemon's status, including bundle store, peers, and routing information.

```bash
# Get node status
dtnquery status

# List current peers
dtnquery peers

# Show bundle store contents
dtnquery bundles

# Display routing table
dtnquery routes

# Show statistics
dtnquery stats

# Options:
# -p, --port: Daemon web port (default: 3000)
# -j, --json: Output in JSON format
```

### dtntrigger - Execute Commands on Bundle Receipt
A tool that watches for incoming bundles and executes specified commands when bundles arrive. Useful for automated processing.

```bash
# Run a command when bundles arrive
dtntrigger -e commands -- ./process_bundle.sh

# Pass bundle payload to command via stdin
dtntrigger -e data --stdin -- python3 process_data.py

# Options:
# -e, --endpoint: Endpoint to monitor
# -p, --port: Daemon web port (default: 3000)
# --stdin: Pass bundle payload to command via stdin
# --env: Set environment variables with bundle metadata
# --: Separates dtntrigger options from command to execute
```

### dtnecho - Echo Service (Testing)
A simple echo service that receives bundles and sends them back to the sender. Primarily used for testing DTN connectivity and round-trip times.

```bash
# Run echo service
dtnecho

# Run with verbose output
dtnecho -v

# Options:
# -p, --port: Daemon web port (default: 3000)
# -v, --verbose: Show detailed information for each echoed bundle
# --ipv6: Use IPv6 for daemon connection
```

### dtnping - Ping Tool (Testing)
A ping-like tool for testing DTN connectivity and measuring round-trip times. Sends bundles to an echo service and waits for responses.

```bash
# Ping an echo service
dtnping -d dtn://node2/echo

# Send 10 pings with custom size
dtnping -d dtn://node2/echo -c 10 -s 1024

# Set custom timeout
dtnping -d dtn://node2/echo -t 5000

# Options:
# -d, --destination: Destination endpoint (must be an echo service)
# -c, --count: Number of pings to send (default: -1 for infinite)
# -s, --size: Payload size in bytes (default: 64)
# -t, --timeout: Timeout in milliseconds (default: 5000)
# -p, --port: Daemon web port (default: 3000)
# -v, --verbose: Show detailed information
```

## Architecture

DTN7 Swift follows a modular architecture:

- **DtnCore**: Central actor managing all DTN components
- **BundleProcessor**: Handles bundle reception, forwarding, and delivery
- **ConvergenceLayerAgents**: Network protocol implementations (TCP, UDP, HTTP)
- **RoutingAgents**: Bundle forwarding strategies
- **ApplicationAgent**: Manages application endpoints and bundle delivery
- **BundleStore**: Persistent and in-memory storage backends

## Configuration

DTN7 can be configured via command-line arguments or configuration files:

```swift
// Example configuration structure
struct DtnConfig {
    let nodeId: String              // Node endpoint ID
    let webPort: UInt16            // HTTP API port (default: 3000)
    let db: String                 // Storage backend: "mem" or "sqlite"
    let routing: String            // Routing algorithm
    let janitorInterval: TimeInterval  // Cleanup interval
    let discoveryInterval: TimeInterval // Peer discovery interval
}
```

## Convergence Layers

### TCP
```bash
dtnd -C tcp:port=4556:bind=0.0.0.0
```

### UDP
```bash
dtnd -C udp:port=4556:bind=0.0.0.0
```

### HTTP
```bash
dtnd -C http
```

### HTTP Pull
```bash
dtnd -C httppull:interval=30
```

## Routing Algorithms

- **Epidemic**: Forwards bundles to all known peers
- **Flooding**: Sends bundles to all connected peers
- **Static**: Uses predefined routing tables
- **Spray and Wait**: Limited bundle replication
- **Sink**: Never forwards bundles (for testing)

## API Documentation

### Application Interface

DTN7 provides two application interfaces:

#### WebSocket API (Recommended)
- Real-time bundle delivery
- Binary and JSON message formats
- Automatic reconnection

#### HTTP API
- Simple REST endpoints
- Polling-based bundle retrieval
- Suitable for simple integrations

### Example: WebSocket Client

```swift
let interface = WebSocketApplicationInterface(
    host: "localhost",
    port: 3000,
    mode: .data  // or .json
)

try await interface.connect()
try await interface.registerEndpoint("dtn://node1/myapp")

// Send bundle
try await interface.sendBundle(
    from: "dtn://node1/myapp",
    to: "dtn://node2/app",
    payload: "Hello".data(using: .utf8)!,
    lifetime: 3600
)

// Receive bundles
for await bundle in interface.incomingBundles {
    print("Received bundle: \(bundle.bundleId)")
}
```

## Testing

DTN7 Swift includes comprehensive test coverage with both unit tests and integration tests.

### Unit Tests

Unit tests are located in `Tests/UnitTests/` and test individual components in isolation:

- **EndpointIDTests** - Tests for endpoint ID parsing and validation
- **PeerManagerTests** - Tests for peer management functionality
- **ServiceRegistryTests** - Tests for service registration and discovery
- **BundleStoreTests** - Tests for bundle storage implementations
- **RoutingTests** - Tests for routing algorithm implementations

Run unit tests with:
```bash
swift test --filter UnitTests
```

### Integration Tests

Integration tests are located in `Tests/IntegrationTests/` and test multi-component scenarios:

- **BasicIntegrationTests** - Tests basic DTN functionality like ping/echo
- **RoutingIntegrationTests** - Tests routing algorithms with multiple nodes

Run integration tests with:
```bash
swift test --filter IntegrationTests
```

### Shell-based Tests

The `tests/` directory contains shell scripts that test full daemon functionality:

```bash
# Run all shell tests
./tests/run_all_tests.sh

# Run specific test
./tests/local_ping_echo.sh

# Keep test running for debugging
./tests/local_ping_echo.sh -k
```

Available shell tests:
- `local_ping_echo.sh` - Tests echo service functionality
- `lifetime.sh` - Tests bundle expiration
- `store_delete.sh` - Tests bundle deletion
- `local_nodes_dtn.sh` - Tests multi-node communication

## Building from Source

```bash
# Clone the repository
git clone https://github.com/edgeengineer/dtn7.git
cd dtn7

# Build the project
swift build

# Run all tests (unit and integration)
swift test

# Run only unit tests
swift test --filter UnitTests

# Run only integration tests
swift test --filter IntegrationTests

# Run specific test suite
swift test --filter EndpointIDTests

# Run tests with verbose output
swift test --verbose

# Build for release
swift build -c release
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Original [dtn7-rs](https://github.com/dtn7/dtn7-rs) Rust implementation
- [BP7 Swift](https://github.com/NightRaven/BP7) for Bundle Protocol implementation
- The DTN community for protocol specifications and standards

## Support

For questions and support:
- Open an issue on [GitHub](https://github.com/edgeengineer/dtn7/issues)
- Check the [documentation](https://github.com/edgeengineer/dtn7/wiki)
- Join the DTN community discussions