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

DTN7 Swift includes several command-line tools:

### dtnd - DTN Daemon
```bash
# Start daemon with custom configuration
dtnd --nodeid dtn://mynode \
     --web-port 3000 \
     --db mem \
     --routing flooding
```

### dtnsend - Send Bundles
```bash
# Send a text message
echo "Hello World" | dtnsend -s dtn://node1/app -d dtn://node2/app

# Send a file
dtnsend -s dtn://node1/files -d dtn://node2/files --file data.txt
```

### dtnrecv - Receive Bundles
```bash
# Listen for bundles on an endpoint
dtnrecv -e incoming

# Receive and save to file
dtnrecv -e files --save-to downloads/
```

### dtnquery - Query Daemon Status
```bash
# Get node status
dtnquery status

# List peers
dtnquery peers

# Show statistics
dtnquery stats
```

### dtntrigger - Execute Commands on Bundle Receipt
```bash
# Run a command when bundles arrive
dtntrigger -e commands -- ./process_bundle.sh
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

## Building from Source

```bash
# Clone the repository
git clone https://github.com/edgeengineer/dtn7.git
cd dtn7

# Build the project
swift build

# Run tests
swift test

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