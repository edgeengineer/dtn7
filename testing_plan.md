# Swift DTN7 Testing Infrastructure Plan

Based on analysis of the Rust dtn7-rs testing infrastructure, this document outlines how to adapt the testing approach for our Swift implementation.

## Overview

Rather than directly copying the Rust test files, we'll adapt the testing strategy to be idiomatic for Swift while maintaining the same comprehensive coverage.

## Test Infrastructure Components

### 1. Unit Tests (Swift Testing Framework)

Create unit tests in `Tests/DTN7Tests/` for:
- Protocol implementations (TCPCL, MTCP, HTTP CLAs)
- Bundle processing logic
- Routing algorithms
- Configuration parsing
- Service discovery

### 2. Integration Tests

Create `Tests/IntegrationTests/` with:
- Multi-node scenarios using Process API
- Network topology tests
- Store-and-forward scenarios
- Bundle lifetime and expiration tests
- Peer discovery and management

### 3. Test Utilities

Port `libshelltests.sh` functionality to Swift:
```swift
// Tests/Utilities/TestFramework.swift
public class DTNTestFramework {
    func startDaemon(config: DtnConfig) async throws -> DTNDaemon
    func waitForPeers(daemon: DTNDaemon, count: Int) async throws
    func sendBundle(from: String, to: String, payload: Data) async throws
    func checkBundleDelivered(at: String, bundleId: String) async throws -> Bool
}
```

### 4. Docker Integration

Keep the existing Docker infrastructure from Rust:
- Copy `dockerfiles/` directory for container builds
- Adapt Docker Compose files for Swift binaries
- Use for system-level integration testing

### 5. Test Scenarios to Port

Priority scenarios from Rust tests:
1. **local_ping_echo** - Basic connectivity
2. **routing_epidemic** - Epidemic routing behavior
3. **lifetime_tests** - Bundle expiration
4. **store_and_forward** - Offline bundle handling
5. **discovery_tests** - Peer discovery
6. **mtcp_reconnect** - Connection resilience

## Implementation Steps

### Phase 1: Basic Test Infrastructure
1. Set up Swift Testing framework in Package.swift
2. Create TestFramework utilities
3. Port simple unit tests for existing components

### Phase 2: Integration Test Framework
1. Create process management utilities
2. Implement test daemon lifecycle management
3. Port first integration test (local_ping_echo)

### Phase 3: Docker Integration
1. Create Dockerfile for Swift dtnd
2. Adapt docker-compose files
3. Create GitHub Actions workflow for Docker tests

### Phase 4: Advanced Testing
1. Port network topology tests
2. Implement performance benchmarks
3. Consider fuzzing with libFuzzer or AFL++

## Directory Structure

```
dtn7/
├── Tests/
│   ├── DTN7Tests/           # Unit tests
│   │   ├── CLATests/
│   │   ├── RoutingTests/
│   │   └── CoreTests/
│   ├── IntegrationTests/    # Multi-node tests
│   │   ├── BasicTests.swift
│   │   ├── RoutingTests.swift
│   │   └── LifetimeTests.swift
│   └── Utilities/
│       └── TestFramework.swift
├── docker/
│   ├── Dockerfile
│   └── compose/
│       ├── 3-node-linear.yml
│       └── epidemic-test.yml
└── scripts/
    └── run_tests.sh
```

## Key Differences from Rust

1. **Swift Testing vs cargo test**: Use Swift's new testing framework with async support
2. **Process management**: Use Process API instead of shell scripts where possible
3. **Network simulation**: May need to adapt or replace clab scenarios
4. **Fuzzing**: Different toolchain, but same targets (protocol parsing)

## Benefits of This Approach

1. **Maintains test coverage**: Same scenarios, Swift-idiomatic implementation
2. **Reuses Docker infrastructure**: System tests remain portable
3. **Progressive implementation**: Can build tests alongside features
4. **CI/CD ready**: Works with GitHub Actions and other CI systems

## Next Steps

1. Update porting_plan.md Phase 6 with this testing approach
2. Create basic test infrastructure on feat/tests branch
3. Port one simple integration test as proof of concept
4. Set up GitHub Actions workflow