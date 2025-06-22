import Testing
@testable import DTN7
import BP7
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite("HTTP Integration Tests")
struct HTTPIntegrationTests {
    let testFramework = DTNTestFramework()
    
    @Test("HTTP Endpoint Test")
    func httpEndpointTest() async throws {
        // Start daemon with specific port
        var config = DtnConfig()
        config.webPort = 9999
        
        let daemon = try await testFramework.startDaemon(nodeId: "dtn://httptest", config: config)
        defer {
            Task { @Sendable in
                try? await testFramework.stopDaemon(daemon)
            }
        }
        
        print("Daemon started on port \(daemon.config.webPort)")
        
        // Test the /test endpoint
        let testUrl = URL(string: "http://localhost:\(daemon.config.webPort)/test")!
        let (data, response) = try await URLSession.shared.data(from: testUrl)
        
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(String(data: data, encoding: .utf8) == "Test route working")
        
        print("HTTP test endpoint working correctly")
    }
}