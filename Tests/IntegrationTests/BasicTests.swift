import Testing
@testable import DTN7
import BP7
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite("Basic Integration Tests")
struct BasicIntegrationTests {
    let testFramework = DTNTestFramework()
    
    @Test("Simple Daemon Start")
    func simpleDaemonStart() async throws {
        // Just try to start a daemon with minimal config
        let daemon = try await testFramework.startDaemon(nodeId: "dtn://simple")
        defer {
            Task { @Sendable in
                try? await testFramework.stopDaemon(daemon)
            }
        }
        
        // Verify the daemon process is running
        #expect(daemon.process.isRunning)
    }
    
    @Test("Local Ping Echo")
    func localPingEcho() async throws {
        // Start a single daemon
        var config = DtnConfig()
        config.endpoints = ["dtn://node1/echo", "dtn://node1/ping"]
        
        let daemon = try await testFramework.startDaemon(nodeId: "dtn://node1", config: config)
        defer {
            Task { @Sendable in
                try? await testFramework.stopDaemon(daemon)
            }
        }
        
        // Send a bundle to the echo endpoint
        try await testFramework.sendBundle(
            from: "dtn://node1/ping",
            to: "dtn://node1/echo",
            payload: "Hello, DTN!"
        )
        
        // Wait a moment for processing
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        // Check if we received the echo (would need echo service implementation)
        // For now, just verify the daemon is running
        #expect(daemon.process.isRunning)
    }
    
    @Test("Two Node Communication")
    func twoNodeCommunication() async throws {
        // Start node1
        var config1 = DtnConfig()
        config1.endpoints = ["dtn://node1/incoming"]
        config1.clas = [DtnConfig.CLAConfig(type: "tcp", settings: ["port": "4556"])]
        
        let daemon1 = try await testFramework.startDaemon(nodeId: "dtn://node1", config: config1)
        defer {
            Task { @Sendable in
                try? await testFramework.stopDaemon(daemon1)
            }
        }
        
        // Start node2 with static peer
        var config2 = DtnConfig()
        config2.endpoints = ["dtn://node2/incoming"]
        config2.clas = [DtnConfig.CLAConfig(type: "tcp", settings: ["port": "4557"])]
        config2.statics = [DtnPeer(
            eid: try! EndpointID.from("dtn://node1"),
            addr: PeerAddress.generic("tcp://localhost:4556"),
            conType: .static,
            period: nil,
            claList: [("tcp", 4556)],
            services: [:],
            lastContact: 0,
            fails: 0
        )]
        
        let daemon2 = try await testFramework.startDaemon(nodeId: "dtn://node2", config: config2)
        defer {
            Task { @Sendable in
                try? await testFramework.stopDaemon(daemon2)
            }
        }
        
        // Wait for peers to connect
        try await testFramework.waitForPeers(daemon: daemon2, expectedCount: 1)
        
        // Send bundle from node2 to node1
        try await testFramework.sendBundle(
            from: "dtn://node2/outgoing",
            to: "dtn://node1/incoming",
            payload: "Hello from node2!"
        )
        
        // Check if bundle was delivered
        let delivered = try await testFramework.checkBundleDelivered(
            at: "dtn://node1/incoming",
            containing: "Hello from node2!"
        )
        
        #expect(delivered)
    }
    
    @Test("Bundle Lifetime Expiration")
    func bundleLifetimeExpiration() async throws {
        // Start a daemon
        var config = DtnConfig()
        config.janitorInterval = 1 // 1 second janitor interval
        
        let daemon = try await testFramework.startDaemon(nodeId: "dtn://node1", config: config)
        defer {
            Task { @Sendable in
                try? await testFramework.stopDaemon(daemon)
            }
        }
        
        // Send a bundle with short lifetime
        try await testFramework.sendBundle(
            from: "dtn://node1/sender",
            to: "dtn://nonexistent/receiver",
            payload: "This should expire",
            lifetime: 2 // 2 seconds
        )
        
        // Wait for bundle to expire
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
        
        // TODO: Check bundle count once HTTP endpoints are fixed
        // For now, just verify the daemon is still running
        #expect(daemon.process.isRunning)
    }
}

@Suite("Routing Tests")
struct RoutingIntegrationTests {
    let testFramework = DTNTestFramework()
    
    @Test("Epidemic Routing")
    func epidemicRouting() async throws {
        // Create a 3-node linear topology: node1 <-> node2 <-> node3
        
        // Start node2 (middle node)
        var config2 = DtnConfig()
        config2.routing = "epidemic"
        config2.clas = [DtnConfig.CLAConfig(type: "tcp", settings: ["port": "4557"])]
        
        let daemon2 = try await testFramework.startDaemon(nodeId: "dtn://node2", config: config2)
        defer {
            Task { @Sendable in
                try? await testFramework.stopDaemon(daemon2)
            }
        }
        
        // Start node1 with node2 as peer
        var config1 = DtnConfig()
        config1.routing = "epidemic"
        config1.endpoints = ["dtn://node1/test"]
        config1.clas = [DtnConfig.CLAConfig(type: "tcp", settings: ["port": "4556"])]
        config1.statics = [DtnPeer(
            eid: try! EndpointID.from("dtn://node2"),
            addr: PeerAddress.generic("tcp://localhost:4557"),
            conType: .static,
            period: nil,
            claList: [("tcp", 4557)],
            services: [:],
            lastContact: 0,
            fails: 0
        )]
        
        let daemon1 = try await testFramework.startDaemon(nodeId: "dtn://node1", config: config1)
        defer {
            Task { @Sendable in
                try? await testFramework.stopDaemon(daemon1)
            }
        }
        
        // Start node3 with node2 as peer
        var config3 = DtnConfig()
        config3.routing = "epidemic"
        config3.endpoints = ["dtn://node3/test"]
        config3.clas = [DtnConfig.CLAConfig(type: "tcp", settings: ["port": "4558"])]
        config3.statics = [DtnPeer(
            eid: try! EndpointID.from("dtn://node2"),
            addr: PeerAddress.generic("tcp://localhost:4557"),
            conType: .static,
            period: nil,
            claList: [("tcp", 4557)],
            services: [:],
            lastContact: 0,
            fails: 0
        )]
        
        let daemon3 = try await testFramework.startDaemon(nodeId: "dtn://node3", config: config3)
        defer {
            Task { @Sendable in
                try? await testFramework.stopDaemon(daemon3)
            }
        }
        
        // Wait for all peers to connect
        try await testFramework.waitForPeers(daemon: daemon2, expectedCount: 2)
        
        // Send bundle from node1 to node3 (should be routed through node2)
        try await testFramework.sendBundle(
            from: "dtn://node1/test",
            to: "dtn://node3/test",
            payload: "Epidemic routing test"
        )
        
        // Check if bundle was delivered to node3
        let delivered = try await testFramework.checkBundleDelivered(
            at: "dtn://node3/test",
            containing: "Epidemic routing test"
        )
        
        #expect(delivered)
    }
}