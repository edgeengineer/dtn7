import Foundation
import BP7
import Logging
import AsyncAlgorithms

/// The central DTN core that manages all components
public actor DtnCore {
    // Core components
    public let nodeId: EndpointID
    public let store: any BundleStore
    public let bundleProcessor: BundleProcessor
    public let claRegistry: CLARegistry
    public let peerManager: PeerManager
    public let serviceRegistry: ServiceRegistry
    public let applicationAgent: ApplicationAgent
    
    // Routing agent (optional, can be set later)
    private var routingAgent: (any RoutingAgent)?
    
    // Statistics
    private var statistics = DtnStatistics()
    
    // Logger
    private let logger = Logger(label: "DtnCore")
    
    // Background tasks
    private var backgroundTasks: [Task<Void, Never>] = []
    
    // Registered endpoints
    private var localEndpoints: Set<EndpointID> = []
    
    public init(
        nodeId: EndpointID,
        store: any BundleStore,
        config: DtnConfig
    ) {
        self.nodeId = nodeId
        self.store = store
        self.bundleProcessor = BundleProcessor(config: config)
        self.claRegistry = CLARegistry()
        self.peerManager = PeerManager(peerTimeout: config.peerTimeout)
        self.serviceRegistry = ServiceRegistry()
        self.applicationAgent = ApplicationAgent()
        
        // Register the node ID as a local endpoint
        self.localEndpoints.insert(nodeId)
    }
    
    /// Start the DTN core
    public func start() async throws {
        logger.info("Starting DTN Core for node: \(nodeId)")
        
        // Start peer manager
        await peerManager.start()
        
        // Start routing agent if configured
        if let agent = routingAgent {
            try await agent.start()
        }
        
        // Start background tasks
        startBackgroundTasks()
        
        logger.info("DTN Core started successfully")
    }
    
    /// Stop the DTN core
    public func stop() async throws {
        logger.info("Stopping DTN Core")
        
        // Cancel background tasks
        for task in backgroundTasks {
            task.cancel()
        }
        backgroundTasks.removeAll()
        
        // Stop components
        await peerManager.stop()
        
        if let agent = routingAgent {
            try await agent.stop()
        }
        
        try await claRegistry.stopAll()
        
        logger.info("DTN Core stopped")
    }
    
    // MARK: - Component Management
    
    /// Set the routing agent
    public func setRoutingAgent(_ agent: any RoutingAgent) async throws {
        if let oldAgent = routingAgent {
            try await oldAgent.stop()
        }
        
        routingAgent = agent
        await agent.configure(peerManager: peerManager, core: self)
        try await agent.start()
    }
    
    /// Register a CLA
    public func registerCLA(_ cla: any ConvergenceLayerAgent) async throws {
        // Set node ID if CLA supports it
        if let tcpCLA = cla as? TCPCLA {
            await tcpCLA.setNodeId(nodeId.description)
        }
        
        try await claRegistry.register(cla)
        
        // Start listening for incoming bundles from this CLA
        let task = Task {
            await listenForBundles(from: cla)
        }
        backgroundTasks.append(task)
    }
    
    // MARK: - Endpoint Management
    
    /// Register a local endpoint
    public func registerEndpoint(_ endpoint: EndpointID) async -> AsyncChannel<BP7.Bundle> {
        localEndpoints.insert(endpoint)
        logger.info("Registered local endpoint: \(endpoint)")
        // Also register with application agent for bundle delivery
        return await applicationAgent.registerEndpoint(endpoint)
    }
    
    /// Unregister a local endpoint
    public func unregisterEndpoint(_ endpoint: EndpointID) async {
        localEndpoints.remove(endpoint)
        await applicationAgent.unregisterEndpoint(endpoint)
        logger.info("Unregistered local endpoint: \(endpoint)")
    }
    
    /// Check if an endpoint is local
    public func isLocalEndpoint(_ endpoint: EndpointID) -> Bool {
        // Check exact match
        if localEndpoints.contains(endpoint) {
            return true
        }
        
        // Check pattern matching for group endpoints
        for local in localEndpoints {
            if matchesEndpoint(endpoint, pattern: local) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Bundle Operations
    
    /// Submit a bundle for transmission
    public func submitBundle(_ bundle: BP7.Bundle) async throws {
        statistics.recordIncoming()
        
        // Store the bundle
        try await store.push(bundle: bundle)
        
        // Process it
        try await bundleProcessor.transmit(bundle: bundle)
    }
    
    /// Get routing decision for a bundle
    public func getRoutingDecision(for bundle: BP7.Bundle) async -> RoutingDecision {
        guard let agent = routingAgent else {
            // Default: try all known peers
            let peers = await peerManager.getAllPeers()
            return RoutingDecision(
                bundleId: BundlePack(from: bundle).id,
                nextHops: peers,
                isLocalDelivery: isLocalEndpoint(bundle.primary.destination)
            )
        }
        
        return await agent.getNextHops(for: bundle)
    }
    
    /// Send a bundle to specific peers
    public func sendBundle(_ bundle: BP7.Bundle, to peers: [DtnPeer]) async {
        for peer in peers {
            let clas = await claRegistry.findCLAsForPeer(peer)
            
            for cla in clas {
                do {
                    try await cla.sendBundle(bundle, to: peer)
                    statistics.recordOutgoing()
                    await peerManager.recordSuccess(for: peer.eid)
                    break // Success, don't try other CLAs
                } catch {
                    logger.warning("Failed to send bundle via \(cla.name): \(error)")
                    await peerManager.recordFailure(for: peer.eid)
                }
            }
        }
    }
    
    // MARK: - Statistics
    
    /// Get current statistics
    public func getStatistics() async -> DtnStatistics {
        var stats = statistics
        stats.updateStored(await store.count())
        return stats
    }
    
    /// Update statistics
    public func updateStatistics(_ update: (inout DtnStatistics) -> Void) {
        update(&statistics)
    }
    
    // MARK: - Service Management
    
    /// Register a service
    public func registerService(_ service: DtnService) async {
        await serviceRegistry.register(service)
        _ = await registerEndpoint(service.endpoint)
    }
    
    /// Get services for an endpoint
    public func getServices(for endpoint: EndpointID) async -> [DtnService] {
        await serviceRegistry.getServices(for: endpoint)
    }
    
    // MARK: - Private Methods
    
    private func startBackgroundTasks() {
        // Peer event handler
        let peerTask = Task {
            for await event in peerManager.peerEvents {
                await handlePeerEvent(event)
            }
        }
        backgroundTasks.append(peerTask)
    }
    
    private func listenForBundles(from cla: any ConvergenceLayerAgent) async {
        for await (bundle, connection) in cla.incomingBundles {
            do {
                logger.info("Received bundle from \(cla.name): \(BundlePack(from: bundle).id)")
                
                // Update peer info if available
                if let remoteEid = connection.remoteEndpointId {
                    if await peerManager.getPeer(remoteEid) != nil {
                        await peerManager.recordSuccess(for: remoteEid)
                    }
                }
                
                // Process the bundle
                try await bundleProcessor.receive(bundle: bundle)
                statistics.recordIncoming()
                
            } catch {
                logger.error("Failed to process bundle from \(cla.name): \(error)")
                statistics.recordFailed()
            }
        }
    }
    
    private func handlePeerEvent(_ event: PeerEvent) async {
        switch event {
        case .discovered(let peer):
            logger.info("Peer discovered: \(peer.eid)")
            if let agent = routingAgent {
                await agent.handleNotification(.notifyPeerEncountered(peer: peer))
            }
            
        case .lost(let peer):
            logger.info("Peer lost: \(peer.eid)")
            if let agent = routingAgent {
                await agent.handleNotification(.notifyPeerLost(peer: peer))
            }
            
        case .updated, .connectionEstablished, .connectionLost:
            // Handle other events as needed
            break
        }
    }
    
    private func matchesEndpoint(_ endpoint: EndpointID, pattern: EndpointID) -> Bool {
        // Simple pattern matching - can be enhanced
        // For now, just check if pattern is a prefix
        return endpoint.description.hasPrefix(pattern.description)
    }
}

