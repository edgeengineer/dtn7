import Foundation
import BP7
import CBOR
import AsyncAlgorithms
import Logging

/// HTTP-based implementation of the ApplicationInterface for simpler use cases
public actor HTTPApplicationInterface: ApplicationInterface {
    private let logger = Logger(label: "HTTPApplicationInterface")
    
    // Connection details
    private let baseURL: URL
    private let session: URLSession
    
    // Registered endpoints
    private var registeredEndpoints: Set<String> = []
    
    // Polling for bundles
    private var pollingTask: Task<Void, Never>?
    private let pollingInterval: TimeInterval
    
    // Incoming bundles channel
    public let incomingBundles = AsyncChannel<ReceivedBundle>()
    
    public init(host: String = "localhost", port: Int = 3000, pollingInterval: TimeInterval = 1.0) {
        self.baseURL = URL(string: "http://\(host):\(port)")!
        self.session = URLSession.shared
        self.pollingInterval = pollingInterval
    }
    
    deinit {
        pollingTask?.cancel()
    }
    
    // MARK: - ApplicationInterface
    
    public var isConnected: Bool {
        // HTTP is connectionless, so we're always "connected"
        return true
    }
    
    public func connect() async throws {
        // Start polling for registered endpoints
        startPolling()
        logger.info("HTTP application interface initialized")
    }
    
    public func disconnect() async {
        pollingTask?.cancel()
        pollingTask = nil
        registeredEndpoints.removeAll()
        logger.info("HTTP application interface stopped")
    }
    
    public func registerEndpoint(_ endpoint: String) async throws {
        // Validate endpoint
        guard let _ = try? EndpointID.from(endpoint) else {
            throw ApplicationInterfaceError.invalidEndpoint(endpoint)
        }
        
        // Register via HTTP API
        let url = baseURL.appendingPathComponent("register")
            .appending(queryItems: [URLQueryItem(name: "endpoint", value: endpoint)])
        
        do {
            let (_, response) = try await session.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    registeredEndpoints.insert(endpoint)
                    logger.info("Registered endpoint: \(endpoint)")
                } else {
                    throw ApplicationInterfaceError.protocolError("Registration failed with status: \(httpResponse.statusCode)")
                }
            }
        } catch {
            logger.error("Failed to register endpoint: \(error)")
            throw ApplicationInterfaceError.connectionFailed(error.localizedDescription)
        }
    }
    
    public func unregisterEndpoint(_ endpoint: String) async throws {
        // Unregister via HTTP API
        let url = baseURL.appendingPathComponent("unregister")
            .appending(queryItems: [URLQueryItem(name: "endpoint", value: endpoint)])
        
        do {
            let (_, response) = try await session.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    registeredEndpoints.remove(endpoint)
                    logger.info("Unregistered endpoint: \(endpoint)")
                } else {
                    throw ApplicationInterfaceError.protocolError("Unregistration failed with status: \(httpResponse.statusCode)")
                }
            }
        } catch {
            logger.error("Failed to unregister endpoint: \(error)")
            throw ApplicationInterfaceError.connectionFailed(error.localizedDescription)
        }
    }
    
    public func sendBundle(from source: String, to destination: String, payload: Data, lifetime: TimeInterval, deliveryNotification: Bool) async throws {
        // Send bundle via HTTP POST
        let url = baseURL.appendingPathComponent("send")
            .appending(queryItems: [
                URLQueryItem(name: "src", value: source),
                URLQueryItem(name: "dst", value: destination),
                URLQueryItem(name: "lifetime", value: String(Int(lifetime * 1000))),
                URLQueryItem(name: "delivery_notification", value: String(deliveryNotification))
            ])
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        do {
            let (_, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                    logger.debug("Sent bundle from \(source) to \(destination)")
                } else {
                    throw ApplicationInterfaceError.protocolError("Send failed with status: \(httpResponse.statusCode)")
                }
            }
        } catch {
            logger.error("Failed to send bundle: \(error)")
            throw ApplicationInterfaceError.connectionFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Private Methods
    
    private func startPolling() {
        pollingTask?.cancel()
        
        pollingTask = Task {
            while !Task.isCancelled {
                // Poll each registered endpoint
                for endpoint in registeredEndpoints {
                    await pollEndpoint(endpoint)
                }
                
                // Wait before next poll
                try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            }
        }
    }
    
    private func pollEndpoint(_ endpoint: String) async {
        let url = baseURL.appendingPathComponent("endpoint")
            .appending(queryItems: [URLQueryItem(name: "endpoint", value: endpoint)])
        
        do {
            let (data, response) = try await session.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               !data.isEmpty {
                
                // Check if it's a "Nothing to receive" response
                if let text = String(data: data, encoding: .utf8),
                   text == "Nothing to receive" {
                    return
                }
                
                // Try to decode as bundle
                do {
                    let bundle = try BP7.Bundle.decode(from: Array(data))
                    let receivedBundle = ReceivedBundle(from: bundle)
                    await incomingBundles.send(receivedBundle)
                    logger.debug("Received bundle \(receivedBundle.bundleId) for endpoint \(endpoint)")
                } catch {
                    logger.warning("Failed to decode bundle from endpoint poll: \(error)")
                }
            }
        } catch {
            // Silently ignore polling errors to avoid log spam
            logger.trace("Polling error for \(endpoint): \(error)")
        }
    }
}

// MARK: - URL Extension

extension URL {
    func appending(queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        components.queryItems = (components.queryItems ?? []) + queryItems
        return components.url!
    }
}