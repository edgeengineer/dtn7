#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import DTN7

/// Example echo service application using the DTN client
@main
struct EchoService {
    static func main() async {
        let logger = Logger(label: "EchoService")
        
        // Create DTN client
        let client = DTNClient(
            nodeId: "dtn://node1",
            applicationName: "echo-service",
            useWebSocket: false  // Use HTTP for simplicity
        )
        
        do {
            // Connect to the DTN daemon
            try await client.connect()
            logger.info("Echo service connected to DTN daemon")
            
            // Register the echo service endpoint
            try await client.registerService("echo") { bundle in
                logger.info("Received bundle from \(bundle.source)")
                
                // Extract the message
                if let message = bundle.text {
                    logger.info("Message: \(message)")
                    
                    // Send echo response back to sender
                    let response = "ECHO: \(message)"
                    try? await client.sendText(
                        to: bundle.source,
                        message: response
                    )
                    
                    logger.info("Sent echo response to \(bundle.source)")
                } else {
                    logger.warning("Received bundle with non-text payload")
                }
            }
            
            logger.info("Echo service registered at dtn://node1/echo")
            
            // Keep the service running
            logger.info("Echo service is running. Press Ctrl+C to stop.")
            
            // Wait indefinitely
            try await Task.sleep(nanoseconds: .max)
            
        } catch {
            logger.error("Failed to start echo service: \(error)")
        }
    }
}

// MARK: - Logger Extension

import Logging

extension Logger {
    init(label: String) {
        self.init(label: label) { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .debug
            return handler
        }
    }
}