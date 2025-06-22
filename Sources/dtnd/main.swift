import DTN7
import ArgumentParser
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@main
struct Dtnd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A DTN7 Bundle Protocol Agent (BPA).")

    @Option(name: .shortAndLong, help: "Sets a custom config file")
    var config: String?
    
    @Option(name: .shortAndLong, help: "Sets local node name (e.g. 'dtn://node1')")
    var nodeid: String?
    
    @Option(name: [.customShort("W"), .long], help: "Sets the working directory")
    var workdir: String = "."
    
    @Flag(name: .shortAndLong, help: "Set log level to debug")
    var debug = false
    
    @Flag(name: [.customShort("4"), .long], help: "Use IPv4")
    var ipv4 = false
    
    @Flag(name: [.customShort("6"), .long], help: "Use IPv6")
    var ipv6 = false
    
    // Service Configuration
    @Option(name: .shortAndLong, parsing: .upToNextOption, help: "Register application agent endpoints (can be repeated)")
    var endpoint: [String] = []
    
    @Option(name: [.customShort("w"), .long], help: "Sets web interface port")
    var webPort: UInt16 = 3000
    
    @Option(name: .shortAndLong, help: "Sets service discovery interval (e.g., '2s', '3m')")
    var interval: String?
    
    @Option(name: .shortAndLong, help: "Sets janitor interval for cleanup")
    var janitor: String?
    
    @Option(name: [.customShort("p"), .long], help: "Sets timeout to remove peer")
    var peerTimeout: String = "20s"
    
    // Routing
    @Option(name: .shortAndLong, help: "Set routing algorithm: epidemic, flooding, sink, external, sprayandwait, static")
    var routing: String = "epidemic"
    
    @Option(name: [.customShort("R"), .long], parsing: .upToNextOption, help: "Set routing options (e.g., 'sprayandwait.num_copies=5')")
    var routingOptions: [String] = []
    
    // Convergence Layer Agents
    @Option(name: [.customShort("C"), .long], parsing: .upToNextOption, help: "Add convergence layer agent: dummy, external, http, httppull, mtcp, tcp, udp")
    var cla: [String] = []
    
    @Option(name: [.customShort("O"), .long], parsing: .upToNextOption, help: "Add global CLA options")
    var global: [String] = []
    
    // Discovery & Peers
    @Option(name: [.customShort("E"), .long], help: "Sets discovery destination (default IPv4=224.0.0.26:3003, IPv6=[FF02::300]:3003)")
    var discoveryDestination: String?
    
    @Option(name: [.customShort("s"), .long], parsing: .upToNextOption, help: "Add static peers (e.g., 'mtcp://192.168.2.1:2342/node2')")
    var staticPeer: [String] = []
    
    @Flag(name: [.customShort("b"), .long], help: "Enable beacon period advertisement")
    var beaconPeriod = false
    
    @Flag(name: .long, help: "Explicitly disable neighbour discovery")
    var disableNd = false
    
    // Storage
    @Option(name: [.customShort("D"), .long], help: "Set bundle store: mem, sled, sneakers")
    var db: String = "mem"
    
    // Advanced Options
    @Option(name: [.customShort("S"), .long], parsing: .upToNextOption, help: "Add custom services with specific tags")
    var service: [String] = []
    
    @Flag(name: [.customShort("g"), .long], help: "Generate status report bundles")
    var generateStatusReports = false
    
    @Flag(name: .long, help: "Process bundles in parallel")
    var parallelBundleProcessing = false
    
    @Flag(name: [.customShort("U"), .long], help: "Allow httpd RPC calls from anywhere")
    var unsafeHttpd = false
    
    @Flag(name: .long, help: "Enable ECLA (WebSocket transport)")
    var ecla = false
    
    @Option(name: .long, help: "Set ECLA TCP port")
    var eclaTcp: UInt16?

    mutating func run() async throws {
        var config = DtnConfig()
        
        // Load config file if specified
        if let configFile = self.config {
            if FileManager.default.fileExists(atPath: configFile) {
                let data = try Data(contentsOf: URL(fileURLWithPath: configFile))
                config = try JSONDecoder().decode(DtnConfig.self, from: data)
            }
        }
        
        // Override with command line options
        if let nodeid = nodeid {
            config.nodeId = nodeid
        }
        config.workdir = workdir
        config.debug = debug
        
        // Handle IPv4/IPv6 flags
        if ipv4 { config.ipv4 = true; config.ipv6 = false }
        if ipv6 { config.ipv6 = true; config.ipv4 = false }
        
        config.endpoints = endpoint
        config.webPort = webPort
        
        // Parse time intervals
        if let interval = interval {
            config.announcementInterval = parseHumanTime(interval)
        }
        if let janitor = janitor {
            config.janitorInterval = parseHumanTime(janitor)
        }
        config.peerTimeout = parseHumanTime(peerTimeout)
        
        config.routing = routing
        
        // Parse routing options
        var routingSettings: [String: [String: String]] = [:]
        for option in routingOptions {
            let parts = option.split(separator: ".", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0])
                let kvParts = parts[1].split(separator: "=", maxSplits: 1)
                if kvParts.count == 2 {
                    if routingSettings[key] == nil {
                        routingSettings[key] = [:]
                    }
                    routingSettings[key]![String(kvParts[0])] = String(kvParts[1])
                }
            }
        }
        config.routingSettings = routingSettings
        
        // Parse CLA configurations
        var claConfigs: [DtnConfig.CLAConfig] = []
        for claSpec in cla {
            let parts = claSpec.split(separator: ":", maxSplits: 1)
            let claType = String(parts[0])
            var settings: [String: String] = [:]
            
            if parts.count > 1 {
                // Parse CLA-specific settings
                let settingPairs = parts[1].split(separator: ",")
                for pair in settingPairs {
                    let kvParts = pair.split(separator: "=", maxSplits: 1)
                    if kvParts.count == 2 {
                        settings[String(kvParts[0])] = String(kvParts[1])
                    }
                }
            }
            
            // Apply global CLA settings if any
            for globalSetting in global {
                let gParts = globalSetting.split(separator: ".", maxSplits: 1)
                if gParts.count == 2 && String(gParts[0]) == claType {
                    let kvParts = gParts[1].split(separator: "=", maxSplits: 1)
                    if kvParts.count == 2 {
                        settings[String(kvParts[0])] = String(kvParts[1])
                    }
                }
            }
            
            claConfigs.append(DtnConfig.CLAConfig(type: claType, settings: settings))
        }
        config.clas = claConfigs
        
        // Parse static peers
        config.statics = staticPeer.compactMap { DtnPeer.from($0) }
        
        config.enablePeriod = beaconPeriod
        config.disableNeighbourDiscovery = disableNd
        config.db = db
        
        // Parse services
        var services: [UInt8: String] = [:]
        for service in service {
            let parts = service.split(separator: ":", maxSplits: 1)
            if parts.count == 2,
               let tag = UInt8(parts[0]) {
                services[tag] = String(parts[1])
            }
        }
        config.services = services
        
        config.generateStatusReports = generateStatusReports
        config.parallelBundleProcessing = parallelBundleProcessing
        config.unsafeHttpd = unsafeHttpd
        config.eclaEnable = ecla
        if let eclaTcp = eclaTcp {
            config.eclaTcpPort = eclaTcp
        }
        
        print("DTN7 Daemon (dtnd) starting...")
        let daemon = try await Daemon(config: config)
        try await daemon.run()
    }
    
    func parseHumanTime(_ input: String) -> TimeInterval {
        // Parse human time formats like "2s", "3m", "1h"
        let value = input.dropLast()
        let unit = input.last!
        
        guard let number = Double(value) else {
            return 60 // default to 60 seconds
        }
        
        switch unit {
        case "s": return number
        case "m": return number * 60
        case "h": return number * 3600
        case "d": return number * 86400
        default: return number
        }
    }
}