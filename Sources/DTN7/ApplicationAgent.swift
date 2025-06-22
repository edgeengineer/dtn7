#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import BP7
import AsyncAlgorithms
import Logging

/// Represents a registered application endpoint
public struct ApplicationEndpoint: Sendable {
    public let endpoint: EndpointID
    public let registeredAt: Date
    
    public init(endpoint: EndpointID) {
        self.endpoint = endpoint
        self.registeredAt = Date()
    }
}

/// Protocol for application agents to receive bundles
public protocol ApplicationAgentDelegate: Sendable {
    /// Called when a bundle is received for this application
    func bundleReceived(_ bundle: BP7.Bundle) async
}

/// Manages application registrations and bundle delivery
public actor ApplicationAgent {
    private let logger = Logger(label: "ApplicationAgent")
    
    // Registered endpoints and their delivery channels
    private var registeredEndpoints: [EndpointID: ApplicationEndpoint] = [:]
    private var deliveryChannels: [EndpointID: AsyncChannel<BP7.Bundle>] = [:]
    
    // Optional delegates for direct delivery
    private var delegates: [EndpointID: any ApplicationAgentDelegate] = [:]
    
    // Queue for bundles awaiting delivery
    private var pendingBundles: [EndpointID: [BP7.Bundle]] = [:]
    
    public init() {}
    
    /// Register an application endpoint
    public func registerEndpoint(_ endpoint: EndpointID) -> AsyncChannel<BP7.Bundle> {
        logger.info("Registering application endpoint: \(endpoint)")
        
        registeredEndpoints[endpoint] = ApplicationEndpoint(endpoint: endpoint)
        
        // Create delivery channel if it doesn't exist
        if deliveryChannels[endpoint] == nil {
            deliveryChannels[endpoint] = AsyncChannel<BP7.Bundle>()
        }
        
        // Deliver any pending bundles
        if let pending = pendingBundles[endpoint] {
            let channel = deliveryChannels[endpoint]!
            Task {
                for bundle in pending {
                    await channel.send(bundle)
                }
            }
            pendingBundles.removeValue(forKey: endpoint)
        }
        
        return deliveryChannels[endpoint]!
    }
    
    /// Register an application endpoint with a delegate
    public func registerEndpoint(_ endpoint: EndpointID, delegate: any ApplicationAgentDelegate) {
        logger.info("Registering application endpoint with delegate: \(endpoint)")
        
        registeredEndpoints[endpoint] = ApplicationEndpoint(endpoint: endpoint)
        delegates[endpoint] = delegate
        
        // Deliver any pending bundles
        if let pending = pendingBundles[endpoint] {
            Task {
                for bundle in pending {
                    await delegate.bundleReceived(bundle)
                }
            }
            pendingBundles.removeValue(forKey: endpoint)
        }
    }
    
    /// Unregister an application endpoint
    public func unregisterEndpoint(_ endpoint: EndpointID) {
        logger.info("Unregistering application endpoint: \(endpoint)")
        
        registeredEndpoints.removeValue(forKey: endpoint)
        deliveryChannels[endpoint]?.finish()
        deliveryChannels.removeValue(forKey: endpoint)
        delegates.removeValue(forKey: endpoint)
        pendingBundles.removeValue(forKey: endpoint)
    }
    
    /// Deliver a bundle to the appropriate application
    public func deliverBundle(_ bundle: BP7.Bundle) async -> Bool {
        let destination = bundle.primary.destination
        let bundleId = BundlePack(from: bundle).id
        
        logger.debug("Attempting to deliver bundle \(bundleId) to \(destination)")
        
        // Try exact match first
        if let registration = registeredEndpoints[destination] {
            return await deliverToEndpoint(bundle, to: destination)
        }
        
        // Try pattern matching for group endpoints
        for (registeredEndpoint, _) in registeredEndpoints {
            if matchesEndpoint(destination, pattern: registeredEndpoint) {
                logger.debug("Bundle \(bundleId) matches registered endpoint \(registeredEndpoint)")
                return await deliverToEndpoint(bundle, to: registeredEndpoint)
            }
        }
        
        // No registered endpoint found - queue the bundle
        logger.info("No application registered for endpoint \(destination), queuing bundle \(bundleId)")
        queueBundle(bundle, for: destination)
        return false
    }
    
    /// Get all registered endpoints
    public func getRegisteredEndpoints() -> [ApplicationEndpoint] {
        Array(registeredEndpoints.values)
    }
    
    /// Check if an endpoint is registered
    public func isEndpointRegistered(_ endpoint: EndpointID) -> Bool {
        if registeredEndpoints[endpoint] != nil {
            return true
        }
        
        // Check pattern matching
        for (registeredEndpoint, _) in registeredEndpoints {
            if matchesEndpoint(endpoint, pattern: registeredEndpoint) {
                return true
            }
        }
        
        return false
    }
    
    /// Get pending bundles for an endpoint
    public func getPendingBundles(for endpoint: EndpointID) -> [BP7.Bundle] {
        pendingBundles[endpoint] ?? []
    }
    
    /// Clear pending bundles for an endpoint
    public func clearPendingBundles(for endpoint: EndpointID) {
        pendingBundles.removeValue(forKey: endpoint)
    }
    
    // MARK: - Private Methods
    
    private func deliverToEndpoint(_ bundle: BP7.Bundle, to endpoint: EndpointID) async -> Bool {
        let bundleId = BundlePack(from: bundle).id
        
        // Try delegate delivery first
        if let delegate = delegates[endpoint] {
            logger.info("Delivering bundle \(bundleId) to delegate for \(endpoint)")
            await delegate.bundleReceived(bundle)
            return true
        }
        
        // Try channel delivery
        if let channel = deliveryChannels[endpoint] {
            logger.info("Delivering bundle \(bundleId) to channel for \(endpoint)")
            await channel.send(bundle)
            return true
        }
        
        return false
    }
    
    private func queueBundle(_ bundle: BP7.Bundle, for endpoint: EndpointID) {
        if pendingBundles[endpoint] == nil {
            pendingBundles[endpoint] = []
        }
        pendingBundles[endpoint]!.append(bundle)
        
        // Limit queue size
        let maxQueueSize = 100
        if pendingBundles[endpoint]!.count > maxQueueSize {
            logger.warning("Bundle queue for \(endpoint) exceeded limit, dropping oldest bundle")
            pendingBundles[endpoint]!.removeFirst()
        }
    }
    
    private func matchesEndpoint(_ endpoint: EndpointID, pattern: EndpointID) -> Bool {
        // Simple pattern matching for group endpoints
        // For example: dtn://global/~news matches dtn://global/~news/*
        let endpointStr = endpoint.description
        let patternStr = pattern.description
        
        // Check if pattern ends with /* for wildcard matching
        if patternStr.hasSuffix("/*") {
            let prefix = String(patternStr.dropLast(2))
            return endpointStr.hasPrefix(prefix)
        }
        
        // Check if pattern contains ~ for group endpoints
        if patternStr.contains("/~") && endpointStr.contains("/~") {
            let patternParts = patternStr.split(separator: "/")
            let endpointParts = endpointStr.split(separator: "/")
            
            if patternParts.count >= 2 && endpointParts.count >= 2 {
                // Match node and group parts
                return patternParts[0] == endpointParts[0] && 
                       patternParts[1] == endpointParts[1]
            }
        }
        
        return endpoint == pattern
    }
}

/// Simple bundle delivery info for external APIs
public struct BundleDeliveryInfo: Codable, Sendable {
    public let bundleId: String
    public let source: String
    public let destination: String
    public let creationTimestamp: UInt64
    public let lifetime: TimeInterval
    public let payloadLength: Int
    
    public init(from bundle: BP7.Bundle) {
        let pack = BundlePack(from: bundle)
        self.bundleId = pack.id
        self.source = bundle.primary.source.description
        self.destination = bundle.primary.destination.description
        self.creationTimestamp = bundle.primary.creationTimestamp.getDtnTime()
        self.lifetime = bundle.primary.lifetime
        self.payloadLength = bundle.payload()?.count ?? 0
    }
}