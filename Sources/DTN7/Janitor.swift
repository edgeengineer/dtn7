import Foundation
import BP7
import Logging

/// Janitor task that periodically cleans up expired bundles and processes peers
public actor Janitor {
    private let logger = Logger(label: "dtnd.janitor")
    private let interval: TimeInterval
    private weak var core: DtnCore?
    private var task: Task<Void, Never>?
    
    public init(interval: TimeInterval = 10.0) {
        self.interval = interval
    }
    
    /// Set the DtnCore reference
    public func setCore(_ core: DtnCore) {
        self.core = core
    }
    
    /// Start the janitor task
    public func start() {
        guard task == nil else {
            logger.warning("Janitor already running")
            return
        }
        
        task = Task {
            logger.info("Starting janitor task with interval: \(interval)s")
            
            while !Task.isCancelled {
                do {
                    // Wait for the interval
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    
                    // Run janitor tasks
                    await run()
                } catch {
                    // Task was cancelled
                    break
                }
            }
            
            logger.info("Janitor task stopped")
        }
    }
    
    /// Stop the janitor task
    public func stop() {
        task?.cancel()
        task = nil
    }
    
    /// Run janitor tasks
    private func run() async {
        logger.debug("Running janitor")
        
        // Clean up expired bundles
        await deleteExpiredBundles()
        
        // Process peers (clean up failed connections, etc.)
        await processPeers()
        
        // Reprocess bundles for forwarding
        await processBundles()
    }
    
    /// Delete expired bundles from the store
    private func deleteExpiredBundles() async {
        guard let core = core else { 
            logger.warning("No core reference, skipping bundle cleanup")
            return 
        }
        
        logger.info("Starting bundle expiration check")
        
        let allBundleIds = await core.store.allIds()
        logger.info("Found \(allBundleIds.count) bundle(s) in store")
        
        var expiredCount = 0
        let currentTime = DisruptionTolerantNetworkingTime.now()
        
        for bundleId in allBundleIds {
            if let bundle = await core.store.getBundle(bundleId: bundleId) {
                let creationTime = bundle.primary.creationTimestamp.getDtnTime()
                let age = TimeInterval(currentTime - creationTime) / 1000.0
                
                logger.info("Bundle \(bundleId): lifetime=\(bundle.primary.lifetime)s, age=\(age)s, expired=\(isExpired(bundle))")
                
                if isExpired(bundle) {
                    logger.info("Bundle \(bundleId) has expired, removing from store")
                    do {
                        try await core.store.remove(bundleId: bundleId)
                        expiredCount += 1
                        logger.info("Successfully removed expired bundle \(bundleId)")
                    } catch {
                        logger.error("Failed to remove expired bundle \(bundleId): \(error)")
                    }
                } else {
                    logger.debug("Bundle \(bundleId) is still valid")
                }
            } else {
                logger.warning("Could not retrieve bundle \(bundleId) from store")
            }
        }
        
        logger.info("Bundle cleanup complete: removed \(expiredCount) expired bundle(s)")
    }
    
    /// Check if a bundle has expired based on its lifetime
    private func isExpired(_ bundle: BP7.Bundle) -> Bool {
        // If lifetime is 0, bundle never expires
        guard bundle.primary.lifetime > 0 else {
            return false
        }
        
        // Check primary block lifetime
        let creationTime = bundle.primary.creationTimestamp.getDtnTime()
        let currentTime = DisruptionTolerantNetworkingTime.now()
        let age = TimeInterval(currentTime - creationTime) / 1000.0 // Convert ms to seconds
        
        if age >= bundle.primary.lifetime {
            logger.debug("Bundle expired: age=\(age)s >= lifetime=\(bundle.primary.lifetime)s")
            return true
        }
        
        // TODO: Check bundle age block if present
        // Currently the BP7 library doesn't expose public access to CanonicalBlock.data
        // This would require updating the BP7 library
        
        return false
    }
    
    /// Process peers - clean up failed connections
    private func processPeers() async {
        guard let core = core else { return }
        
        logger.debug("Processing peers")
        
        // Clean up peers that have failed too many times
        let peers = await core.peerManager.getAllPeers()
        for peer in peers {
            if peer.conType == .dynamic && peer.fails > 3 {
                logger.info("Removing dynamic peer \(peer.eid) due to too many failures (\(peer.fails))")
                await core.peerManager.removePeer(peer.eid)
            }
        }
    }
    
    /// Reprocess bundles for forwarding
    private func processBundles() async {
        guard let core = core else { return }
        
        logger.debug("Reprocessing bundles")
        
        // Get all bundle IDs
        let bundleIds = await core.store.allIds()
        
        // Check if any CLAs are accepting connections
        let hasActiveCLA = await core.claRegistry.hasActiveCLA()
        guard hasActiveCLA else {
            logger.debug("No active CLA, skipping bundle forwarding")
            return
        }
        
        // Process bundles that need forwarding
        for bundleId in bundleIds {
            if let bundle = await core.store.getBundle(bundleId: bundleId) {
                // Skip if bundle is for local delivery
                if await core.isLocalEndpoint(bundle.primary.destination) {
                    continue
                }
                
                // Skip if bundle has expired
                if isExpired(bundle) {
                    continue
                }
                
                // Try to forward the bundle
                // Get routing decision and send to peers
                let decision = await core.getRoutingDecision(for: bundle)
                if !decision.nextHops.isEmpty && !decision.isLocalDelivery {
                    await core.sendBundle(bundle, to: decision.nextHops)
                }
            }
        }
    }
}