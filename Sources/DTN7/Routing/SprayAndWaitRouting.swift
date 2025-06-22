#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import BP7
import Logging

/// Bundle metadata for Spray and Wait routing
struct SprayAndWaitBundleData: Sendable {
    var remainingCopies: Int
    var nodesWithCopy: Set<String>
}

/// Spray and Wait routing algorithm - efficient DTN routing with limited copies
/// For each bundle, only L copies are spread, after which we enter wait phase
/// In wait phase, only direct delivery is possible
public actor SprayAndWaitRouting: RoutingAgent {
    public let algorithmName = "sprayandwait"
    
    private let logger = Logger(label: "SprayAndWaitRouting")
    
    // Configuration
    private let maxCopies: Int
    
    // Bundle tracking: bundleId -> metadata
    private var bundleHistory: [String: SprayAndWaitBundleData] = [:]
    
    // Reference to peer manager
    private weak var peerManager: PeerManager?
    
    // Reference to core for local endpoint checks
    private weak var core: DtnCore?
    
    // Statistics
    private var totalBundlesProcessed = 0
    private var bundlesInSprayPhase = 0
    private var bundlesInWaitPhase = 0
    private var directDeliveries = 0
    
    /// Default number of copies
    private static let defaultMaxCopies = 7
    
    public init(maxCopies: Int? = nil) {
        self.maxCopies = maxCopies ?? Self.defaultMaxCopies
    }
    
    /// Set required references
    public func configure(peerManager: PeerManager, core: DtnCore) async {
        self.peerManager = peerManager
        self.core = core
    }
    
    public func start() async throws {
        logger.info("Spray and Wait routing agent started with max copies: \(maxCopies)")
    }
    
    public func stop() async throws {
        logger.info("Spray and Wait routing agent stopped")
        bundleHistory.removeAll()
    }
    
    public func getNextHops(for bundle: BP7.Bundle) async -> RoutingDecision {
        let bundleId = BundlePack(from: bundle).id
        let destination = bundle.primary.destination
        
        guard let peerManager = peerManager,
              let core = core else {
            logger.error("Missing required references")
            return RoutingDecision(bundleId: bundleId)
        }
        
        totalBundlesProcessed += 1
        
        // Check if this is for local delivery
        if await core.isLocalEndpoint(destination) {
            logger.debug("Bundle \(bundleId) is for local delivery")
            return RoutingDecision(bundleId: bundleId, nextHops: [], isLocalDelivery: true)
        }
        
        // Initialize bundle metadata if this is a new bundle
        if bundleHistory[bundleId] == nil {
            await initializeBundleMetadata(bundleId: bundleId, source: bundle.primary.source)
        }
        
        guard var metadata = bundleHistory[bundleId] else {
            logger.error("Failed to initialize metadata for bundle \(bundleId)")
            return RoutingDecision(bundleId: bundleId)
        }
        
        // Get all current peers
        let allPeers = await peerManager.getAllPeers()
        
        // Check if we're in wait phase (only 1 copy left)
        if metadata.remainingCopies < 2 {
            bundlesInWaitPhase += 1
            
            // In wait phase - only direct delivery
            if let destinationPeer = allPeers.first(where: { $0.eid == destination }) {
                logger.info("Direct delivery possible for bundle \(bundleId) to \(destination)")
                directDeliveries += 1
                
                // Mark as sent and use last copy
                metadata.nodesWithCopy.insert(destination.description)
                metadata.remainingCopies = 0
                bundleHistory[bundleId] = metadata
                
                return RoutingDecision(bundleId: bundleId, nextHops: [destinationPeer])
            } else {
                logger.debug("Bundle \(bundleId) in wait phase, no direct delivery possible")
                return RoutingDecision(bundleId: bundleId)
            }
        }
        
        // We're in spray phase - distribute copies
        bundlesInSprayPhase += 1
        var candidatePeers: [DtnPeer] = []
        
        for peer in allPeers {
            let peerName = peer.eid.description
            
            // Skip if we already sent to this peer
            if metadata.nodesWithCopy.contains(peerName) {
                continue
            }
            
            // Skip if peer has no CLAs
            if peer.claList.isEmpty {
                continue
            }
            
            // Skip if we've run out of copies
            if metadata.remainingCopies <= 0 {
                break
            }
            
            candidatePeers.append(peer)
            
            // Binary spray: give half of remaining copies to the peer
            let copiesToGive = max(1, metadata.remainingCopies / 2)
            metadata.remainingCopies -= copiesToGive
            metadata.nodesWithCopy.insert(peerName)
            
            logger.debug("Spraying bundle \(bundleId) to \(peerName), giving \(copiesToGive) copies, \(metadata.remainingCopies) remaining")
        }
        
        // Update metadata
        bundleHistory[bundleId] = metadata
        
        if candidatePeers.isEmpty {
            logger.debug("No new peers to spray bundle \(bundleId) to")
        } else {
            logger.info("Spraying bundle \(bundleId) to \(candidatePeers.count) peers")
        }
        
        return RoutingDecision(bundleId: bundleId, nextHops: candidatePeers)
    }
    
    public func handleNotification(_ notification: RoutingCommand) async {
        switch notification {
        case .notifyBundleForwarded(let bundleId, let peer):
            logger.trace("Bundle \(bundleId) forwarded to \(peer.eid)")
            // Already tracked in getNextHops
            
        case .notifyPeerEncountered(let peer):
            logger.info("New peer encountered: \(peer.eid)")
            // Spray and Wait will consider new peers in next routing decision
            
        case .notifyPeerLost(let peer):
            logger.info("Peer lost: \(peer.eid)")
            // For failed transmissions, we could restore copies, but keeping it simple
            
        case .requestNextHop(let bundle):
            logger.trace("Received requestNextHop for bundle \(BundlePack(from: bundle).id)")
            
        default:
            break
        }
    }
    
    public func getState() async -> [String: String] {
        let avgCopiesPerBundle = bundleHistory.isEmpty ? 0.0 :
            Double(bundleHistory.values.reduce(0) { $0 + $1.remainingCopies }) / Double(bundleHistory.count)
        
        return [
            "algorithm": algorithmName,
            "max_copies": "\(maxCopies)",
            "total_bundles_processed": "\(totalBundlesProcessed)",
            "bundles_tracked": "\(bundleHistory.count)",
            "bundles_in_spray_phase": "\(bundlesInSprayPhase)",
            "bundles_in_wait_phase": "\(bundlesInWaitPhase)",
            "direct_deliveries": "\(directDeliveries)",
            "avg_remaining_copies": String(format: "%.2f", avgCopiesPerBundle)
        ]
    }
    
    // MARK: - Helper Methods
    
    /// Initialize metadata for a new bundle
    private func initializeBundleMetadata(bundleId: String, source: EndpointID) async {
        guard let core = core else { return }
        
        let isOwnBundle = await core.isLocalEndpoint(source)
        
        let metadata = SprayAndWaitBundleData(
            remainingCopies: isOwnBundle ? maxCopies : 1,  // Own bundles get L copies, received bundles get 1
            nodesWithCopy: []
        )
        
        bundleHistory[bundleId] = metadata
        
        logger.debug("Initialized bundle \(bundleId) with \(metadata.remainingCopies) copies (own bundle: \(isOwnBundle))")
    }
    
    /// Clean up old history entries (could be called periodically)
    public func cleanupHistory(olderThan: TimeInterval) {
        let maxHistorySize = 10000
        
        if bundleHistory.count > maxHistorySize {
            // Remove bundles with no remaining copies
            bundleHistory = bundleHistory.filter { $0.value.remainingCopies > 0 }
            
            // If still too large, remove oldest entries (simplified)
            if bundleHistory.count > maxHistorySize {
                let toRemove = bundleHistory.count - maxHistorySize
                for key in bundleHistory.keys.prefix(toRemove) {
                    bundleHistory.removeValue(forKey: key)
                }
            }
        }
    }
}