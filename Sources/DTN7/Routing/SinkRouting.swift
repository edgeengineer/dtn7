#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import BP7
import Logging

/// Sink routing algorithm - never forwards bundles (acts as a data sink)
/// Useful for testing and for nodes that should only be endpoints
public actor SinkRouting: RoutingAgent {
    public let algorithmName = "sink"
    
    private let logger = Logger(label: "SinkRouting")
    
    // Statistics
    private var totalBundlesProcessed = 0
    private var localDeliveries = 0
    
    // Reference to core for local endpoint checks
    private weak var core: DtnCore?
    
    public init() {}
    
    /// Set required references
    public func configure(peerManager: PeerManager, core: DtnCore) async {
        // Sink doesn't need peer manager since it never forwards
        self.core = core
    }
    
    public func start() async throws {
        logger.info("Sink routing agent started - no bundles will be forwarded")
    }
    
    public func stop() async throws {
        logger.info("Sink routing agent stopped")
    }
    
    public func getNextHops(for bundle: BP7.Bundle) async -> RoutingDecision {
        let bundleId = BundlePack(from: bundle).id
        let destination = bundle.primary.destination
        
        totalBundlesProcessed += 1
        
        // Check if this is for local delivery
        if let core = core, await core.isLocalEndpoint(destination) {
            logger.debug("Bundle \(bundleId) is for local delivery")
            localDeliveries += 1
            return RoutingDecision(bundleId: bundleId, nextHops: [], isLocalDelivery: true)
        }
        
        // Sink router never forwards bundles
        logger.trace("Sink router dropping bundle \(bundleId) - no forwarding")
        return RoutingDecision(bundleId: bundleId, nextHops: [])
    }
    
    public func handleNotification(_ notification: RoutingCommand) async {
        // Sink router ignores all notifications
        switch notification {
        case .notifyPeerEncountered(let peer):
            logger.trace("Peer encountered: \(peer.eid) (ignored by sink)")
            
        case .notifyPeerLost(let peer):
            logger.trace("Peer lost: \(peer.eid) (ignored by sink)")
            
        default:
            logger.trace("Received notification: \(notification) (ignored by sink)")
        }
    }
    
    public func getState() async -> [String: String] {
        return [
            "algorithm": algorithmName,
            "total_bundles_processed": "\(totalBundlesProcessed)",
            "local_deliveries": "\(localDeliveries)",
            "bundles_dropped": "\(totalBundlesProcessed - localDeliveries)"
        ]
    }
}