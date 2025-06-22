#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import BP7
import Logging

/// Flooding routing algorithm - simplest routing that sends all bundles to all peers repeatedly
public actor FloodingRouting: RoutingAgent {
    public let algorithmName = "flooding"
    
    private let logger = Logger(label: "FloodingRouting")
    
    // Reference to peer manager
    private weak var peerManager: PeerManager?
    
    // Reference to core for local endpoint checks
    private weak var core: DtnCore?
    
    // Statistics
    private var totalRoutingDecisions = 0
    private var totalPeersReturned = 0
    
    public init() {}
    
    /// Set required references
    public func configure(peerManager: PeerManager, core: DtnCore) async {
        self.peerManager = peerManager
        self.core = core
    }
    
    public func start() async throws {
        logger.info("Flooding routing agent started")
    }
    
    public func stop() async throws {
        logger.info("Flooding routing agent stopped")
    }
    
    public func getNextHops(for bundle: BP7.Bundle) async -> RoutingDecision {
        let bundleId = BundlePack(from: bundle).id
        let destination = bundle.primary.destination
        
        guard let peerManager = peerManager,
              let core = core else {
            logger.error("Missing required references")
            return RoutingDecision(bundleId: bundleId)
        }
        
        totalRoutingDecisions += 1
        
        // Check if this is for local delivery
        if await core.isLocalEndpoint(destination) {
            logger.debug("Bundle \(bundleId) is for local delivery")
            return RoutingDecision(bundleId: bundleId, nextHops: [], isLocalDelivery: true)
        }
        
        // Get all current peers
        let allPeers = await peerManager.getAllPeers()
        
        // Filter peers that have CLAs available
        let peersWithCLAs = allPeers.filter { !$0.claList.isEmpty }
        
        totalPeersReturned += peersWithCLAs.count
        
        if peersWithCLAs.isEmpty {
            logger.debug("No peers with CLAs available for bundle \(bundleId)")
        } else {
            logger.info("Flooding bundle \(bundleId) to \(peersWithCLAs.count) peers")
        }
        
        // Always forward to all available peers (no history tracking)
        return RoutingDecision(bundleId: bundleId, nextHops: peersWithCLAs)
    }
    
    public func handleNotification(_ notification: RoutingCommand) async {
        // Flooding routing ignores all notifications - it always forwards to everyone
        switch notification {
        case .notifyPeerEncountered(let peer):
            logger.trace("Peer encountered: \(peer.eid) (ignored)")
            
        case .notifyPeerLost(let peer):
            logger.trace("Peer lost: \(peer.eid) (ignored)")
            
        default:
            logger.trace("Received notification: \(notification) (ignored)")
        }
    }
    
    public func getState() async -> [String: String] {
        let avgPeersPerDecision = totalRoutingDecisions > 0 
            ? Double(totalPeersReturned) / Double(totalRoutingDecisions) 
            : 0.0
            
        return [
            "algorithm": algorithmName,
            "total_routing_decisions": "\(totalRoutingDecisions)",
            "total_peers_returned": "\(totalPeersReturned)",
            "average_peers_per_decision": String(format: "%.2f", avgPeersPerDecision)
        ]
    }
}