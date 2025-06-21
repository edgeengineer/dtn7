import Foundation
import BP7
import CBOR
import AsyncAlgorithms
import NIOCore
import NIOWebSocket
import NIOHTTP1
import NIOPosix
import Logging

/// WebSocket-based implementation of the ApplicationInterface
public actor WebSocketApplicationInterface: ApplicationInterface {
    private let logger = Logger(label: "WebSocketApplicationInterface")
    
    // Connection details
    private let host: String
    private let port: Int
    private let mode: TransmissionMode
    
    // Connection state
    private var eventLoopGroup: EventLoopGroup?
    private var channel: Channel?
    private var webSocketHandler: WebSocketHandler?
    private var connected = false
    
    // Registered endpoints
    private var registeredEndpoints: Set<String> = []
    
    // Incoming bundles channel
    public let incomingBundles = AsyncChannel<ReceivedBundle>()
    
    // Heartbeat
    private var heartbeatTask: Task<Void, Never>?
    private let heartbeatInterval: TimeInterval = 5.0
    private let heartbeatTimeout: TimeInterval = 30.0
    
    public init(host: String = "localhost", port: Int = 3000, mode: TransmissionMode = .data) {
        self.host = host
        self.port = port
        self.mode = mode
    }
    
    deinit {
        heartbeatTask?.cancel()
    }
    
    // MARK: - ApplicationInterface
    
    public var isConnected: Bool {
        return connected
    }
    
    public func connect() async throws {
        guard !connected else { return }
        
        logger.info("Connecting to DTN daemon at \(host):\(port)")
        
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        
        let bootstrap = ClientBootstrap(group: eventLoopGroup!)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                let httpHandler = HTTPInitialRequestHandler(host: self.host)
                let websocketUpgrader = NIOWebSocketClientUpgrader(
                    requestKey: Self.generateWebSocketKey(),
                    upgradePipelineHandler: { channel, _ in
                        self.setupWebSocketPipeline(channel: channel)
                    }
                )
                
                let config: NIOHTTPClientUpgradeConfiguration = (
                    upgraders: [websocketUpgrader],
                    completionHandler: { _ in
                        channel.pipeline.removeHandler(httpHandler, promise: nil)
                    }
                )
                
                return channel.pipeline.addHTTPClientHandlers(withClientUpgrade: config).flatMap {
                    channel.pipeline.addHandler(httpHandler)
                }
            }
        
        do {
            channel = try await bootstrap.connect(host: host, port: port).get()
            connected = true
            
            // Send initial mode command
            try await sendTextMessage(mode.rawValue)
            
            // Start heartbeat
            startHeartbeat()
            
            logger.info("Connected to DTN daemon")
        } catch {
            logger.error("Failed to connect: \(error)")
            throw ApplicationInterfaceError.connectionFailed(error.localizedDescription)
        }
    }
    
    public func disconnect() async {
        logger.info("Disconnecting from DTN daemon")
        
        heartbeatTask?.cancel()
        heartbeatTask = nil
        
        if let channel = channel {
            try? await channel.close().get()
        }
        
        if let group = eventLoopGroup {
            try? await group.shutdownGracefully()
        }
        
        channel = nil
        eventLoopGroup = nil
        webSocketHandler = nil
        connected = false
        registeredEndpoints.removeAll()
    }
    
    public func registerEndpoint(_ endpoint: String) async throws {
        guard connected else {
            throw ApplicationInterfaceError.notConnected
        }
        
        // Validate endpoint
        guard let _ = try? EndpointID.from(endpoint) else {
            throw ApplicationInterfaceError.invalidEndpoint(endpoint)
        }
        
        // Send subscribe command
        let command = "/subscribe \(endpoint)"
        try await sendTextMessage(command)
        
        registeredEndpoints.insert(endpoint)
        logger.info("Registered endpoint: \(endpoint)")
    }
    
    public func unregisterEndpoint(_ endpoint: String) async throws {
        guard connected else {
            throw ApplicationInterfaceError.notConnected
        }
        
        // Send unsubscribe command
        let command = "/unsubscribe \(endpoint)"
        try await sendTextMessage(command)
        
        registeredEndpoints.remove(endpoint)
        logger.info("Unregistered endpoint: \(endpoint)")
    }
    
    public func sendBundle(from source: String, to destination: String, payload: Data, lifetime: TimeInterval, deliveryNotification: Bool) async throws {
        guard connected else {
            throw ApplicationInterfaceError.notConnected
        }
        
        let sendRequest = BundleSendRequest(
            source: source,
            destination: destination,
            deliveryNotification: deliveryNotification,
            lifetime: lifetime,
            data: payload
        )
        
        switch mode {
        case .data:
            // Send as CBOR
            let encoder = CBOREncoder()
            let data = try encoder.encode(sendRequest)
            try await sendBinaryMessage(Data(data))
            
        case .json:
            // Send as JSON with base64 encoded data
            var jsonDict: [String: Any] = [
                "src": sendRequest.src,
                "dst": sendRequest.dst,
                "delivery_notification": sendRequest.delivery_notification,
                "lifetime": sendRequest.lifetime,
                "data": sendRequest.data.base64EncodedString()
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: jsonDict)
            try await sendBinaryMessage(jsonData)
            
        case .bundle:
            // Create and send raw bundle
            throw ApplicationInterfaceError.protocolError("Bundle mode not yet implemented")
        }
        
        logger.debug("Sent bundle from \(source) to \(destination)")
    }
    
    // MARK: - Private Methods
    
    private func setupWebSocketPipeline(channel: Channel) -> EventLoopFuture<Void> {
        let handler = WebSocketHandler { [weak self] in
            await self?.handleWebSocketFrame($0)
        }
        self.webSocketHandler = handler
        
        return channel.pipeline.addHandler(handler)
    }
    
    private func handleWebSocketFrame(_ frame: WebSocketFrame) async {
        switch frame.opcode {
        case .text:
            var buffer = frame.unmaskedData
            if let text = buffer.readString(length: buffer.readableBytes) {
                await handleTextMessage(text)
            }
            
        case .binary:
            var buffer = frame.unmaskedData
            if let data = buffer.readData(length: buffer.readableBytes) {
                await handleBinaryMessage(data)
            }
            
        case .pong:
            logger.trace("Received pong")
            
        case .ping:
            // Respond with pong
            if let handler = webSocketHandler {
                var buffer = channel!.allocator.buffer(capacity: 0)
                let pongFrame = WebSocketFrame(fin: true, opcode: .pong, data: buffer)
                channel?.writeAndFlush(pongFrame, promise: nil)
            }
            
        case .connectionClose:
            logger.warning("WebSocket connection closed by server")
            await handleDisconnection()
            
        default:
            break
        }
    }
    
    private func handleTextMessage(_ text: String) async {
        logger.debug("Received text message: \(text)")
        
        // Handle server responses
        if text.hasPrefix("Subscribed to ") {
            logger.info("\(text)")
        } else if text.hasPrefix("Unsubscribed from ") {
            logger.info("\(text)")
        } else if text.hasPrefix("Error:") {
            logger.error("Server error: \(text)")
        }
    }
    
    private func handleBinaryMessage(_ data: Data) async {
        do {
            switch mode {
            case .data:
                // Decode CBOR
                let decoder = CBORDecoder()
                let recvData = try decoder.decode(WsRecvData.self, from: Array(data))
                
                let bundle = ReceivedBundle(
                    bundleId: recvData.bid,
                    source: recvData.src,
                    destination: recvData.dst,
                    creationTimestamp: Date(timeIntervalSince1970: Double(recvData.cts) / 1000.0),
                    lifetime: TimeInterval(recvData.lifetime) / 1000.0,
                    payload: recvData.data
                )
                
                await incomingBundles.send(bundle)
                
            case .json:
                // Decode JSON
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let bid = json["bid"] as? String,
                   let src = json["src"] as? String,
                   let dst = json["dst"] as? String,
                   let cts = json["cts"] as? UInt64,
                   let lifetime = json["lifetime"] as? UInt64,
                   let dataStr = json["data"] as? String,
                   let payload = Data(base64Encoded: dataStr) {
                    
                    let bundle = ReceivedBundle(
                        bundleId: bid,
                        source: src,
                        destination: dst,
                        creationTimestamp: Date(timeIntervalSince1970: Double(cts) / 1000.0),
                        lifetime: TimeInterval(lifetime) / 1000.0,
                        payload: payload
                    )
                    
                    await incomingBundles.send(bundle)
                }
                
            case .bundle:
                // Decode raw bundle
                throw ApplicationInterfaceError.protocolError("Bundle mode not yet implemented")
            }
        } catch {
            logger.error("Failed to decode incoming bundle: \(error)")
        }
    }
    
    private func sendTextMessage(_ text: String) async throws {
        guard let handler = webSocketHandler else {
            throw ApplicationInterfaceError.notConnected
        }
        
        var buffer = channel!.allocator.buffer(capacity: text.count)
        buffer.writeString(text)
        
        let frame = WebSocketFrame(fin: true, opcode: .text, data: buffer)
        try await channel!.writeAndFlush(frame).get()
    }
    
    private func sendBinaryMessage(_ data: Data) async throws {
        guard let handler = webSocketHandler else {
            throw ApplicationInterfaceError.notConnected
        }
        
        var buffer = channel!.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        
        let frame = WebSocketFrame(fin: true, opcode: .binary, data: buffer)
        try await channel!.writeAndFlush(frame).get()
    }
    
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        
        heartbeatTask = Task {
            while !Task.isCancelled && connected {
                do {
                    // Send ping
                    if let channel = channel {
                        var buffer = channel.allocator.buffer(capacity: 0)
                        let pingFrame = WebSocketFrame(fin: true, opcode: .ping, data: buffer)
                        channel.writeAndFlush(pingFrame, promise: nil)
                    }
                    
                    try await Task.sleep(nanoseconds: UInt64(heartbeatInterval * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }
    
    private func handleDisconnection() async {
        connected = false
        logger.warning("Disconnected from DTN daemon")
        
        // Attempt reconnection
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            if !connected {
                try? await connect()
                
                // Re-register endpoints
                for endpoint in registeredEndpoints {
                    try? await registerEndpoint(endpoint)
                }
            }
        }
    }
    
    private static func generateWebSocketKey() -> String {
        // Generate random 16-byte key and base64 encode it
        var keyData = Data(count: 16)
        keyData.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress else { return }
            _ = SecRandomCopyBytes(kSecRandomDefault, 16, baseAddress)
        }
        return keyData.base64EncodedString()
    }
}

// MARK: - Helper Classes

/// WebSocket handler for NIO
private final class WebSocketHandler: ChannelInboundHandler {
    typealias InboundIn = WebSocketFrame
    typealias OutboundOut = WebSocketFrame
    
    private let frameHandler: (WebSocketFrame) async -> Void
    
    init(frameHandler: @escaping (WebSocketFrame) async -> Void) {
        self.frameHandler = frameHandler
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let frame = unwrapInboundIn(data)
        Task {
            await frameHandler(frame)
        }
    }
}

/// HTTP request handler for WebSocket upgrade
private final class HTTPInitialRequestHandler: ChannelInboundHandler, RemovableChannelHandler {
    typealias InboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPClientRequestPart
    
    private let host: String
    
    init(host: String) {
        self.host = host
    }
    
    func channelActive(context: ChannelHandlerContext) {
        // Send WebSocket upgrade request
        var headers = HTTPHeaders()
        headers.add(name: "Host", value: host)
        headers.add(name: "Upgrade", value: "websocket")
        headers.add(name: "Connection", value: "Upgrade")
        headers.add(name: "Sec-WebSocket-Version", value: "13")
        
        let requestHead = HTTPRequestHead(
            version: .http1_1,
            method: .GET,
            uri: "/ws",
            headers: headers
        )
        
        context.write(wrapOutboundOut(.head(requestHead)), promise: nil)
        context.write(wrapOutboundOut(.end(nil)), promise: nil)
        context.flush()
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        // WebSocket upgrade handler will handle the response
    }
}