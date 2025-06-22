#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import BP7
import Logging
import CBOR

/// Errors that can occur during bundle processing
public enum BundleProcessorError: Error, Sendable {
    case noCoreReference
    case invalidSource
    case bundleExpired
    case duplicateBundle
    case bundleDeleted
    case invalidAdministrativeRecord
    case noLocalEndpoint
}

/// An actor responsible for processing bundles with complete pipeline support
public actor BundleProcessor {
    private let config: DtnConfig
    private var logger: Logger
    private var core: DtnCore?
    
    // Duplicate detection
    private var seenBundles: Set<String> = []
    private let maxSeenBundles = 10000
    
    // Bundle state tracking
    private var bundleConstraints: [String: Constraints] = [:]

    public init(config: DtnConfig) {
        self.config = config
        self.logger = Logger(label: "BundleProcessor")
    }
    
    /// Set the DtnCore reference
    public func setCore(_ core: DtnCore) {
        self.core = core
    }

    /// Handles a new incoming bundle.
    public func receive(bundle: BP7.Bundle) async throws {
        let bundlePack = BundlePack(from: bundle)
        let bundleId = bundlePack.id
        logger.info("Received new bundle: \(bundleId)")
        
        guard let core = core else {
            throw BundleProcessorError.noCoreReference
        }
        
        // 1. Check for duplicates
        if seenBundles.contains(bundleId) {
            logger.debug("Duplicate bundle detected: \(bundleId)")
            await core.updateStatistics { stats in
                stats.recordDuplicate()
            }
            throw BundleProcessorError.duplicateBundle
        }
        
        // Add to seen bundles (with size limit)
        seenBundles.insert(bundleId)
        if seenBundles.count > maxSeenBundles {
            // Remove oldest entries (simplified - in production use LRU cache)
            seenBundles.removeFirst()
        }
        
        // 2. Check bundle expiration
        if isBundleExpired(bundle) {
            logger.warning("Received expired bundle: \(bundleId)")
            
            // Generate deletion status report if requested
            if shouldSendStatusReport(bundle, for: .bundleStatusRequestDeletion) {
                try await sendStatusReport(
                    for: bundle,
                    status: .deletedBundle,
                    reason: .lifetimeExpired
                )
            }
            
            throw BundleProcessorError.bundleExpired
        }
        
        // 3. Store bundle
        try await core.store.push(bundle: bundle)
        await core.updateStatistics { stats in
            stats.recordIncoming()
        }
        
        // 4. Initialize constraints
        var constraints = Constraints()
        bundleConstraints[bundleId] = constraints
        
        // 5. Send reception status report if requested
        if shouldSendStatusReport(bundle, for: .bundleStatusRequestReception) {
            try await sendStatusReport(
                for: bundle,
                status: .receivedBundle,
                reason: .noInformation
            )
        }
        
        // 6. Handle administrative records
        if bundle.primary.bundleControlFlags.contains(.bundleAdministrativeRecordPayload) {
            try await handleAdministrativeRecord(bundle)
            return // Don't forward administrative records
        }
        
        // 7. Validate unknown block types
        for block in bundle.canonicals {
            if !isKnownBlockType(block.blockType) {
                let flags = block.blockControlFlags
                
                if flags.contains(.blockDeleteBundle) {
                    logger.warning("Unknown block type \(block.blockType) with delete bundle flag")
                    
                    // Send deletion status report if requested
                    if shouldSendStatusReport(bundle, for: .bundleStatusRequestDeletion) {
                        try await sendStatusReport(
                            for: bundle,
                            status: .deletedBundle,
                            reason: .blockUnintelligible
                        )
                    }
                    
                    // Mark bundle as deleted
                    constraints.insert(.deleted)
                    bundleConstraints[bundleId] = constraints
                    try await core.store.remove(bundleId: bundleId)
                    throw BundleProcessorError.bundleDeleted
                    
                } else if flags.contains(.blockStatusReport) {
                    // Send status report for unprocessable block
                    if !bundle.primary.reportTo.isNone() {
                        try await sendStatusReport(
                            for: bundle,
                            status: .receivedBundle,
                            reason: .blockUnintelligible
                        )
                    }
                }
                
                if flags.contains(.blockRemove) {
                    // Remove the block (in a real implementation)
                    logger.info("Should remove unknown block type \(block.blockType)")
                }
            }
        }
        
        // 8. Set dispatch pending
        constraints.insert(.dispatchPending)
        bundleConstraints[bundleId] = constraints
        
        // 9. Dispatch the bundle
        try await dispatch(bundle: bundle, bundleId: bundleId)
    }
    
    /// Starts the transmission of an outbound bundle.
    public func transmit(bundle: BP7.Bundle) async throws {
        let bundlePack = BundlePack(from: bundle)
        let bundleId = bundlePack.id
        logger.info("Transmission of bundle requested: \(bundleId)")
        
        guard let core = core else {
            throw BundleProcessorError.noCoreReference
        }
        
        // 1. Validate source
        if await !core.isLocalEndpoint(bundle.primary.source) {
            logger.error("Bundle source is not a local endpoint: \(bundle.primary.source)")
            throw BundleProcessorError.invalidSource
        }
        
        // 2. Check expiration
        if isBundleExpired(bundle) {
            logger.warning("Attempting to transmit expired bundle: \(bundleId)")
            throw BundleProcessorError.bundleExpired
        }
        
        // 3. Store bundle
        try await core.store.push(bundle: bundle)
        
        // 4. Initialize constraints with dispatch pending
        var constraints = Constraints()
        constraints.insert(.dispatchPending)
        bundleConstraints[bundleId] = constraints
        
        // 5. Dispatch the bundle
        try await dispatch(bundle: bundle, bundleId: bundleId)
    }

    /// Dispatches a bundle to local delivery or forwarding.
    private func dispatch(bundle: BP7.Bundle, bundleId: String) async throws {
        logger.info("Dispatching bundle: \(bundleId)")
        
        guard let core = core else {
            throw BundleProcessorError.noCoreReference
        }
        
        // Remove dispatch pending constraint
        if var constraints = bundleConstraints[bundleId] {
            constraints.remove(.dispatchPending)
            bundleConstraints[bundleId] = constraints
        }
        
        // Get routing decision
        let decision = await core.getRoutingDecision(for: bundle)
        
        if decision.isLocalDelivery {
            try await localDelivery(bundle: bundle, bundleId: bundleId)
        } else if !decision.nextHops.isEmpty {
            // Set forward pending constraint
            if var constraints = bundleConstraints[bundleId] {
                constraints.insert(.forwardPending)
                bundleConstraints[bundleId] = constraints
            }
            
            try await forward(bundle: bundle, bundleId: bundleId, to: decision.nextHops)
        } else {
            logger.warning("No route found for bundle: \(bundleId)")
            
            // Send status report if no route
            if shouldSendStatusReport(bundle, for: .bundleStatusRequestDeletion) &&
               !bundle.primary.destination.isNone() {
                try await sendStatusReport(
                    for: bundle,
                    status: .deletedBundle,
                    reason: .noRouteToDestination
                )
            }
            
            await core.updateStatistics { stats in
                stats.recordFailed()
            }
        }
    }
    
    /// Forwards a bundle to the next hop.
    private func forward(bundle: BP7.Bundle, bundleId: String, to peers: [DtnPeer]) async throws {
        logger.info("Forwarding bundle: \(bundleId) to \(peers.count) peers")
        
        guard let core = core else {
            throw BundleProcessorError.noCoreReference
        }
        
        // Check bundle lifetime
        if isBundleExpired(bundle) {
            logger.warning("Bundle expired during forwarding: \(bundleId)")
            
            // Send deletion status report if requested
            if shouldSendStatusReport(bundle, for: .bundleStatusRequestDeletion) {
                try await sendStatusReport(
                    for: bundle,
                    status: .deletedBundle,
                    reason: .lifetimeExpired
                )
            }
            
            // Mark bundle as deleted
            if var constraints = bundleConstraints[bundleId] {
                constraints.insert(.deleted)
                bundleConstraints[bundleId] = constraints
            }
            
            throw BundleProcessorError.bundleExpired
        }
        
        // Send to peers
        await core.sendBundle(bundle, to: peers)
        
        // Remove forward pending constraint
        if var constraints = bundleConstraints[bundleId] {
            constraints.remove(.forwardPending)
            bundleConstraints[bundleId] = constraints
        }
        
        // Send forwarding status report if requested
        if shouldSendStatusReport(bundle, for: .bundleStatusRequestForward) {
            try await sendStatusReport(
                for: bundle,
                status: .forwardedBundle,
                reason: .noInformation
            )
        }
        
        await core.updateStatistics { stats in
            stats.recordOutgoing()
        }
    }
    
    /// Delivers a bundle to a local application.
    private func localDelivery(bundle: BP7.Bundle, bundleId: String) async throws {
        logger.info("Delivering bundle locally: \(bundleId)")
        
        guard let core = core else {
            throw BundleProcessorError.noCoreReference
        }
        
        // Check if destination is actually local
        if await !core.isLocalEndpoint(bundle.primary.destination) {
            logger.error("Attempted local delivery for non-local endpoint: \(bundle.primary.destination)")
            throw BundleProcessorError.noLocalEndpoint
        }
        
        // Deliver bundle to application agent
        let delivered = await core.applicationAgent.deliverBundle(bundle)
        
        if delivered {
            logger.info("Bundle \(bundleId) delivered to application agent for \(bundle.primary.destination)")
        } else {
            logger.warning("Bundle \(bundleId) could not be delivered - no registered application for \(bundle.primary.destination)")
        }
        
        await core.updateStatistics { stats in
            stats.recordDelivered()
        }
        
        // Send delivery status report if requested
        if shouldSendStatusReport(bundle, for: .bundleStatusRequestDelivery) {
            try await sendStatusReport(
                for: bundle,
                status: .deliveredBundle,
                reason: .noInformation
            )
        }
        
        // Mark bundle as delivered (can be deleted by janitor)
        if var constraints = bundleConstraints[bundleId] {
            constraints.insert(.deleted)
            bundleConstraints[bundleId] = constraints
        }
    }
    
    /// Handle administrative records
    private func handleAdministrativeRecord(_ bundle: BP7.Bundle) async throws {
        guard let payload = bundle.payload() else {
            logger.warning("Administrative record bundle has no payload")
            throw BundleProcessorError.invalidAdministrativeRecord
        }
        
        do {
            let adminRecord = try AdministrativeRecord.decode(from: CBOR.decode(payload))
            
            switch adminRecord {
            case .bundleStatusReport(let statusReport):
                logger.info("Received status report for bundle: \(statusReport.refBundle())")
                // Process status report (e.g., update routing tables, notify applications)
                
            case .unknown(let code, _):
                logger.warning("Received unknown administrative record type: \(code)")
                
            case .mismatched(let code, _):
                logger.warning("Received mismatched administrative record type: \(code)")
            }
            
        } catch {
            logger.error("Failed to decode administrative record: \(error)")
            throw BundleProcessorError.invalidAdministrativeRecord
        }
    }
    
    /// Check if a bundle has expired
    private func isBundleExpired(_ bundle: BP7.Bundle) -> Bool {
        let now = Date()
        let dtnTime = bundle.primary.creationTimestamp.getDtnTime()
        // DTN time is milliseconds since 2000-01-01, need to convert to Unix time
        let unixTimeMs = dtnTime + 946_684_800_000 // Add milliseconds from 1970 to 2000
        let creationTime = Date(timeIntervalSince1970: Double(unixTimeMs) / 1000.0)
        let expiryTime = creationTime.addingTimeInterval(bundle.primary.lifetime)
        
        logger.debug("Bundle expiry check: dtnTime=\(dtnTime)ms, unixTime=\(unixTimeMs)ms, creationTime=\(creationTime), lifetime=\(bundle.primary.lifetime)s, expiryTime=\(expiryTime), now=\(now), expired=\(now > expiryTime)")
        
        return now > expiryTime
    }
    
    /// Check if a status report should be sent
    private func shouldSendStatusReport(_ bundle: BP7.Bundle, for flag: BundleControlFlags) -> Bool {
        return bundle.primary.bundleControlFlags.contains(flag) &&
               !bundle.primary.reportTo.isNone() &&
               config.generateStatusReports
    }
    
    /// Send a status report
    private func sendStatusReport(
        for bundle: BP7.Bundle,
        status: StatusInformationPos,
        reason: StatusReportReason
    ) async throws {
        guard let core = core else {
            throw BundleProcessorError.noCoreReference
        }
        
        // Create status report bundle
        let reportBundle = StatusReport.newBundle(
            origBundle: bundle,
            source: core.nodeId,
            crcType: .crc32(0),
            status: status,
            reason: reason
        )
        
        logger.debug("Sending status report for bundle \(BundlePack(from: bundle).id): \(status)")
        
        // Transmit the status report
        try await transmit(bundle: reportBundle)
    }
    
    /// Check if a block type is known
    private func isKnownBlockType(_ blockType: UInt64) -> Bool {
        // Known block types from BP7 spec
        let knownTypes: Set<UInt64> = [
            1,  // Payload
            2,  // Previous Node
            6,  // Bundle Age
            7,  // Hop Count
        ]
        return knownTypes.contains(blockType)
    }
    
    /// Get current constraints for a bundle
    public func getConstraints(for bundleId: String) -> Constraints? {
        return bundleConstraints[bundleId]
    }
    
    /// Update constraints for a bundle
    public func updateConstraints(for bundleId: String, _ update: (inout Constraints) -> Void) {
        if var constraints = bundleConstraints[bundleId] {
            update(&constraints)
            bundleConstraints[bundleId] = constraints
        }
    }
    
    /// Clean up old bundle tracking data
    public func cleanup() async {
        // Remove constraints for deleted bundles
        let deletedBundles = bundleConstraints.compactMap { (bundleId, constraints) in
            constraints.contains(.deleted) ? bundleId : nil
        }
        
        for bundleId in deletedBundles {
            bundleConstraints.removeValue(forKey: bundleId)
        }
        
        logger.debug("Cleaned up \(deletedBundles.count) deleted bundle constraints")
    }
}