import Foundation
import BP7
import Logging

/// Epidemic routing algorithm - controlled flooding where each bundle is sent exactly once to each peer
public actor EpidemicRouting: RoutingAgent {
    public let algorithmName = "epidemic"
    
    private let logger = Logger(label: "EpidemicRouting")
    
    // Bundle forwarding history: bundleId -> Set of node names that have received it
    private var forwardingHistory: [String: Set<String>] = [:]
    
    // Track which peer sent us each bundle to avoid loops
    private var incomingBundleSource: [String: String] = [:]
    
    // Reference to peer manager
    private weak var peerManager: PeerManager?
    
    // Reference to core for local endpoint checks
    private weak var core: DtnCore?
    
    public init() {}
    
    /// Set required references
    public func configure(peerManager: PeerManager, core: DtnCore) async {
        self.peerManager = peerManager
        self.core = core
    }
    
    public func start() async throws {
        logger.info("Epidemic routing agent started")
    }
    
    public func stop() async throws {
        logger.info("Epidemic routing agent stopped")
        forwardingHistory.removeAll()
        incomingBundleSource.removeAll()
    }
    
    public func getNextHops(for bundle: BP7.Bundle) async -> RoutingDecision {
        let bundleId = BundlePack(from: bundle).id
        let destination = bundle.primary.destination
        
        guard let peerManager = peerManager,
              let core = core else {
            logger.error("Missing required references")
            return RoutingDecision(bundleId: bundleId)
        }
        
        // Check if this is for local delivery
        if await core.isLocalEndpoint(destination) {
            logger.debug("Bundle \(bundleId) is for local delivery")
            return RoutingDecision(bundleId: bundleId, nextHops: [], isLocalDelivery: true)
        }
        
        // Get all current peers
        let allPeers = await peerManager.getAllPeers()
        
        // Check if destination is a direct peer (optimization)
        if let destinationPeer = allPeers.first(where: { $0.eid == destination }) {
            logger.info("Direct delivery possible for bundle \(bundleId) to \(destination)")
            // Mark this peer as having received the bundle
            markBundleSent(bundleId: bundleId, to: destination.description)
            return RoutingDecision(bundleId: bundleId, nextHops: [destinationPeer])
        }
        
        // Build list of peers that haven't received this bundle yet
        var candidatePeers: [DtnPeer] = []
        let bundleHistory = forwardingHistory[bundleId] ?? Set<String>()
        
        for peer in allPeers {
            let peerName = peer.eid.description
            
            // Skip if we already sent to this peer
            if bundleHistory.contains(peerName) {
                logger.trace("Skipping peer \(peerName) - already sent bundle \(bundleId)")
                continue
            }
            
            // Skip if this peer sent us the bundle (avoid loops)
            if let source = incomingBundleSource[bundleId], source == peerName {
                logger.trace("Skipping peer \(peerName) - they sent us bundle \(bundleId)")
                continue
            }
            
            // Skip if peer has no CLAs
            if peer.claList.isEmpty {
                logger.trace("Skipping peer \(peerName) - no CLAs available")
                continue
            }
            
            candidatePeers.append(peer)
            // Mark as sent (optimistically - will be removed if sending fails)
            markBundleSent(bundleId: bundleId, to: peerName)
        }
        
        if candidatePeers.isEmpty {
            logger.debug("No new peers to forward bundle \(bundleId) to")
        } else {
            logger.info("Forwarding bundle \(bundleId) to \(candidatePeers.count) peers: \(candidatePeers.map { $0.eid.description }.joined(separator: ", "))")
        }
        
        return RoutingDecision(bundleId: bundleId, nextHops: candidatePeers)
    }
    
    public func handleNotification(_ notification: RoutingCommand) async {
        switch notification {
        case .notifyBundleDelivered(let bundleId):
            logger.debug("Bundle \(bundleId) delivered")
            // Could clean up history for delivered bundles
            
        case .notifyBundleForwarded(let bundleId, let peer):
            logger.debug("Bundle \(bundleId) forwarded to \(peer.eid)")
            // Already tracked in getNextHops
            
        case .notifyPeerEncountered(let peer):
            logger.info("New peer encountered: \(peer.eid)")
            // Epidemic routing will automatically consider new peers
            
        case .notifyPeerLost(let peer):
            logger.info("Peer lost: \(peer.eid)")
            // Remove peer from all forwarding histories to allow retransmission
            removePeerFromHistory(peer.eid.description)
            
        case .requestNextHop(let bundle):
            // This is handled by getNextHops
            logger.trace("Received requestNextHop for bundle \(BundlePack(from: bundle).id)")
            
        default:
            break
        }
    }
    
    public func getState() async -> [String: String] {
        return [
            "algorithm": algorithmName,
            "forwarding_history_size": "\(forwardingHistory.count)",
            "total_forwards": "\(forwardingHistory.values.reduce(0) { $0 + $1.count })",
            "tracked_bundles": "\(forwardingHistory.count) bundles"
        ]
    }
    
    // MARK: - Helper Methods
    
    /// Mark a bundle as sent to a specific peer
    private func markBundleSent(bundleId: String, to peer: String) {
        if forwardingHistory[bundleId] == nil {
            forwardingHistory[bundleId] = Set<String>()
        }
        forwardingHistory[bundleId]!.insert(peer)
    }
    
    /// Remove a peer from all forwarding histories (e.g., when peer is lost)
    private func removePeerFromHistory(_ peer: String) {
        for bundleId in forwardingHistory.keys {
            forwardingHistory[bundleId]?.remove(peer)
        }
        
        // Also remove from incoming bundle sources
        incomingBundleSource = incomingBundleSource.filter { $0.value != peer }
    }
    
    /// Record which peer sent us a bundle (for loop prevention)
    public func recordIncomingBundle(_ bundleId: String, from peer: String) {
        incomingBundleSource[bundleId] = peer
    }
    
    /// Clean up old history entries (could be called periodically)
    public func cleanupHistory(olderThan: TimeInterval) {
        // In a production system, we'd track timestamps and remove old entries
        // For now, simple size limit
        let maxHistorySize = 10000
        
        if forwardingHistory.count > maxHistorySize {
            // Remove oldest entries (simplified - in production use LRU)
            let toRemove = forwardingHistory.count - maxHistorySize
            for key in forwardingHistory.keys.prefix(toRemove) {
                forwardingHistory.removeValue(forKey: key)
                incomingBundleSource.removeValue(forKey: key)
            }
        }
    }
}