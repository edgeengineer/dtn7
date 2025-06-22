import Testing
@testable import DTN7
import BP7
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@Suite("HTTP Integration Tests", .serialized)
struct HTTPIntegrationTests {
    let testFramework = DTNTestFramework()
    
    /// Kill any leftover processes that might interfere with tests
    private func killLeftoverProcesses() async {
        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        killProcess.arguments = ["pkill", "-f", "dtnd"]
        killProcess.standardOutput = Pipe()
        killProcess.standardError = Pipe()
        
        do {
            try killProcess.run()
            killProcess.waitUntilExit()
        } catch {
            // Ignore errors - process might not exist
        }
        
        // Give time for processes to clean up
        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
    }
    
    @Test(.timeLimit(.minutes(1)))
    func httpEndpointTest() async throws {
        // Clean up any leftover processes
        await killLeftoverProcesses()
        
        // Start daemon with dynamic port allocation instead of hardcoded
        let config = DtnConfig()
        // Don't set webPort, let framework allocate it
        
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