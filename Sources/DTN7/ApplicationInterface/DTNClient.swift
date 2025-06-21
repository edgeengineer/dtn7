import Foundation
import BP7
import AsyncAlgorithms
import Logging

/// High-level client for DTN applications
public class DTNClient: @unchecked Sendable {
    private let logger = Logger(label: "DTNClient")
    
    // Application interface (WebSocket or HTTP)
    private let interface: any ApplicationInterface
    
    // Client configuration
    private let nodeId: String
    private let applicationName: String
    
    // Bundle handlers
    private var bundleHandlers: [String: (ReceivedBundle) async -> Void] = [:]
    private let handlerQueue = DispatchQueue(label: "dtn.client.handlers")
    
    // Background task for processing incoming bundles
    private var processingTask: Task<Void, Never>?
    
    /// Initialize a DTN client
    /// - Parameters:
    ///   - nodeId: The node ID (e.g., "dtn://node1")
    ///   - applicationName: The application name for endpoints
    ///   - useWebSocket: Whether to use WebSocket (true) or HTTP polling (false)
    ///   - host: The DTN daemon host
    ///   - port: The DTN daemon port
    public init(
        nodeId: String,
        applicationName: String,
        useWebSocket: Bool = true,
        host: String = "localhost",
        port: Int = 3000
    ) {
        self.nodeId = nodeId
        self.applicationName = applicationName
        
        if useWebSocket {
            self.interface = WebSocketApplicationInterface(host: host, port: port)
        } else {
            self.interface = HTTPApplicationInterface(host: host, port: port)
        }
    }
    
    deinit {
        processingTask?.cancel()
    }
    
    /// Connect to the DTN daemon
    public func connect() async throws {
        try await interface.connect()
        startProcessingBundles()
        logger.info("DTN client connected for application: \(applicationName)")
    }
    
    /// Disconnect from the DTN daemon
    public func disconnect() async {
        processingTask?.cancel()
        processingTask = nil
        await interface.disconnect()
        logger.info("DTN client disconnected")
    }
    
    /// Register a service endpoint
    /// - Parameters:
    ///   - service: The service name (e.g., "echo", "ping")
    ///   - handler: Callback for handling received bundles
    public func registerService(_ service: String, handler: @escaping (ReceivedBundle) async -> Void) async throws {
        let endpoint = "\(nodeId)/\(service)"
        
        try await interface.registerEndpoint(endpoint)
        
        handlerQueue.sync {
            bundleHandlers[endpoint] = handler
        }
        
        logger.info("Registered service: \(service) at endpoint: \(endpoint)")
    }
    
    /// Register a group endpoint
    /// - Parameters:
    ///   - group: The group name (e.g., "~news", "~chat")
    ///   - handler: Callback for handling received bundles
    public func registerGroup(_ group: String, handler: @escaping (ReceivedBundle) async -> Void) async throws {
        let endpoint = "dtn://global/\(group)"
        
        try await interface.registerEndpoint(endpoint)
        
        handlerQueue.sync {
            bundleHandlers[endpoint] = handler
        }
        
        logger.info("Registered group: \(group) at endpoint: \(endpoint)")
    }
    
    /// Unregister a service endpoint
    public func unregisterService(_ service: String) async throws {
        let endpoint = "\(nodeId)/\(service)"
        
        try await interface.unregisterEndpoint(endpoint)
        
        handlerQueue.sync {
            bundleHandlers.removeValue(forKey: endpoint)
        }
        
        logger.info("Unregistered service: \(service)")
    }
    
    /// Send a bundle to a destination
    /// - Parameters:
    ///   - destination: The destination endpoint (e.g., "dtn://node2/echo")
    ///   - payload: The bundle payload
    ///   - lifetime: Bundle lifetime in seconds (default: 3600)
    ///   - deliveryNotification: Request delivery notification (default: false)
    ///   - source: Optional source endpoint (defaults to nodeId/applicationName)
    public func sendBundle(
        to destination: String,
        payload: Data,
        lifetime: TimeInterval = 3600,
        deliveryNotification: Bool = false,
        from source: String? = nil
    ) async throws {
        let sourceEndpoint = source ?? "\(nodeId)/\(applicationName)"
        
        try await interface.sendBundle(
            from: sourceEndpoint,
            to: destination,
            payload: payload,
            lifetime: lifetime,
            deliveryNotification: deliveryNotification
        )
        
        logger.debug("Sent bundle from \(sourceEndpoint) to \(destination), size: \(payload.count) bytes")
    }
    
    /// Send a text message as a bundle
    public func sendText(
        to destination: String,
        message: String,
        lifetime: TimeInterval = 3600,
        deliveryNotification: Bool = false
    ) async throws {
        guard let data = message.data(using: .utf8) else {
            throw ApplicationInterfaceError.serializationError("Failed to encode text message")
        }
        
        try await sendBundle(
            to: destination,
            payload: data,
            lifetime: lifetime,
            deliveryNotification: deliveryNotification
        )
    }
    
    /// Send a JSON-encodable object as a bundle
    public func sendJSON<T: Encodable>(
        to destination: String,
        object: T,
        lifetime: TimeInterval = 3600,
        deliveryNotification: Bool = false
    ) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(object)
        
        try await sendBundle(
            to: destination,
            payload: data,
            lifetime: lifetime,
            deliveryNotification: deliveryNotification
        )
    }
    
    // MARK: - Private Methods
    
    private func startProcessingBundles() {
        processingTask = Task {
            for await bundle in interface.incomingBundles {
                await handleReceivedBundle(bundle)
            }
        }
    }
    
    private func handleReceivedBundle(_ bundle: ReceivedBundle) async {
        logger.debug("Processing received bundle: \(bundle.bundleId)")
        
        // Find matching handler
        let handler = handlerQueue.sync { () -> ((ReceivedBundle) async -> Void)? in
            // Try exact match first
            if let handler = bundleHandlers[bundle.destination] {
                return handler
            }
            
            // Try pattern matching for group endpoints
            for (endpoint, handler) in bundleHandlers {
                if matchesEndpoint(bundle.destination, pattern: endpoint) {
                    return handler
                }
            }
            
            return nil
        }
        
        if let handler = handler {
            await handler(bundle)
        } else {
            logger.warning("No handler registered for bundle to: \(bundle.destination)")
        }
    }
    
    private func matchesEndpoint(_ endpoint: String, pattern: String) -> Bool {
        // Simple pattern matching for group endpoints
        if pattern.contains("/~") && endpoint.contains("/~") {
            let patternParts = pattern.split(separator: "/")
            let endpointParts = endpoint.split(separator: "/")
            
            if patternParts.count >= 3 && endpointParts.count >= 3 {
                // Match node and group parts
                return patternParts[0] == endpointParts[0] &&
                       patternParts[1] == endpointParts[1] &&
                       patternParts[2] == endpointParts[2]
            }
        }
        
        return endpoint == pattern
    }
}

// MARK: - Convenience Extensions

extension ReceivedBundle {
    /// Get the payload as a UTF-8 string
    public var text: String? {
        String(data: payload, encoding: .utf8)
    }
    
    /// Decode the payload as JSON
    public func decodeJSON<T: Decodable>(_ type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        return try decoder.decode(type, from: payload)
    }
}