import Foundation
import BP7
import Logging

/// A static route entry
public struct StaticRoute: Sendable {
    let index: Int
    let sourcePattern: String
    let destinationPattern: String
    let viaNode: EndpointID
    
    init(index: Int, source: String, destination: String, via: String) throws {
        self.index = index
        self.sourcePattern = source
        self.destinationPattern = destination
        self.viaNode = try EndpointID.from(via)
    }
}

/// Static routing algorithm - table-driven routing based on configured rules
public actor StaticRouting: RoutingAgent {
    public let algorithmName = "static"
    
    private let logger = Logger(label: "StaticRouting")
    
    // Routing table
    private var routes: [StaticRoute] = []
    
    // Configuration
    private let routesFile: String?
    
    // Reference to peer manager
    private weak var peerManager: PeerManager?
    
    // Reference to core for local endpoint checks
    private weak var core: DtnCore?
    
    // Statistics
    private var totalRoutingDecisions = 0
    private var matchedRoutes = 0
    
    public init(routesFile: String? = nil) {
        self.routesFile = routesFile
    }
    
    /// Set required references
    public func configure(peerManager: PeerManager, core: DtnCore) {
        self.peerManager = peerManager
        self.core = core
    }
    
    public func start() async throws {
        logger.info("Static routing agent started")
        
        // Load routes from file if specified
        if let routesFile = routesFile {
            try await loadRoutes(from: routesFile)
        }
    }
    
    public func stop() async throws {
        logger.info("Static routing agent stopped")
        routes.removeAll()
    }
    
    public func getNextHops(for bundle: BP7.Bundle) async -> RoutingDecision {
        let bundleId = BundlePack(from: bundle).id
        let source = bundle.primary.source
        let destination = bundle.primary.destination
        
        guard let peerManager = peerManager,
              let core = core else {
            logger.error("Missing required references")
            return RoutingDecision(bundleId: bundleId)
        }
        
        totalRoutingDecisions += 1
        
        // Check if this is for local delivery
        if await core.isLocalEndpoint(destination) {
            logger.debug("Bundle \(bundleId) is for local delivery")
            return RoutingDecision(bundleId: bundleId, nextHops: [], isLocalDelivery: true)
        }
        
        // Get all current peers
        let allPeers = await peerManager.getAllPeers()
        
        // Find matching route
        for route in routes.sorted(by: { $0.index < $1.index }) {
            if matchesPattern(source.description, pattern: route.sourcePattern) &&
               matchesPattern(destination.description, pattern: route.destinationPattern) {
                
                logger.debug("Bundle \(bundleId) matches route #\(route.index): \(route.sourcePattern) -> \(route.destinationPattern) via \(route.viaNode)")
                
                // Find the peer matching the via node
                if let peer = allPeers.first(where: { $0.eid == route.viaNode }) {
                    if !peer.claList.isEmpty {
                        matchedRoutes += 1
                        logger.info("Routing bundle \(bundleId) via \(peer.eid) using route #\(route.index)")
                        return RoutingDecision(bundleId: bundleId, nextHops: [peer])
                    } else {
                        logger.warning("Via node \(route.viaNode) has no CLAs available")
                    }
                } else {
                    logger.warning("Via node \(route.viaNode) is not currently a peer")
                }
            }
        }
        
        logger.debug("No matching route found for bundle \(bundleId) (source: \(source), dest: \(destination))")
        return RoutingDecision(bundleId: bundleId)
    }
    
    public func handleNotification(_ notification: RoutingCommand) async {
        switch notification {
        case .updateConfig(let config):
            // Check if this is a reload command
            if config["command"] == "reload" {
                logger.info("Reloading static routes")
                if let routesFile = routesFile {
                    do {
                        try await loadRoutes(from: routesFile)
                    } catch {
                        logger.error("Failed to reload routes: \(error)")
                    }
                }
            }
            
        default:
            logger.trace("Received notification: \(notification) (ignored)")
        }
    }
    
    public func getState() async -> [String: String] {
        let routesInfo = routes.map { route in
            "#\(route.index): \(route.sourcePattern) -> \(route.destinationPattern) via \(route.viaNode.description)"
        }.joined(separator: "; ")
        
        return [
            "algorithm": algorithmName,
            "routes_count": "\(routes.count)",
            "routes": routesInfo,
            "total_routing_decisions": "\(totalRoutingDecisions)",
            "matched_routes": "\(matchedRoutes)",
            "routes_file": routesFile ?? "none"
        ]
    }
    
    /// Load routes from a configuration file
    public func loadRoutes(from file: String) async throws {
        logger.info("Loading routes from: \(file)")
        
        let fileURL = URL(fileURLWithPath: file)
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        
        var newRoutes: [StaticRoute] = []
        
        for (lineNumber, line) in contents.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and comments
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }
            
            // Parse route: index source destination via
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            
            guard parts.count == 4 else {
                logger.warning("Invalid route at line \(lineNumber + 1): \(line)")
                continue
            }
            
            guard let index = Int(parts[0]) else {
                logger.warning("Invalid index at line \(lineNumber + 1): \(parts[0])")
                continue
            }
            
            do {
                let route = try StaticRoute(
                    index: index,
                    source: parts[1],
                    destination: parts[2],
                    via: parts[3]
                )
                newRoutes.append(route)
            } catch {
                logger.warning("Invalid route at line \(lineNumber + 1): \(error)")
            }
        }
        
        routes = newRoutes
        logger.info("Loaded \(routes.count) static routes")
    }
    
    /// Add a route programmatically
    public func addRoute(_ route: StaticRoute) {
        routes.append(route)
        logger.info("Added route #\(route.index): \(route.sourcePattern) -> \(route.destinationPattern) via \(route.viaNode)")
    }
    
    /// Clear all routes
    public func clearRoutes() {
        routes.removeAll()
        logger.info("Cleared all routes")
    }
    
    /// Check if a string matches a glob pattern
    private func matchesPattern(_ string: String, pattern: String) -> Bool {
        // Simple pattern matching with * wildcard
        if pattern == "*" {
            return true
        }
        
        // Convert glob pattern to regex
        let escapedPattern = NSRegularExpression.escapedPattern(for: pattern)
        let finalPattern = escapedPattern
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        
        do {
            let regex = try NSRegularExpression(pattern: "^\\(finalPattern)$", options: [])
            let range = NSRange(location: 0, length: string.count)
            return regex.firstMatch(in: string, options: [], range: range) != nil
        } catch {
            logger.error("Invalid pattern: \(pattern)")
            return false
        }
    }
}