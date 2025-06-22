#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import BP7
import AsyncAlgorithms

/// Commands that can be sent to a routing agent
public enum RoutingCommand: Sendable {
    case requestNextHop(bundle: BP7.Bundle)
    case notifyBundleDelivered(bundleId: String)
    case notifyBundleForwarded(bundleId: String, to: DtnPeer)
    case notifyPeerEncountered(peer: DtnPeer)
    case notifyPeerLost(peer: DtnPeer)
    case updateConfig([String: String])
    case getRoutingTable
}

/// Response from routing agent for next hop queries
public struct RoutingDecision: Sendable {
    public let bundleId: String
    public let nextHops: [DtnPeer]
    public let isLocalDelivery: Bool
    
    public init(bundleId: String, nextHops: [DtnPeer] = [], isLocalDelivery: Bool = false) {
        self.bundleId = bundleId
        self.nextHops = nextHops
        self.isLocalDelivery = isLocalDelivery
    }
}

/// Protocol for all routing algorithms
public protocol RoutingAgent: Sendable {
    /// Name of the routing algorithm
    var algorithmName: String { get }
    
    /// Configure the routing agent with required dependencies
    func configure(peerManager: PeerManager, core: DtnCore) async
    
    /// Start the routing agent
    func start() async throws
    
    /// Stop the routing agent
    func stop() async throws
    
    /// Get next hops for a bundle
    func getNextHops(for bundle: BP7.Bundle) async -> RoutingDecision
    
    /// Handle routing notifications
    func handleNotification(_ notification: RoutingCommand) async
    
    /// Get current routing state (for monitoring)
    func getState() async -> [String: String]
}

/// Base implementation for routing agents
public actor BaseRoutingAgent {
    public let algorithmName: String
    private var peers: Set<DtnPeer> = []
    private var isRunning = false
    private weak var peerManager: PeerManager?
    private weak var core: DtnCore?
    
    public init(algorithmName: String) {
        self.algorithmName = algorithmName
    }
    
    public func configure(peerManager: PeerManager, core: DtnCore) async {
        self.peerManager = peerManager
        self.core = core
    }
    
    public func start() async throws {
        isRunning = true
    }
    
    public func stop() async throws {
        isRunning = false
    }
    
    public func addPeer(_ peer: DtnPeer) {
        peers.insert(peer)
    }
    
    public func removePeer(_ peer: DtnPeer) {
        peers.remove(peer)
    }
    
    public func getAllPeers() -> Set<DtnPeer> {
        peers
    }
}