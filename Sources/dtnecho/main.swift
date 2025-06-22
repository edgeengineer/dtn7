import Foundation
import ArgumentParser
import DTN7
import BP7
import NIO

struct DTNEcho: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dtnecho",
        abstract: "A simple Bundle Protocol 7 Echo Service for Delay Tolerant Networking"
    )
    
    @Option(name: .shortAndLong, help: "Local web port")
    var port: UInt16 = 3000
    
    @Flag(name: .short, help: "Use IPv6")
    var ipv6: Bool = false
    
    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false
    
    func run() async throws {
        // Get port from environment or command line
        let actualPort: UInt16
        if let envPort = ProcessInfo.processInfo.environment["DTN_WEB_PORT"],
           let parsed = UInt16(envPort) {
            actualPort = parsed
        } else {
            actualPort = port
        }
        
        let host = ipv6 ? "::1" : "127.0.0.1"
        
        // First connect to daemon to get node ID
        let wsInterface = WebSocketApplicationInterface(host: host, port: Int(actualPort))
        try await wsInterface.connect()
        
        // Get node ID from daemon status
        let nodeIdStr = "dtn://node1" // Default, will be replaced if we can get actual node ID
        
        // Create DTN client
        let client = DTNClient(
            nodeId: nodeIdStr,
            applicationName: "echo",
            useWebSocket: true,
            host: host,
            port: Int(actualPort)
        )
        
        // Connect client
        try await client.connect()
        
        // Determine endpoint based on scheme
        let endpoint = nodeIdStr.hasPrefix("dtn://") ? "echo" : "7"
        
        // Register as a service
        try await client.registerService(endpoint) { bundle in
            if verbose {
                print("[<] Received bundle:")
                print("    Bundle-Id: \(bundle.bundleId)")
                print("    From: \(bundle.source)")
                print("    To: \(bundle.destination)")
                if let payloadStr = bundle.text {
                    print("    Data: \(payloadStr)")
                }
            } else {
                print(".", terminator: "")
                fflush(stdout)
            }
            
            // Echo the bundle back
            try? await client.sendBundle(
                to: bundle.source,
                payload: bundle.payload,
                lifetime: 3600 * 24 // 24 hours
            )
            
            if verbose {
                print("[>] Echoed bundle back to: \(bundle.source)")
            }
        }
        
        if verbose {
            print("[*] Registered endpoint: \(endpoint)")
        }
        
        print("[*] Echo service started, listening on endpoint: \(endpoint)")
        if !verbose {
            print("[*] Echoing bundles (. = bundle echoed)")
        }
        
        // Keep running
        try await Task.sleep(nanoseconds: .max)
    }
}

// Run the command
DTNEcho.main()