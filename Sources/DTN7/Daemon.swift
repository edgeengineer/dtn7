#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Hummingbird
import Logging
import BP7
import CBOR

struct StatusResponse: Codable {
    let nodeId: String
    let uptime: TimeInterval
    let version: String
    let statistics: StatsInfo
}

struct StatsInfo: Codable {
    let incoming: UInt64
    let outgoing: UInt64
    let delivered: UInt64
    let stored: UInt64
}

struct BundlesResponse: Codable {
    let count: Int
    let bundles: [String]
}

struct PeerInfo: Codable {
    let eid: String
    let type: String
    let lastContact: TimeInterval
    let services: [UInt8: String]
}

struct PeersResponse: Codable {
    let count: Int
    let peers: [PeerInfo]
}

struct StatsResponse: Codable {
    let incoming: UInt64
    let duplicates: UInt64
    let outgoing: UInt64
    let delivered: UInt64
    let failed: UInt64
    let broken: UInt64
    let stored: UInt64
}

/// The main DTN daemon class.
public actor Daemon {
    private let config: DtnConfig
    private var logger: Logger
    private var app: Application<RouterResponder<BasicRequestContext>>
    private let core: DtnCore
    private let startTime: Date
    
    public init(config: DtnConfig) async throws {
        self.config = config
        self.logger = Logger(label: "dtnd")
        self.startTime = Date()
        
        // Initialize store based on config
        let store: any BundleStore
        switch config.db {
        case "sled", "sneakers":
            // For now, fall back to CSQLite for persistent storage
            logger.info("Using CSQLite store (requested: \(config.db))")
            store = try CSQLiteStore(path: "\(config.workdir)/bundles.db")
        case "mem":
            logger.info("Using in-memory store")
            store = InMemoryBundleStore()
        default:
            logger.info("Using CSQLite store at: \(config.workdir)/bundles.db")
            store = try CSQLiteStore(path: "\(config.workdir)/bundles.db")
        }
        
        // Parse node ID
        let nodeId = try EndpointID.from(config.nodeId.isEmpty ? "dtn://node1" : config.nodeId)
        
        // Create DTN core
        self.core = DtnCore(nodeId: nodeId, store: store, config: config)
        
        // Set up bundle processor reference
        await core.bundleProcessor.setCore(core)
        
        // Register configured endpoints
        for endpoint in config.endpoints {
            if let eid = try? EndpointID.from(endpoint) {
                _ = await core.registerEndpoint(eid)
            }
        }
        
        // Register services
        for (tag, description) in config.services {
            let service = DtnService(tag: tag, endpoint: nodeId, description: description)
            await core.registerService(service)
        }
        
        // Set up HTTP API
        let router = Router<BasicRequestContext>()
        
        self.app = Application(
            router: router,
            configuration: .init(
                address: .hostname(config.ipv6 ? "::1" : "127.0.0.1", port: Int(config.webPort))
            )
        )
        
        setupRoutes(router: router)
        
        // Initialize and register CLAs
        for claConfig in config.clas {
            do {
                let cla = try await createCLA(from: claConfig)
                try await core.registerCLA(cla)
                logger.info("Registered CLA: \(claConfig.type)")
            } catch {
                logger.error("Failed to initialize CLA \(claConfig.type): \(error)")
            }
        }
        
        // If no CLAs configured, add default TCP CLA
        if config.clas.isEmpty {
            let tcpCLA = TCPCLA()
            try await core.registerCLA(tcpCLA)
            logger.info("Registered default TCP CLA")
        }
        
        // Initialize routing agent based on configuration
        let routingAgent = try await createRoutingAgent()
        try await core.setRoutingAgent(routingAgent)
        logger.info("Initialized \(config.routing) routing")
    }

    /// The main entry point for running the daemon.
    public func run() async throws {
        logger.info("Starting DTN7 Daemon...")
        logger.info("Node ID: \(core.nodeId)")
        logger.info("Web interface: http://\(config.ipv6 ? "[::1]" : "127.0.0.1"):\(config.webPort)")
        
        // Start the core
        try await core.start()
        
        // Run the HTTP server
        try await app.runService()
    }
    
    /// Set up HTTP routes
    private func setupRoutes(router: Router<BasicRequestContext>) {
        // Simple test route
        router.get("/test") { _, _ in
            return "Test route working"
        }
        
        // Status endpoint
        router.get("/") { _,_ in
            return """
            <html>
            <head><title>DTN7 Swift</title></head>
            <body>
            <h1>DTN7 Swift Node</h1>
            <p>Node ID: \(self.core.nodeId)</p>
            <p>Status: Running</p>
            <ul>
            <li><a href="/status">Status</a></li>
            <li><a href="/bundles">Bundles</a></li>
            <li><a href="/peers">Peers</a></li>
            <li><a href="/stats">Statistics</a></li>
            </ul>
            </body>
            </html>
            """
        }
        
        // API routes with JSON responses
        router.get("/status") { _, _ async in
            let stats = await self.core.getStatistics()
            let status = StatusResponse(
                nodeId: self.core.nodeId.description,
                uptime: Date().timeIntervalSince(self.startTime),
                version: "0.0.1",
                statistics: StatsInfo(
                    incoming: stats.incoming,
                    outgoing: stats.outgoing,
                    delivered: stats.delivered,
                    stored: UInt64(stats.stored)
                )
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let jsonData = try? encoder.encode(status),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "{\"error\": \"Failed to encode status\"}"
        }
        
        router.get("/bundles") { _, _ async in
            let count = await self.core.store.count()
            let bundleIds = await self.core.store.allIds()
            
            let response = BundlesResponse(
                count: Int(count),
                bundles: bundleIds
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let jsonData = try? encoder.encode(response),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "{\"error\": \"Failed to encode bundles\"}"
        }
        
        router.get("/peers") { _, _ async in
            let peers = await self.core.peerManager.getAllPeers()
            let peerInfos = peers.map { peer in
                PeerInfo(
                    eid: peer.eid.description,
                    type: peer.claList.first?.0 ?? "unknown",
                    lastContact: peer.lastContact,
                    services: peer.services
                )
            }
            
            let response = PeersResponse(
                count: peerInfos.count,
                peers: peerInfos
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let jsonData = try? encoder.encode(response),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "{\"error\": \"Failed to encode peers\"}"
        }
        
        router.get("/stats") { _, _ async in
            let stats = await self.core.getStatistics()
            let response = StatsResponse(
                incoming: stats.incoming,
                duplicates: stats.dups,
                outgoing: stats.outgoing,
                delivered: stats.delivered,
                failed: stats.failed,
                broken: stats.broken,
                stored: stats.stored
            )
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let jsonData = try? encoder.encode(response),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
            return "{\"error\": \"Failed to encode stats\"}"
        }
        
        // Application interface endpoints
        router.get("/register") { request, _ in
            guard let endpoint = request.uri.queryParameters["endpoint"] else {
                return "Error: Missing endpoint parameter"
            }
            
            do {
                let eid = try EndpointID.from(String(endpoint))
                _ = await self.core.registerEndpoint(eid)
                // Store the channel for the application (in a real implementation)
                return "Registered endpoint: \(endpoint)"
            } catch {
                return "Error: Invalid endpoint - \(error)"
            }
        }
        
        router.get("/unregister") { request, _ in
            guard let endpoint = request.uri.queryParameters["endpoint"] else {
                return "Error: Missing endpoint parameter"
            }
            
            do {
                let eid = try EndpointID.from(String(endpoint))
                await self.core.unregisterEndpoint(eid)
                return "Unregistered endpoint: \(endpoint)"
            } catch {
                return "Error: Invalid endpoint - \(error)"
            }
        }
        
        router.post("/send") { request, _ in
            guard let dst = request.uri.queryParameters["dst"] else {
                return "Error: Missing dst parameter"
            }
            
            let src = request.uri.queryParameters["src"].map(String.init) ?? self.core.nodeId.description
            let lifetimeStr = request.uri.queryParameters["lifetime"].map(String.init) ?? "3600000"
            let lifetime = TimeInterval(lifetimeStr) ?? 3600000.0
            
            do {
                let srcEid = try EndpointID.from(src)
                let dstEid = try EndpointID.from(String(dst))
                let payload = try await request.body.collect(upTo: 10 * 1024 * 1024) // 10MB limit
                
                // Create bundle using builder pattern
                let primaryBlock = PrimaryBlockBuilder(destination: dstEid)
                    .source(srcEid)
                    .reportTo(srcEid)
                    .creationTimestamp(CreationTimestamp())
                    .lifetime(lifetime / 1000.0) // Convert from ms to seconds
                    .crc(.crc32(0))
                    .build()
                
                let payloadBlock = CanonicalBlock(
                    blockType: BlockType.payload.rawValue,
                    blockNumber: 1,
                    blockControlFlags: 0,
                    crc: .crc32(0),
                    data: .data(Array(payload.readableBytesView))
                )
                
                let bundle = Bundle(
                    primary: primaryBlock,
                    canonicals: [payloadBlock]
                )
                
                try await self.core.submitBundle(bundle)
                return "Bundle sent from \(src) to \(dst)"
            } catch {
                return "Error: Failed to send bundle - \(error)"
            }
        }
        
        router.get("/endpoint") { request, _ in
            guard let endpoint = request.uri.queryParameters["endpoint"] else {
                return "Error: Missing endpoint parameter"
            }
            
            do {
                let eid = try EndpointID.from(String(endpoint))
                
                // Check if endpoint is registered
                if await self.core.applicationAgent.isEndpointRegistered(eid) {
                    // Get pending bundles for this endpoint
                    let pendingBundles = await self.core.applicationAgent.getPendingBundles(for: eid)
                    
                    if let firstBundle = pendingBundles.first {
                        // Clear the pending bundle
                        await self.core.applicationAgent.clearPendingBundles(for: eid)
                        
                        // Return the bundle as CBOR
                        let bundleData = firstBundle.encode()
                        // Return as base64 for text response
                        return Data(bundleData).base64EncodedString()
                    }
                }
                
                return "Nothing to receive"
            } catch {
                return "Error: Invalid endpoint - \(error)"
            }
        }
    }
    
    /// Create a CLA from configuration
    private func createCLA(from config: DtnConfig.CLAConfig) async throws -> any ConvergenceLayerAgent {
        switch config.type.lowercased() {
        case "tcp", "mtcp":
            let port = UInt16(config.settings["port"] ?? "4556") ?? 4556
            let bindAddress = config.settings["bind"] ?? "0.0.0.0"
            let refuseExisting = config.settings["refuse-existing-bundles"] == "true"
            
            let tcpConfig = TCPCLA.TCPCLAConfig(
                port: port,
                bindAddress: bindAddress,
                refuseExistingBundles: refuseExisting
            )
            return TCPCLA(config: tcpConfig)
            
        case "udp":
            let port = UInt16(config.settings["port"] ?? "4556") ?? 4556
            let bindAddress = config.settings["bind"] ?? "0.0.0.0"
            
            let udpConfig = UDPCLA.UDPCLAConfig(
                port: port,
                bindAddress: bindAddress
            )
            return UDPCLA(config: udpConfig)
            
        case "http":
            return HTTPCLA()
            
        case "httppull":
            let pollingInterval = TimeInterval(config.settings["interval"] ?? "30") ?? 30
            let httpPullConfig = HTTPPullCLA.HTTPPullCLAConfig(
                pollingInterval: pollingInterval
            )
            return HTTPPullCLA(config: httpPullConfig)
            
        default:
            throw CLAError.invalidProtocol("Unknown CLA type: \(config.type)")
        }
    }
    
    /// Create a routing agent based on configuration
    private func createRoutingAgent() async throws -> any RoutingAgent {
        switch config.routing.lowercased() {
        case "epidemic":
            return EpidemicRouting()
            
        case "flooding":
            return FloodingRouting()
            
        case "static":
            // Check for routes file in routing settings
            let routesFile = config.routingSettings["static"]?["routes"]
            return StaticRouting(routesFile: routesFile)
            
        case "sprayandwait", "spray-and-wait", "spray_and_wait":
            // Check for max copies setting
            let maxCopies = config.routingSettings["sprayandwait"]?["num_copies"]
                .flatMap { Int($0) }
            return SprayAndWaitRouting(maxCopies: maxCopies)
            
        case "sink":
            return SinkRouting()
            
        default:
            logger.warning("Unknown routing algorithm '\(config.routing)', defaulting to epidemic")
            return EpidemicRouting()
        }
    }
} 