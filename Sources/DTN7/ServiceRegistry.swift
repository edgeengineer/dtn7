#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import BP7

/// Represents a service that can be registered on an endpoint
public struct DtnService: Sendable {
    public let tag: UInt8
    public let endpoint: EndpointID
    public let description: String
    
    public init(tag: UInt8, endpoint: EndpointID, description: String) {
        self.tag = tag
        self.endpoint = endpoint
        self.description = description
    }
}

/// Registry for managing services and their endpoints
public actor ServiceRegistry {
    private var services: [UInt8: DtnService] = [:]
    private var endpointServices: [EndpointID: Set<UInt8>] = [:]
    
    /// Register a new service
    public func register(_ service: DtnService) {
        services[service.tag] = service
        
        if endpointServices[service.endpoint] == nil {
            endpointServices[service.endpoint] = []
        }
        endpointServices[service.endpoint]?.insert(service.tag)
    }
    
    /// Unregister a service by tag
    public func unregister(tag: UInt8) {
        if let service = services[tag] {
            services.removeValue(forKey: tag)
            endpointServices[service.endpoint]?.remove(tag)
            
            if endpointServices[service.endpoint]?.isEmpty == true {
                endpointServices.removeValue(forKey: service.endpoint)
            }
        }
    }
    
    /// Get service by tag
    public func getService(tag: UInt8) -> DtnService? {
        services[tag]
    }
    
    /// Get all services for an endpoint
    public func getServices(for endpoint: EndpointID) -> [DtnService] {
        guard let tags = endpointServices[endpoint] else { return [] }
        return tags.compactMap { services[$0] }
    }
    
    /// Get all registered services
    public func getAllServices() -> [DtnService] {
        Array(services.values)
    }
    
    /// Check if a service tag is registered
    public func isRegistered(tag: UInt8) -> Bool {
        services[tag] != nil
    }
}