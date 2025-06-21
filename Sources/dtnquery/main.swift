import DTN7
import ArgumentParser
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct DtnQuery: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Query tool for dtn7 daemon",
        subcommands: [Eids.self, Peers.self, Bundles.self, Store.self, Info.self, NodeId.self])
    
    @Option(name: .shortAndLong, help: "Local web port")
    var port: UInt16 = 3000
    
    @Flag(name: [.customShort("6"), .long], help: "Use IPv6")
    var ipv6 = false
}

extension DtnQuery {
    struct Eids: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List registered endpoint IDs")
        
        @OptionGroup var parent: DtnQuery
        
        mutating func run() async throws {
            let baseURL = "http://\(parent.ipv6 ? "[::1]" : "127.0.0.1"):\(parent.port)"
            
            do {
                let url = URL(string: "\(baseURL)/status")!
                let (data, _) = try await URLSession.shared.data(from: url)
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let nodeId = json["nodeId"] as? String {
                    print("Registered endpoints for node: \(nodeId)")
                    // Note: The current API doesn't expose registered endpoints separately
                    // This would need to be added to the daemon API
                    print("- \(nodeId)")
                }
            } catch {
                print("Error: Failed to connect to daemon at \(baseURL)")
                print("Make sure dtnd is running on port \(parent.port)")
            }
        }
    }
    
    struct Peers: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List known peers")
        
        @OptionGroup var parent: DtnQuery
        
        mutating func run() async throws {
            let baseURL = "http://\(parent.ipv6 ? "[::1]" : "127.0.0.1"):\(parent.port)"
            
            do {
                let url = URL(string: "\(baseURL)/peers")!
                let (data, _) = try await URLSession.shared.data(from: url)
                
                if let jsonString = String(data: data, encoding: .utf8) {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let count = json["count"] as? Int,
                       let peers = json["peers"] as? [[String: Any]] {
                        print("Known peers (\(count)):")
                        for peer in peers {
                            if let eid = peer["eid"] as? String,
                               let type = peer["type"] as? String {
                                print("- \(eid) [\(type)]")
                            }
                        }
                    } else {
                        // Fallback to plain text response
                        print(jsonString)
                    }
                }
            } catch {
                print("Error: Failed to connect to daemon at \(baseURL)")
                print("Make sure dtnd is running on port \(parent.port)")
            }
        }
    }
    
    struct Bundles: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List bundles")
        
        @OptionGroup var parent: DtnQuery
        
        @Flag(name: .shortAndLong, help: "Include bundle destination")
        var verbose = false
        
        @Flag(name: .shortAndLong, help: "Just print hash digest")
        var digest = false
        
        @Option(name: .shortAndLong, help: "Filter by address")
        var addr: String?
        
        mutating func run() async throws {
            let baseURL = "http://\(parent.ipv6 ? "[::1]" : "127.0.0.1"):\(parent.port)"
            
            do {
                let url = URL(string: "\(baseURL)/bundles")!
                let (data, _) = try await URLSession.shared.data(from: url)
                
                if let jsonString = String(data: data, encoding: .utf8) {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let count = json["count"] as? Int,
                       let bundles = json["bundles"] as? [String] {
                        // Filter bundles if address filter is provided
                        var filteredBundles = bundles
                        if let addr = addr {
                            filteredBundles = bundles.filter { bundleId in
                                // Bundle IDs typically contain source endpoint
                                bundleId.contains(addr)
                            }
                        }
                        
                        if let addr = addr {
                            print("Bundles in store matching '\(addr)' (\(filteredBundles.count) of \(count)):")
                        } else {
                            print("Bundles in store (\(count)):")
                        }
                        
                        for bundleId in filteredBundles {
                            if digest {
                                // Extract just the hash part
                                if let hashRange = bundleId.range(of: "-") {
                                    let hash = String(bundleId[bundleId.index(after: hashRange.lowerBound)...])
                                    print(hash)
                                } else {
                                    print(bundleId)
                                }
                            } else if verbose {
                                // Note: Current API only returns bundle IDs, not full details
                                // Bundle ID format is typically: <source>-<timestamp>-<sequence>
                                let components = bundleId.split(separator: "-")
                                if components.count >= 3 {
                                    print("- \(bundleId)")
                                    print("  Source: \(components[0])")
                                    if let timestamp = UInt64(components[1]) {
                                        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
                                        print("  Created: \(date)")
                                    }
                                } else {
                                    print("- \(bundleId)")
                                }
                            } else {
                                print("- \(bundleId)")
                            }
                        }
                    } else {
                        // Fallback to plain text response
                        print(jsonString)
                    }
                }
            } catch {
                print("Error: Failed to connect to daemon at \(baseURL)")
                print("Make sure dtnd is running on port \(parent.port)")
            }
        }
    }
    
    struct Store: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List bundle status in store")
        
        @OptionGroup var parent: DtnQuery
        
        mutating func run() async throws {
            let baseURL = "http://\(parent.ipv6 ? "[::1]" : "127.0.0.1"):\(parent.port)"
            
            do {
                let url = URL(string: "\(baseURL)/bundles")!
                let (data, _) = try await URLSession.shared.data(from: url)
                
                if let jsonString = String(data: data, encoding: .utf8) {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let count = json["count"] as? Int,
                       let bundles = json["bundles"] as? [String] {
                        print("Bundle store status:")
                        print("Total bundles: \(count)")
                        print("\nBundle IDs:")
                        for bundleId in bundles {
                            print("  \(bundleId)")
                        }
                    } else {
                        // Fallback to plain text response
                        print(jsonString)
                    }
                }
            } catch {
                print("Error: Failed to connect to daemon at \(baseURL)")
                print("Make sure dtnd is running on port \(parent.port)")
            }
        }
    }
    
    struct Info: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "General dtnd info")
        
        @OptionGroup var parent: DtnQuery
        
        mutating func run() async throws {
            let baseURL = "http://\(parent.ipv6 ? "[::1]" : "127.0.0.1"):\(parent.port)"
            
            do {
                let url = URL(string: "\(baseURL)/status")!
                let (data, _) = try await URLSession.shared.data(from: url)
                
                if let jsonString = String(data: data, encoding: .utf8) {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        print("DTN Daemon Information:")
                        print("======================")
                        if let nodeId = json["nodeId"] as? String {
                            print("Node ID: \(nodeId)")
                        }
                        if let version = json["version"] as? String {
                            print("Version: \(version)")
                        }
                        if let uptime = json["uptime"] as? Double {
                            let hours = Int(uptime) / 3600
                            let minutes = (Int(uptime) % 3600) / 60
                            let seconds = Int(uptime) % 60
                            print("Uptime: \(hours)h \(minutes)m \(seconds)s")
                        }
                        if let stats = json["statistics"] as? [String: Any] {
                            print("\nStatistics:")
                            if let incoming = stats["incoming"] as? Int {
                                print("  Incoming bundles: \(incoming)")
                            }
                            if let outgoing = stats["outgoing"] as? Int {
                                print("  Outgoing bundles: \(outgoing)")
                            }
                            if let delivered = stats["delivered"] as? Int {
                                print("  Delivered bundles: \(delivered)")
                            }
                            if let stored = stats["stored"] as? Int {
                                print("  Stored bundles: \(stored)")
                            }
                        }
                    } else {
                        // Fallback to plain text response
                        print(jsonString)
                    }
                }
            } catch {
                print("Error: Failed to connect to daemon at \(baseURL)")
                print("Make sure dtnd is running on port \(parent.port)")
            }
        }
    }
    
    struct NodeId: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Local node ID")
        
        @OptionGroup var parent: DtnQuery
        
        mutating func run() async throws {
            let baseURL = "http://\(parent.ipv6 ? "[::1]" : "127.0.0.1"):\(parent.port)"
            
            do {
                let url = URL(string: "\(baseURL)/status")!
                let (data, _) = try await URLSession.shared.data(from: url)
                
                if let jsonString = String(data: data, encoding: .utf8) {
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let nodeId = json["nodeId"] as? String {
                        print(nodeId)
                    } else {
                        // Fallback to plain text response
                        print(jsonString)
                    }
                }
            } catch {
                print("Error: Failed to connect to daemon at \(baseURL)")
                print("Make sure dtnd is running on port \(parent.port)")
            }
        }
    }
} 