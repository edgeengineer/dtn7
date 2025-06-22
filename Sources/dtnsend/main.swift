import DTN7
import ArgumentParser
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@main
struct DtnSend: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Send a bundle.")
    
    @Option(name: .shortAndLong, help: "Local web port")
    var port: UInt16 = 3000
    
    @Flag(name: [.customShort("6"), .long], help: "Use IPv6")
    var ipv6 = false
    
    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose = false
    
    @Option(name: .shortAndLong, help: "Sets sender name (e.g. 'dtn://node1')")
    var sender: String?
    
    @Option(name: .shortAndLong, help: "Receiver EID (e.g. 'dtn://node2/incoming')")
    var receiver: String
    
    @Argument(help: "File to send (reads from stdin if omitted)")
    var infile: String?
    
    @Flag(name: [.customShort("D"), .long], help: "Don't actually send, just dump encoded bundle")
    var dryrun = false
    
    @Option(name: .shortAndLong, help: "Bundle lifetime in seconds")
    var lifetime: Int = 3600

    mutating func run() async throws {
        // Check for DTN_WEB_PORT environment variable
        if let envPort = ProcessInfo.processInfo.environment["DTN_WEB_PORT"],
           let portNumber = UInt16(envPort) {
            port = portNumber
        }
        
        let baseURL = "http://\(ipv6 ? "[::1]" : "127.0.0.1"):\(port)"
        
        // Read payload
        var payload: Data
        if let infile = infile {
            payload = try Data(contentsOf: URL(fileURLWithPath: infile))
        } else {
            // Read from stdin
            payload = FileHandle.standardInput.readDataToEndOfFile()
        }
        
        // Get sender from parameter or query daemon for node ID
        var actualSender = sender
        if actualSender == nil {
            // Query daemon for node ID
            let statusUrl = URL(string: "\(baseURL)/status")!
            do {
                let (data, _) = try await URLSession.shared.data(from: statusUrl)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let nodeId = json["nodeId"] as? String {
                    actualSender = nodeId
                }
            } catch {
                print("Warning: Failed to get node ID from daemon, using default")
                actualSender = "dtn://node1/app"
            }
        }
        
        if verbose {
            print("Sender: \(actualSender ?? "unknown")")
            print("Receiver: \(receiver)")
            print("Lifetime: \(lifetime) seconds")
            print("Payload size: \(payload.count) bytes")
        }
        
        if dryrun {
            print("Dry run - would send bundle with payload:")
            if let text = String(data: payload, encoding: .utf8) {
                print(text)
            } else {
                print("Binary data (\(payload.count) bytes)")
            }
        } else {
            // Send the bundle via HTTP API
            var urlComponents = URLComponents(string: "\(baseURL)/send")!
            urlComponents.queryItems = [
                URLQueryItem(name: "dst", value: receiver),
                URLQueryItem(name: "src", value: actualSender),
                URLQueryItem(name: "lifetime", value: String(lifetime * 1000)) // Convert to milliseconds
            ]
            
            var request = URLRequest(url: urlComponents.url!)
            request.httpMethod = "POST"
            request.httpBody = payload
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        if let message = String(data: data, encoding: .utf8) {
                            print(message)
                        } else {
                            print("Bundle sent successfully")
                        }
                    } else {
                        print("Failed to send bundle: HTTP \(httpResponse.statusCode)")
                        if let message = String(data: data, encoding: .utf8) {
                            print(message)
                        }
                    }
                }
            } catch {
                print("Error sending bundle: \(error)")
            }
        }
    }
} 