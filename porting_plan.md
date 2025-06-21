# Porting dtn7-rs to Swift: A Step-by-Step Plan

This document outlines a phased approach to porting the `dtn7-rs` Rust implementation to a cross-platform Swift library.

## Pre-flight Checklist

- [x] **BP7 Dependency**: A Swift implementation of RFC9171 (`bp7`) is available and included in `Package.swift`.
- [x] **Project Setup**: A basic Swift Package structure exists.
- [x] **Familiarization**: You have a high-level understanding of the `dtn7-rs` architecture, including its main components: daemon, convergence layers, routing algorithms, and command-line tools.

---

## Phase 1: Foundational Components

This phase focuses on setting up the project and porting the core data structures and configuration management.

-   [x] **1.1: Finalize Dependencies in `Package.swift`**: Based on `dtn7-rs`'s `Cargo.toml`, add the following Swift packages:
    -   [x] `swift-nio` for low-level networking (replaces `tokio`).
    -   [x] `swift-argument-parser` for command-line tools (replaces `clap`).
    -   [x] `swift-log` for structured logging.
    -   [x] `Hummingbird` as the web framework (replaces `axum`/`hyper`).
    -   [x] `swift-async-algorithms` for advanced asynchronous sequences.

-   [x] **1.2: Port Core Data Structures**: Create Swift equivalents for the fundamental data types.
    -   [x] `NodeID` and `EndpointID` representations (`dtn7/src/core/mod.rs`).
    -   [x] `Peer` data structure (`dtn7/src/core/peer.rs`).
    -   [x] Error types (`dtn7/src/lib.rs`). Use Swift's `Error` protocol.

-   [x] **1.3: Configuration Management**: Port the configuration handling from `dtn7/src/dtnconfig.rs`.
    -   [x] Create a `DtnConfig` struct that is `Codable` to support loading from files (e.g., JSON or YAML instead of TOML).
    -   [x] Map the command-line arguments (from `clap` in Rust) to `swift-argument-parser` options in the configuration loading logic.

---

## Phase 2: The Daemon and Bundle Processing Core

This phase implements the heart of the DTN daemon: the bundle processing logic and storage.

-   [x] **2.1: Daemon Lifecycle**: Implement the main daemon process (`dtnd`).
    -   [x] Create a `Daemon` class to manage the lifecycle (start, stop).
    -   [x] Set up the main actor-based concurrency model.

-   [x] **2.2: Bundle Processing Pipeline**: Port the core bundle forwarding logic from `dtn7/src/core/processing.rs`.
    -   [x] Implement the central `bundle_processor` task/actor.
    -   [x] Handle bundle reception, queuing, and forwarding decisions.
    -   [x] Implement duplicate detection.
    -   [x] Implement status report generation.
    -   [x] Implement bundle expiration handling.
    -   [x] Implement proper constraint management.

-   [x] **2.3: Bundle Storage**: Implement a storage backend for bundles-in-flight.
    -   [x] **In-Memory Store**: First, port the in-memory store from `dtn7/src/core/store/mem.rs`. This is the simplest and good for initial testing.
    -   [x] **Persistent Store**: Plan for and implement a persistent store called `CSQLiteStore` and implement `BundleStore` protocol. Use a Swift and C interop with a local library `CSQLite` 

-   [x] **2.4: Application Agent Interface**: Port the interface for local applications to connect to the daemon (`dtn7/src/core/application_agent.rs`).
    -   [x] Define a clear API for applications to register endpoints, send bundles, and receive bundles.

---

## Phase 3: Convergence Layers (CLAs)

This phase involves porting the various network protocols that carry bundles. They should be designed to be pluggable.

-   [x] **3.1: CLA Abstraction**: Define a `ConvergenceLayer` protocol (similar to a Rust trait) that all CLAs will conform to. This ensures a modular design.

-   [x] **3.2: Port TCP Convergence Layer**: Port `dtn7/src/cla/tcp/`.
    -   [x] Use Apple's Network.framework for the TCP connection logic.
    -   [x] Implement the connection management and bundle transmission/reception logic from `net.rs` and `proto.rs`.
    -   [x] Implement full TCPCLv4 protocol support.

-   [x] **3.3: Port Other CLAs**: Incrementally port the other convergence layers.
    -   [ ] **MTCP**: `cla/mtcp.rs`
    -   [x] **UDP**: `cla/udp.rs`
    -   [x] **HTTP**: `cla/http.rs` (implemented with URLSession).
    -   [x] **HTTP Pull**: `cla/httppull.rs`

---

## Phase 4: Routing Algorithms

Similar to CLAs, routing algorithms should be modular and swappable.

-   [x] **4.1: Routing Abstraction**: Define a `RoutingAlgorithm` protocol that all router implementations will conform to. It will likely need methods to get routes for a bundle, notify of new peers, etc.

-   [x] **4.2: Port Routing Logic**: Port the existing routing algorithms from `dtn7/src/routing/`.
    -   [x] **Static Routing**: `static_routing.rs`
    -   [x] **Flooding**: `flooding.rs`
    -   [x] **Epidemic**: `epidemic.rs`
    -   [x] **Spray and Wait**: `sprayandwait.rs`
    -   [x] **Sink Router**: `sink.rs` (for testing)

---

## Phase 5: Interfaces and Tooling

This phase focuses on the user-facing parts of the system: the command-line tools and management interfaces.

-   [x] **5.1: Command-Line Tools**: Create executables for the helper tools using `swift-argument-parser`.
    -   [x] `dtnquery`
    -   [x] `dtnrecv`
    -   [x] `dtnsend`
    -   [x] `dtntrigger`

-   [ ] **5.2: HTTP Management Interface**: Port the web server from `dtn7/src/dtnd/httpd.rs`.
    -   [ ] Use `Hummingbird` to create the REST API endpoints.
    -   [ ] Re-create the status pages (`webroot/`).

-   [ ] **5.3: WebSocket API**: Port the WebSocket interface from `dtn7/src/dtnd/ws.rs` for rich client interactions. This will use the `HummingbirdWebSocket` extension.

---

## Phase 6: Testing and Validation

Testing is crucial and should be done throughout the process, but this phase focuses on comprehensive integration testing.

-   [ ] **6.1: Unit Tests**: Write `Swift Testing` (NOT XCTest) unit tests for each ported component (data structures, routing logic, CLA parsers, etc.).

-   [ ] **6.2: Integration Tests**: Re-create the scenarios from the `dtn7-rs/tests/` directory.
    -   [ ] Write Swift scripts or use shell scripts to set up local nodes and test interactions.
    -   [ ] Test scenarios like `local_ping_echo.sh`.

-   [ ] **6.3: Documentation**:
    -   [ ] Add Swift-DocC comments to the public API.
    -   [ ] Create a "Getting Started" guide similar to the one in `dtn7-rs/doc/`.

---

## Phase 7: Packaging and Release

Prepare the Swift package for public consumption.

-   [ ] **7.1: Swift Package Manager**: Finalize the `Package.swift` manifest, ensuring all products and targets are correctly defined.
-   [ ] **7.2: Platform Support**: Test the library on all target platforms (`macOS`, `iOS`, etc.).
-   [ ] **7.3: Release Workflow**: Establish a process for versioning and publishing new releases. 