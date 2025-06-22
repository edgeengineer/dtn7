import Foundation
import ArgumentParser
import DTN7
import BP7
import NIO

struct DTNPing: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dtnping",
        abstract: "A simple Bundle Protocol 7 Ping Tool for Delay Tolerant Networking"
    )
    
    @Option(name: .shortAndLong, help: "Local web port")
    var port: UInt16 = 3000
    
    @Flag(name: .short, help: "Use IPv6")
    var ipv6: Bool = false
    
    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false
    
    @Option(name: .shortAndLong, help: "Destination to ping")
    var destination: String
    
    @Option(name: .shortAndLong, help: "Payload size in bytes")
    var size: Int = 64
    
    @Option(name: .shortAndLong, help: "Number of pings to send (-1 for infinite)")
    var count: Int = -1
    
    @Option(name: .shortAndLong, help: "Timeout to wait for reply in milliseconds")
    var timeout: Int = 5000
    
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
        
        // Get node ID (default)
        let nodeIdStr = "dtn://node1" // Default node ID
        
        // Create DTN client
        let client = DTNClient(
            nodeId: nodeIdStr,
            applicationName: "ping",
            useWebSocket: true,
            host: host,
            port: Int(actualPort)
        )
        
        // Connect client
        try await client.connect()
        
        // Determine endpoint based on scheme
        let endpoint = nodeIdStr.hasPrefix("dtn://") ? "ping" : "7007"
        
        // Register endpoint
        let fullEndpoint = "\(nodeIdStr)/\(endpoint)"
        var receivedBundles: [ReceivedBundle] = []
        
        try await client.registerService(endpoint) { bundle in
            receivedBundles.append(bundle)
        }
        
        if verbose {
            print("[*] Registered endpoint: \(endpoint)")
        }
        
        print("\nPING: \(fullEndpoint) -> \(destination)")
        
        var sequenceNumber: Int = 0
        var successfulPings: Int = 0
        
        while count < 0 || sequenceNumber < count {
            sequenceNumber += 1
            
            // Generate random payload
            let payload = generateRandomPayload(size: size)
            
            print("[>] #\(sequenceNumber) size=\(size)")
            fflush(stdout)
            
            let startTime = Date()
            
            // Clear received bundles
            receivedBundles.removeAll()
            
            // Send ping bundle
            try await client.sendBundle(
                to: destination,
                payload: payload,
                lifetime: 3600 * 24 // 24 hours
            )
            
            // Wait for reply with timeout
            let timeoutNanos = UInt64(timeout) * 1_000_000
            let startNanos = DispatchTime.now().uptimeNanoseconds
            
            var replyReceived = false
            while DispatchTime.now().uptimeNanoseconds - startNanos < timeoutNanos {
                if !receivedBundles.isEmpty {
                    let replyBundle = receivedBundles[0]
                    let elapsed = Date().timeIntervalSince(startTime)
                    print("[<] #\(sequenceNumber) : \(String(format: "%.3f", elapsed * 1000))ms")
                    successfulPings += 1
                    
                    if verbose {
                        print("    Bundle-Id: \(replyBundle.bundleId)")
                        print("    From: \(replyBundle.source)")
                        print("    To: \(replyBundle.destination)")
                        if let payloadStr = replyBundle.text {
                            print("    Data: \(payloadStr)")
                        }
                    }
                    
                    replyReceived = true
                    break
                }
                
                // Small sleep to avoid busy waiting
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            }
            
            if !replyReceived {
                print("[!] *** timeout ***")
            }
            
            // Wait 1 second between pings
            if count < 0 || sequenceNumber < count {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        
        print("\n[*] \(successfulPings) of \(sequenceNumber) pings successful")
        
        if successfulPings < sequenceNumber {
            throw ExitCode(1)
        }
    }
    
    private func generateRandomPayload(size: Int) -> Data {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let randomString = String((0..<size).map { _ in letters.randomElement()! })
        return randomString.data(using: .utf8) ?? Data()
    }
}

// Run the command
DTNPing.main()