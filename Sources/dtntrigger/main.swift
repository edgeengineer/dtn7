import DTN7
import ArgumentParser
import Foundation
import BP7

@main
struct DtnTrigger: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Trigger an external command on bundle arrival.")
    
    @Option(name: .shortAndLong, help: "Local web port")
    var port: UInt16 = 3000
    
    @Flag(name: [.customShort("6"), .long], help: "Use IPv6")
    var ipv6 = false
    
    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose = false
    
    @Option(name: .shortAndLong, help: "Specify local endpoint")
    var endpoint: String
    
    @Option(name: .shortAndLong, help: "Command to execute for incoming bundles")
    var command: String

    mutating func run() async throws {
        // Check for DTN_WEB_PORT environment variable
        if let envPort = ProcessInfo.processInfo.environment["DTN_WEB_PORT"],
           let portNumber = UInt16(envPort) {
            port = portNumber
        }
        
        print("Setting up trigger on endpoint: \(endpoint)")
        print("Will execute command: \(command)")
        print("Command will receive: param1 = source, param2 = payload file")
        
        if verbose {
            print("Using port: \(port)")
            print("IPv6: \(ipv6)")
        }
        
        let baseURL = "http://\(ipv6 ? "[::1]" : "127.0.0.1"):\(port)"
        
        // First register the endpoint
        let registerUrl = URL(string: "\(baseURL)/register?endpoint=\(endpoint.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? endpoint)")!
        do {
            let (_, response) = try await URLSession.shared.data(from: registerUrl)
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                print("Warning: Failed to register endpoint \(endpoint)")
            } else if verbose {
                print("Successfully registered endpoint: \(endpoint)")
            }
        } catch {
            print("Error registering endpoint: \(error)")
            return
        }
        
        print("Waiting for bundles...")
        
        // Poll for bundles and execute command
        let pollUrl = URL(string: "\(baseURL)/endpoint?endpoint=\(endpoint.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? endpoint)")!
        
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
                            let source = bundle.primary.source.description
                            
                            if verbose {
                                print("\n--- Bundle received ---")
                                print("Bundle ID: \(bundleId)")
                                print("Source: \(source)")
                                print("Executing command: \(command)")
                            }
                            
                            // Extract payload and save to temporary file
                            if let payload = bundle.payload() {
                                let tempDir = FileManager.default.temporaryDirectory
                                let tempFile = tempDir.appendingPathComponent("dtn-trigger-\(UUID().uuidString).dat")
                                
                                try Data(payload).write(to: tempFile)
                                
                                // Execute command with source and payload file as arguments
                                let process = Process()
                                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                                process.arguments = ["-c", "\(command) '\(source)' '\(tempFile.path)'"]
                                
                                if verbose {
                                    print("Executing: \(command) '\(source)' '\(tempFile.path)'")
                                }
                                
                                let outputPipe = Pipe()
                                let errorPipe = Pipe()
                                process.standardOutput = outputPipe
                                process.standardError = errorPipe
                                
                                try process.run()
                                process.waitUntilExit()
                                
                                // Read command output
                                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                                
                                if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                                    print("Command output:")
                                    print(output)
                                }
                                
                                if let error = String(data: errorData, encoding: .utf8), !error.isEmpty {
                                    print("Command error:")
                                    print(error)
                                }
                                
                                if process.terminationStatus != 0 {
                                    print("Command exited with status: \(process.terminationStatus)")
                                }
                                
                                // Clean up temp file
                                try? FileManager.default.removeItem(at: tempFile)
                                
                            } else {
                                print("Warning: Bundle has no payload")
                            }
                        } else {
                            print("Error: Failed to decode bundle")
                        }
                    }
                }
            } catch {
                print("Error: \(error)")
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds on error
            }
        }
    }
} 