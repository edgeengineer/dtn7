# Build stage
FROM swift:6.0-jammy AS builder

WORKDIR /build

# Copy package files
COPY Package.swift Package.resolved ./
COPY Sources ./Sources

# Build in release mode
RUN swift build -c release

# Runtime stage
FROM swift:6.0-jammy-slim

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    libsqlite3-0 \
    curl \
    iproute2 \
    iputils-ping \
    tcpdump \
    netcat \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy built binaries
COPY --from=builder /build/.build/release/dtnd /usr/local/bin/
COPY --from=builder /build/.build/release/dtnsend /usr/local/bin/
COPY --from=builder /build/.build/release/dtnrecv /usr/local/bin/
COPY --from=builder /build/.build/release/dtnquery /usr/local/bin/
COPY --from=builder /build/.build/release/dtntrigger /usr/local/bin/

# Create data directory
RUN mkdir -p /data

# Default configuration
ENV DTN_NODE_ID="dtn://node1"
ENV DTN_WEB_PORT="3000"
ENV DTN_WORKDIR="/data"

# Health check
HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:${DTN_WEB_PORT}/status || exit 1

# Expose ports
EXPOSE 3000 4556

# Run daemon
CMD ["dtnd", "--nodeid", "${DTN_NODE_ID}", "--webPort", "${DTN_WEB_PORT}", "--workdir", "${DTN_WORKDIR}"]