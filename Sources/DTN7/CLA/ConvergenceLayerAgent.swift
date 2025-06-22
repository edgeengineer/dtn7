#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import BP7
import AsyncAlgorithms

/// Protocol defining the interface for all Convergence Layer Agents
public protocol ConvergenceLayerAgent: Sendable {
    /// Unique identifier for this CLA instance
    var id: String { get }
    
    /// Human-readable name for this CLA type
    var name: String { get }
    
    /// Start the CLA and begin listening for connections
    func start() async throws
    
    /// Stop the CLA and close all connections
    func stop() async throws
    
    /// Send a bundle through this CLA to a specific peer
    func sendBundle(_ bundle: BP7.Bundle, to peer: DtnPeer) async throws
    
    /// Channel for receiving bundles from this CLA
    var incomingBundles: AsyncChannel<(BP7.Bundle, CLAConnection)> { get }
    
    /// Check if this CLA can reach a specific peer
    func canReach(_ peer: DtnPeer) -> Bool
    
    /// Get all active connections
    func getConnections() async -> [CLAConnection]
}

/// Represents a connection through a CLA
public struct CLAConnection: Sendable, Equatable {
    public let id: String
    public let remoteEndpointId: EndpointID?
    public let remoteAddress: String
    public let claType: String
    public let establishedAt: Date
    
    public init(id: String, remoteEndpointId: EndpointID?, remoteAddress: String, claType: String, establishedAt: Date = Date()) {
        self.id = id
        self.remoteEndpointId = remoteEndpointId
        self.remoteAddress = remoteAddress
        self.claType = claType
        self.establishedAt = establishedAt
    }
}

/// Registry for managing multiple CLAs
public actor CLARegistry {
    private var clas: [String: any ConvergenceLayerAgent] = [:]
    
    /// Register a new CLA
    public func register(_ cla: any ConvergenceLayerAgent) async throws {
        clas[cla.id] = cla
        try await cla.start()
    }
    
    /// Unregister a CLA
    public func unregister(_ claId: String) async throws {
        if let cla = clas[claId] {
            try await cla.stop()
            clas.removeValue(forKey: claId)
        }
    }
    
    /// Get all registered CLAs
    public func getAllCLAs() -> [any ConvergenceLayerAgent] {
        Array(clas.values)
    }
    
    /// Find CLAs that can reach a specific peer
    public func findCLAsForPeer(_ peer: DtnPeer) -> [any ConvergenceLayerAgent] {
        clas.values.filter { $0.canReach(peer) }
    }
    
    /// Stop all CLAs
    public func stopAll() async throws {
        for cla in clas.values {
            try await cla.stop()
        }
        clas.removeAll()
    }
    
    /// Check if any CLAs are active/accepting connections
    public func hasActiveCLA() -> Bool {
        return !clas.isEmpty
    }
}