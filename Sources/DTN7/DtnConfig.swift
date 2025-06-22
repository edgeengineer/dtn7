#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import BP7

/// The main configuration for the DTN daemon.
public struct DtnConfig: Codable, Sendable {
    public var debug: Bool = false
    public var unsafeHttpd: Bool = false
    public var ipv4: Bool = true
    public var ipv6: Bool = false
    public var customTimeout: Bool = false
    public var enablePeriod: Bool = false
    public var nodeId: String = ""
    public var hostEid: EndpointID?
    public var webPort: UInt16 = 4242
    public var announcementInterval: TimeInterval = 60
    public var disableNeighbourDiscovery: Bool = false
    public var discoveryDestinations: [String: UInt32] = [:]
    public var janitorInterval: TimeInterval = 10
    public var endpoints: [String] = []
    public var clas: [CLAConfig] = []
    public var services: [UInt8: String] = [:]
    
    /// Configuration for a Convergence Layer Agent
    public struct CLAConfig: Codable, Sendable {
        public let type: String
        public let settings: [String: String]
        
        public init(type: String, settings: [String: String] = [:]) {
            self.type = type
            self.settings = settings
        }
    }
    public var routing: String = "epidemic"
    public var routingSettings: [String: [String: String]] = [:]
    public var peerTimeout: TimeInterval = 300
    public var statics: [DtnPeer] = []
    public var workdir: String = "."
    public var db: String = "mem"
    public var generateStatusReports: Bool = false
    public var eclaTcpPort: UInt16 = 4243
    public var eclaEnable: Bool = false
    public var parallelBundleProcessing: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case debug, unsafeHttpd, ipv4, ipv6, customTimeout, enablePeriod, nodeId, hostEid, webPort, announcementInterval, disableNeighbourDiscovery, discoveryDestinations, janitorInterval, endpoints, clas, services, routing, routingSettings, peerTimeout, statics, workdir, db, generateStatusReports, eclaTcpPort, eclaEnable, parallelBundleProcessing
    }

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        debug = try container.decode(Bool.self, forKey: .debug)
        unsafeHttpd = try container.decode(Bool.self, forKey: .unsafeHttpd)
        ipv4 = try container.decode(Bool.self, forKey: .ipv4)
        ipv6 = try container.decode(Bool.self, forKey: .ipv6)
        customTimeout = try container.decode(Bool.self, forKey: .customTimeout)
        enablePeriod = try container.decode(Bool.self, forKey: .enablePeriod)
        nodeId = try container.decode(String.self, forKey: .nodeId)
        if let hostEidString = try container.decodeIfPresent(String.self, forKey: .hostEid) {
            hostEid = try EndpointID.from(hostEidString)
        }
        webPort = try container.decode(UInt16.self, forKey: .webPort)
        announcementInterval = try container.decode(TimeInterval.self, forKey: .announcementInterval)
        disableNeighbourDiscovery = try container.decode(Bool.self, forKey: .disableNeighbourDiscovery)
        discoveryDestinations = try container.decode([String: UInt32].self, forKey: .discoveryDestinations)
        janitorInterval = try container.decode(TimeInterval.self, forKey: .janitorInterval)
        endpoints = try container.decode([String].self, forKey: .endpoints)
        clas = try container.decodeIfPresent([CLAConfig].self, forKey: .clas) ?? []
        services = try container.decode([UInt8: String].self, forKey: .services)
        routing = try container.decode(String.self, forKey: .routing)
        routingSettings = try container.decode([String: [String: String]].self, forKey: .routingSettings)
        peerTimeout = try container.decode(TimeInterval.self, forKey: .peerTimeout)
        statics = try container.decode([DtnPeer].self, forKey: .statics)
        workdir = try container.decode(String.self, forKey: .workdir)
        db = try container.decode(String.self, forKey: .db)
        generateStatusReports = try container.decode(Bool.self, forKey: .generateStatusReports)
        eclaTcpPort = try container.decode(UInt16.self, forKey: .eclaTcpPort)
        eclaEnable = try container.decode(Bool.self, forKey: .eclaEnable)
        parallelBundleProcessing = try container.decode(Bool.self, forKey: .parallelBundleProcessing)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(debug, forKey: .debug)
        try container.encode(unsafeHttpd, forKey: .unsafeHttpd)
        try container.encode(ipv4, forKey: .ipv4)
        try container.encode(ipv6, forKey: .ipv6)
        try container.encode(customTimeout, forKey: .customTimeout)
        try container.encode(enablePeriod, forKey: .enablePeriod)
        try container.encode(nodeId, forKey: .nodeId)
        try container.encodeIfPresent(hostEid?.description, forKey: .hostEid)
        try container.encode(webPort, forKey: .webPort)
        try container.encode(announcementInterval, forKey: .announcementInterval)
        try container.encode(disableNeighbourDiscovery, forKey: .disableNeighbourDiscovery)
        try container.encode(discoveryDestinations, forKey: .discoveryDestinations)
        try container.encode(janitorInterval, forKey: .janitorInterval)
        try container.encode(endpoints, forKey: .endpoints)
        try container.encode(clas, forKey: .clas)
        try container.encode(services, forKey: .services)
        try container.encode(routing, forKey: .routing)
        try container.encode(routingSettings, forKey: .routingSettings)
        try container.encode(peerTimeout, forKey: .peerTimeout)
        try container.encode(statics, forKey: .statics)
        try container.encode(workdir, forKey: .workdir)
        try container.encode(db, forKey: .db)
        try container.encode(generateStatusReports, forKey: .generateStatusReports)
        try container.encode(eclaTcpPort, forKey: .eclaTcpPort)
        try container.encode(eclaEnable, forKey: .eclaEnable)
        try container.encode(parallelBundleProcessing, forKey: .parallelBundleProcessing)
    }
} 