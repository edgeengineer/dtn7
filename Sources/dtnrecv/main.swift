import DTN7
import ArgumentParser
import Foundation
import BP7

@main
struct DtnRecv: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Receive bundles from a specific endpoint.")
    
    @Option(name: .shortAndLong, help: "Local web port")
    var port: UInt16 = 3000
    
    @Flag(name: [.customShort("6"), .long], help: "Use IPv6")
    var ipv6 = false
    
    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose = false
    
    @Option(name: .shortAndLong, help: "Specify local endpoint to receive from")
    var endpoint: String?
    
    @Option(name: .shortAndLong, help: "Register a local endpoint")
    var register: String?
    
    @Option(name: .shortAndLong, help: "Unregister a local endpoint")
    var unregister: String?
    
    @Option(name: .shortAndLong, help: "Download bundle by ID")
    var bid: String?
    
    @Option(name: .shortAndLong, help: "Delete bundle by ID")
    var delete: String?
    
    @Option(name: .shortAndLong, help: "Write payload to file instead of stdout")
    var outfile: String?
    
    @Flag(name: .shortAndLong, help: "Hex output of whole bundle")
    var hex = false
    
    @Flag(name: .long, help: "Output full bundle in raw bytes")
    var raw = false

    mutating func run() async throws {
        // Check for DTN_WEB_PORT environment variable
        if let envPort = ProcessInfo.processInfo.environment["DTN_WEB_PORT"],
           let portNumber = UInt16(envPort) {
            port = portNumber
        }
        
        let baseURL = "http://\(ipv6 ? "[::1]" : "127.0.0.1"):\(port)"
        
        if let register = register {
            // Register endpoint
            let url = URL(string: "\(baseURL)/register?endpoint=\(register.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? register)")!
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        print("Successfully registered endpoint: \(register)")
                    } else {
                        print("Failed to register endpoint: HTTP \(httpResponse.statusCode)")
                        if let message = String(data: data, encoding: .utf8) {
                            print(message)
                        }
                    }
                }
            } catch {
                print("Error registering endpoint: \(error)")
            }
            
        } else if let unregister = unregister {
            // Unregister endpoint
            let url = URL(string: "\(baseURL)/unregister?endpoint=\(unregister.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? unregister)")!
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        print("Successfully unregistered endpoint: \(unregister)")
                    } else {
                        print("Failed to unregister endpoint: HTTP \(httpResponse.statusCode)")
                        if let message = String(data: data, encoding: .utf8) {
                            print(message)
                        }
                    }
                }
            } catch {
                print("Error unregistering endpoint: \(error)")
            }
            
        } else if let bid = bid {
            // Download bundle by ID
            print("Downloading bundle: \(bid)")
            // Note: Current API doesn't support downloading by bundle ID directly
            // This would need to be added to the daemon API
            print("Error: Bundle download by ID not yet implemented in daemon API")
            
        } else if let delete = delete {
            // Delete bundle by ID  
            print("Deleting bundle: \(delete)")
            // Note: Current API doesn't support deleting by bundle ID
            // This would need to be added to the daemon API
            print("Error: Bundle deletion by ID not yet implemented in daemon API")
            
        } else {
            // Receive bundles from endpoint
            let receiveEndpoint = endpoint ?? "incoming"
            
            if verbose {
                print("Receiving bundles from endpoint: \(receiveEndpoint)")
                print("Connecting to daemon at \(baseURL)")
            }
            
            // First register the endpoint
            let registerUrl = URL(string: "\(baseURL)/register?endpoint=\(receiveEndpoint.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? receiveEndpoint)")!
            do {
                let (_, response) = try await URLSession.shared.data(from: registerUrl)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                    print("Warning: Failed to register endpoint \(receiveEndpoint)")
                }
            } catch {
                print("Warning: Failed to register endpoint: \(error)")
            }
            
            print("Waiting to receive bundles...")
            
            // Poll for bundles
            let pollUrl = URL(string: "\(baseURL)/endpoint?endpoint=\(receiveEndpoint.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? receiveEndpoint)")!
            
            while true {
                do {
                    let (data, _) = try await URLSession.shared.data(from: pollUrl)
                    
                    if let responseStr = String(data: data, encoding: .utf8) {
                        if responseStr == "Nothing to receive" {
                            // No bundle available, wait and retry
                            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                            continue
                        }
                        
                        // Bundle received as base64 CBOR
                        if let bundleData = Data(base64Encoded: responseStr) {
                            // Decode the bundle
                            if let bundle = try? BP7.Bundle.decode(from: Array(bundleData)) {
                                let bundleId = BundlePack(from: bundle).id
                                
                                if verbose {
                                    print("\n--- Bundle received ---")
                                    print("Bundle ID: \(bundleId)")
                                    print("Source: \(bundle.primary.source)")
                                    print("Destination: \(bundle.primary.destination)")
                                    print("Creation time: \(Date(timeIntervalSince1970: Double(bundle.primary.creationTimestamp.getDtnTime()) / 1000.0))")
                                }
                                
                                // Handle output
                                if let payload = bundle.payload() {
                                    let payloadData = Data(payload)
                                    
                                    if hex {
                                        // Hex output of whole bundle
                                        print(bundleData.map { String(format: "%02x", $0) }.joined())
                                    } else if raw {
                                        // Raw bundle output
                                        if let outfile = outfile {
                                            try bundleData.write(to: URL(fileURLWithPath: outfile))
                                            print("Bundle written to: \(outfile)")
                                        } else {
                                            FileHandle.standardOutput.write(bundleData)
                                        }
                                    } else {
                                        // Payload output
                                        if let outfile = outfile {
                                            try payloadData.write(to: URL(fileURLWithPath: outfile))
                                            print("Payload written to: \(outfile)")
                                        } else {
                                            FileHandle.standardOutput.write(payloadData)
                                            print() // Add newline after payload
                                        }
                                    }
                                }
                            } else {
                                print("Error: Failed to decode bundle")
                            }
                        }
                    }
                } catch {
                    print("Error receiving bundle: \(error)")
                    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds on error
                }
            }
        }
    }
} 