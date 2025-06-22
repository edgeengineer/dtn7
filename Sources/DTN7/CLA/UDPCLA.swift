#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Network
import BP7
import AsyncAlgorithms
import Logging

/// UDP Convergence Layer Agent for simple datagram-based bundle transfer
public actor UDPCLA: ConvergenceLayerAgent {
    public let id: String
    public let name: String = "udp"
    public let incomingBundles = AsyncChannel<(BP7.Bundle, CLAConnection)>()
    
    private let config: UDPCLAConfig
    private var listener: NWListener?
    private let logger = Logger(label: "UDPCLA")
    private var isRunning = false
    
    /// Configuration for UDP CLA
    public struct UDPCLAConfig: Sendable {
        public let port: UInt16
        public let bindAddress: String
        public let maxBundleSize: Int
        
        public init(
            port: UInt16 = 4556,
            bindAddress: String = "0.0.0.0",
            maxBundleSize: Int = 65535
        ) {
            self.port = port
            self.bindAddress = bindAddress
            self.maxBundleSize = min(maxBundleSize, 65535) // UDP limit
        }
    }
    
    public init(config: UDPCLAConfig = UDPCLAConfig()) {
        self.id = "udp-\(config.port)"
        self.config = config
    }
    
    public func start() async throws {
        guard !isRunning else { return }
        
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        
        // Configure listener endpoint
        if config.bindAddress == "0.0.0.0" || config.bindAddress == "::" {
            _ = NWEndpoint.hostPort(host: .ipv4(.any), port: .init(integerLiteral: config.port))
        } else {
            _ = NWEndpoint.hostPort(host: .init(config.bindAddress), port: .init(integerLiteral: config.port))
        }
        
        listener = try NWListener(using: parameters, on: .init(integerLiteral: config.port))
        
        listener?.newConnectionHandler = { [weak self] connection in
            Task {
                await self?.handleIncomingConnection(connection)
            }
        }
        
        listener?.start(queue: .global())
        isRunning = true
        logger.info("UDP CLA started on port \(config.port)")
    }
    
    public func stop() async throws {
        guard isRunning else { return }
        
        listener?.cancel()
        listener = nil
        
        isRunning = false
        logger.info("UDP CLA stopped")
    }
    
    public func sendBundle(_ bundle: BP7.Bundle, to peer: DtnPeer) async throws {
        guard let peerAddress = extractUDPAddress(from: peer) else {
            throw CLAError.invalidPeerAddress
        }
        
        let bundleData = bundle.encode()
        
        // Check bundle size
        guard bundleData.count <= config.maxBundleSize else {
            logger.error("Bundle too large for UDP: \(bundleData.count) bytes")
            throw CLAError.bundleTooLarge(bundleData.count, config.maxBundleSize)
        }
        
        // Create UDP connection
        let endpoint = NWEndpoint.hostPort(
            host: .init(peerAddress.host),
            port: .init(integerLiteral: peerAddress.port)
        )
        
        let connection = NWConnection(to: endpoint, using: .udp)
        connection.start(queue: .global())
        
        // Wait for connection to be ready
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                case .cancelled:
                    continuation.resume(throwing: CLAError.connectionCancelled)
                default:
                    break
                }
            }
        }
        
        // Send bundle data
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: bundleData, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
        
        // Close connection
        connection.cancel()
        
        let bundleId = BundlePack(from: bundle).id
        logger.debug("Sent bundle \(bundleId) via UDP to \(endpoint)")
    }
    
    public nonisolated func canReach(_ peer: DtnPeer) -> Bool {
        // Check if peer has UDP in its CLA list
        return peer.claList.contains { $0.0 == "udp" }
    }
    
    public func getConnections() async -> [CLAConnection] {
        // UDP doesn't maintain persistent connections
        return []
    }
    
    private func handleIncomingConnection(_ connection: NWConnection) async {
        connection.start(queue: .global())
        
        // Receive data
        connection.receive(minimumIncompleteLength: 1, maximumLength: config.maxBundleSize) { [weak self] data, _, isComplete, error in
            Task {
                if let error = error {
                    self?.logger.error("Error receiving UDP data: \(error)")
                } else if let data = data {
                    await self?.handleIncomingData(data, from: connection.endpoint)
                }
                
                // Close connection after receiving
                connection.cancel()
            }
        }
    }
    
    private func handleIncomingData(_ data: Data, from endpoint: NWEndpoint) async {
        do {
            // Parse bundle
            let bundle = try BP7.Bundle.decode(from: Array(data))
            let bundleId = BundlePack(from: bundle).id
            
            logger.debug("Received bundle \(bundleId) via UDP from \(endpoint)")
            
            // Create connection info
            let connection = CLAConnection(
                id: "udp-\(endpoint)",
                remoteEndpointId: nil, // UDP doesn't provide peer ID
                remoteAddress: "\(endpoint)",
                claType: "udp",
                establishedAt: Date()
            )
            
            // Send to incoming channel
            await incomingBundles.send((bundle, connection))
            
        } catch {
            logger.error("Failed to parse bundle from UDP data: \(error)")
        }
    }
    
    private func extractUDPAddress(from peer: DtnPeer) -> (host: String, port: UInt16)? {
        switch peer.addr {
        case .ip(let host, let port):
            // Check if UDP port is specified in CLA list
            for (cla, claPort) in peer.claList where cla == "udp" {
                if let claPort = claPort {
                    return (host, claPort)
                }
            }
            // Fall back to default port
            return (host, UInt16(port))
        default:
            return nil
        }
    }
}

extension CLAError {
    static func bundleTooLarge(_ actualSize: Int, _ maxSize: Int) -> CLAError {
        .invalidProtocol("Bundle too large: \(actualSize) bytes (max: \(maxSize))")
    }
}