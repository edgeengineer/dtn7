#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import BP7
import CBOR
import AsyncAlgorithms

/// Protocol for applications to interact with the DTN daemon
public protocol ApplicationInterface: Sendable {
    /// Register an endpoint for this application
    func registerEndpoint(_ endpoint: String) async throws
    
    /// Unregister an endpoint
    func unregisterEndpoint(_ endpoint: String) async throws
    
    /// Send a bundle
    func sendBundle(from source: String, to destination: String, payload: Data, lifetime: TimeInterval, deliveryNotification: Bool) async throws
    
    /// Receive bundles for registered endpoints
    var incomingBundles: AsyncChannel<ReceivedBundle> { get }
    
    /// Check if connected
    var isConnected: Bool { get async }
    
    /// Connect to the daemon
    func connect() async throws
    
    /// Disconnect from the daemon
    func disconnect() async
}

/// Represents a bundle received by an application
public struct ReceivedBundle: Sendable {
    public let bundleId: String
    public let source: String
    public let destination: String
    public let creationTimestamp: Date
    public let lifetime: TimeInterval
    public let payload: Data
    
    public init(from bundle: BP7.Bundle) {
        let pack = BundlePack(from: bundle)
        self.bundleId = pack.id
        self.source = bundle.primary.source.description
        self.destination = bundle.primary.destination.description
        self.creationTimestamp = Date(timeIntervalSince1970: Double(bundle.primary.creationTimestamp.getDtnTime()) / 1000.0)
        self.lifetime = bundle.primary.lifetime
        self.payload = bundle.payload().map { Data($0) } ?? Data()
    }
    
    public init(bundleId: String, source: String, destination: String, creationTimestamp: Date, lifetime: TimeInterval, payload: Data) {
        self.bundleId = bundleId
        self.source = source
        self.destination = destination
        self.creationTimestamp = creationTimestamp
        self.lifetime = lifetime
        self.payload = payload
    }
}

/// Bundle send request data
public struct BundleSendRequest: Codable, Sendable {
    public let src: String
    public let dst: String
    public let delivery_notification: Bool
    public let lifetime: UInt64  // milliseconds
    public let data: Data
    
    public init(source: String, destination: String, deliveryNotification: Bool, lifetime: TimeInterval, data: Data) {
        self.src = source
        self.dst = destination
        self.delivery_notification = deliveryNotification
        self.lifetime = UInt64(lifetime * 1000)  // Convert to milliseconds
        self.data = data
    }
}

/// Bundle receive data for WebSocket
struct WsRecvData: Codable, Sendable {
    let bid: String
    let src: String
    let dst: String
    let cts: UInt64
    let lifetime: UInt64
    let data: Data
}

/// Transmission mode for WebSocket connection
public enum TransmissionMode: String, Sendable {
    case data = "/data"      // CBOR data mode
    case json = "/json"      // JSON mode
    case bundle = "/bundle"  // Raw bundle mode
}

/// Errors that can occur in the application interface
public enum ApplicationInterfaceError: Error, Sendable {
    case notConnected
    case invalidEndpoint(String)
    case connectionFailed(String)
    case serializationError(String)
    case protocolError(String)
    case timeout
}