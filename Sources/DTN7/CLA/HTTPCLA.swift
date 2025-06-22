#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import BP7
import AsyncAlgorithms
import Logging
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HTTP Convergence Layer Agent for REST-based bundle transfer
public actor HTTPCLA: ConvergenceLayerAgent {
    public let id: String
    public let name: String = "http"
    public let incomingBundles = AsyncChannel<(BP7.Bundle, CLAConnection)>()
    
    private let config: HTTPCLAConfig
    private let logger = Logger(label: "HTTPCLA")
    private var isRunning = false
    private let session: URLSession
    
    /// Configuration for HTTP CLA
    public struct HTTPCLAConfig: Sendable {
        public let timeout: TimeInterval
        public let maxRetries: Int
        
        public init(
            timeout: TimeInterval = 5.0,
            maxRetries: Int = 3
        ) {
            self.timeout = timeout
            self.maxRetries = maxRetries
        }
    }
    
    public init(config: HTTPCLAConfig = HTTPCLAConfig()) {
        self.id = "http"
        self.config = config
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = config.timeout
        sessionConfig.timeoutIntervalForResource = config.timeout * 2
        self.session = URLSession(configuration: sessionConfig)
    }
    
    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true
        logger.info("HTTP CLA started")
        // Note: Incoming bundles are handled by the HTTP daemon, not this CLA
    }
    
    public func stop() async throws {
        guard isRunning else { return }
        isRunning = false
        logger.info("HTTP CLA stopped")
    }
    
    public func sendBundle(_ bundle: BP7.Bundle, to peer: DtnPeer) async throws {
        guard let url = buildPeerURL(for: peer) else {
            throw CLAError.invalidPeerAddress
        }
        
        let bundleData = bundle.encode()
        let bundleId = BundlePack(from: bundle).id
        
        var lastError: Error?
        
        for attempt in 1...config.maxRetries {
            do {
                try await sendBundleHTTP(bundleData: Data(bundleData), to: url)
                logger.debug("Sent bundle \(bundleId) via HTTP to \(url) (attempt \(attempt))")
                return
            } catch {
                lastError = error
                logger.warning("Failed to send bundle via HTTP (attempt \(attempt)/\(config.maxRetries)): \(error)")
                
                if attempt < config.maxRetries {
                    // Exponential backoff
                    let delay = TimeInterval(attempt) * 0.5
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? CLAError.connectionFailed
    }
    
    public nonisolated func canReach(_ peer: DtnPeer) -> Bool {
        // Check if peer has HTTP in its CLA list or if we can construct a valid URL
        if peer.claList.contains(where: { $0.0 == "http" || $0.0 == "httppull" }) {
            return true
        }
        
        // Check if we can build a URL for this peer
        // Check if we have enough info to build a URL
        switch peer.addr {
        case .ip(_, _):
            return true
        case .generic(let addr):
            return URL(string: addr) != nil
        default:
            return false
        }
    }
    
    public func getConnections() async -> [CLAConnection] {
        // HTTP doesn't maintain persistent connections
        return []
    }
    
    private func sendBundleHTTP(bundleData: Data, to url: URL) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bundleData
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("\(bundleData.count)", forHTTPHeaderField: "Content-Length")
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CLAError.invalidResponse
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CLAError.httpError(httpResponse.statusCode)
        }
    }
    
    private func buildPeerURL(for peer: DtnPeer) -> URL? {
        var host: String?
        var port: UInt16?
        
        switch peer.addr {
        case .ip(let h, let p):
            host = h
            port = UInt16(p)
        case .generic(let addr):
            // Try to parse as URL
            if let url = URL(string: addr) {
                return url.appendingPathComponent("push")
            }
        default:
            break
        }
        
        // Check CLA list for HTTP port
        for (cla, claPort) in peer.claList where cla == "http" || cla == "httppull" {
            if let claPort = claPort {
                port = claPort
            }
        }
        
        guard let host = host, let port = port else {
            return nil
        }
        
        // Build URL
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        components.path = "/push"
        
        return components.url
    }
}

/// HTTP Pull CLA - periodically polls peers for new bundles
public actor HTTPPullCLA: ConvergenceLayerAgent {
    public let id: String = "httppull"
    public let name: String = "httppull"
    public let incomingBundles = AsyncChannel<(BP7.Bundle, CLAConnection)>()
    
    private let config: HTTPPullCLAConfig
    private let logger = Logger(label: "HTTPPullCLA")
    private var isRunning = false
    private let session: URLSession
    private var pollingTask: Task<Void, Never>?
    private var knownBundles: Set<String> = []
    
    /// Configuration for HTTP Pull CLA
    public struct HTTPPullCLAConfig: Sendable {
        public let pollingInterval: TimeInterval
        public let timeout: TimeInterval
        
        public init(
            pollingInterval: TimeInterval = 30.0,
            timeout: TimeInterval = 5.0
        ) {
            self.pollingInterval = pollingInterval
            self.timeout = timeout
        }
    }
    
    public init(config: HTTPPullCLAConfig = HTTPPullCLAConfig()) {
        self.config = config
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = config.timeout
        sessionConfig.timeoutIntervalForResource = config.timeout * 2
        self.session = URLSession(configuration: sessionConfig)
    }
    
    public func start() async throws {
        guard !isRunning else { return }
        isRunning = true
        
        // Start polling task
        pollingTask = Task {
            await startPolling()
        }
        
        logger.info("HTTP Pull CLA started")
    }
    
    public func stop() async throws {
        guard isRunning else { return }
        
        isRunning = false
        pollingTask?.cancel()
        pollingTask = nil
        
        logger.info("HTTP Pull CLA stopped")
    }
    
    public func sendBundle(_ bundle: BP7.Bundle, to peer: DtnPeer) async throws {
        // HTTP Pull doesn't support sending
        throw CLAError.operationNotSupported("HTTP Pull CLA cannot send bundles")
    }
    
    public nonisolated func canReach(_ peer: DtnPeer) -> Bool {
        // HTTP Pull can't actively reach peers
        return false
    }
    
    public func getConnections() async -> [CLAConnection] {
        // HTTP Pull doesn't maintain connections
        return []
    }
    
    private func startPolling() async {
        while isRunning && !Task.isCancelled {
            // Note: In a real implementation, we would get peers from DtnCore
            // For now, this is a placeholder
            
            // Sleep for polling interval
            do {
                try await Task.sleep(nanoseconds: UInt64(config.pollingInterval * 1_000_000_000))
            } catch {
                break
            }
        }
    }
    
    public func pollPeer(_ peer: DtnPeer) async {
        guard let baseURL = buildPeerURL(for: peer) else {
            return
        }
        
        do {
            // Get bundle list from peer
            let bundleIds = try await fetchBundleList(from: baseURL)
            
            // Find new bundles
            let newBundles = bundleIds.filter { !knownBundles.contains($0) }
            
            // Download new bundles
            for bundleId in newBundles {
                do {
                    let bundle = try await downloadBundle(bundleId: bundleId, from: baseURL)
                    
                    // Add to known bundles
                    knownBundles.insert(bundleId)
                    
                    // Create connection info
                    let connection = CLAConnection(
                        id: "httppull-\(peer.eid)",
                        remoteEndpointId: peer.eid,
                        remoteAddress: baseURL.absoluteString,
                        claType: "httppull",
                        establishedAt: Date()
                    )
                    
                    // Send to incoming channel
                    await incomingBundles.send((bundle, connection))
                    
                    logger.debug("Downloaded bundle \(bundleId) from \(peer.eid)")
                    
                } catch {
                    logger.error("Failed to download bundle \(bundleId): \(error)")
                }
            }
            
        } catch {
            logger.error("Failed to poll peer \(peer.eid): \(error)")
        }
    }
    
    private func fetchBundleList(from baseURL: URL) async throws -> [String] {
        let url = baseURL.appendingPathComponent("status/bundles")
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw CLAError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        // Parse JSON response
        struct BundleListResponse: Codable {
            let bundles: [String]
        }
        
        let decoder = JSONDecoder()
        let bundleList = try decoder.decode(BundleListResponse.self, from: data)
        return bundleList.bundles
    }
    
    private func downloadBundle(bundleId: String, from baseURL: URL) async throws -> BP7.Bundle {
        var components = URLComponents(url: baseURL.appendingPathComponent("download"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "bundle", value: bundleId)]
        
        guard let url = components?.url else {
            throw CLAError.invalidPeerAddress
        }
        
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw CLAError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        return try BP7.Bundle.decode(from: Array(data))
    }
    
    private func buildPeerURL(for peer: DtnPeer) -> URL? {
        var host: String?
        var port: UInt16?
        
        switch peer.addr {
        case .ip(let h, let p):
            host = h
            port = UInt16(p)
        case .generic(let addr):
            // Try to parse as URL
            return URL(string: addr)
        default:
            break
        }
        
        // Check CLA list for HTTP port
        for (cla, claPort) in peer.claList where cla == "http" || cla == "httppull" {
            if let claPort = claPort {
                port = claPort
            }
        }
        
        guard let host = host, let port = port else {
            return nil
        }
        
        // Build URL
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        
        return components.url
    }
}

extension CLAError {
    static let connectionFailed = CLAError.invalidProtocol("Connection failed")
    static let invalidResponse = CLAError.invalidProtocol("Invalid HTTP response")
    
    static func httpError(_ statusCode: Int) -> CLAError {
        .invalidProtocol("HTTP error: \(statusCode)")
    }
    
    static func operationNotSupported(_ message: String) -> CLAError {
        .invalidProtocol(message)
    }
}