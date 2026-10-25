import Foundation
import Network
import os

/// Discovery service for finding DRU bridges on the local network
actor DRUDiscovery {

    // MARK: - Types

    /// Thread-safe flag for connection state tracking
    private final class ConnectionFlag: @unchecked Sendable {
        private let lock = OSAllocatedUnfairLock(initialState: false)

        var hasResumed: Bool {
            get { lock.withLock { $0 } }
            set { lock.withLock { $0 = newValue } }
        }

        func setTrueIfFalse() -> Bool {
            lock.withLock { current in
                if !current {
                    current = true
                    return true
                }
                return false
            }
        }
    }

    /// A discovered bridge on the network
    struct DiscoveredBridge: Identifiable, Sendable {
        let id: String
        let ipAddress: String
        let port: UInt16
        let responseTime: TimeInterval

        init(ipAddress: String, port: UInt16 = 502, responseTime: TimeInterval = 0) {
            self.id = ipAddress
            self.ipAddress = ipAddress
            self.port = port
            self.responseTime = responseTime
        }
    }

    /// Discovery progress update
    enum DiscoveryProgress: Sendable {
        case started
        case scanning(progress: Double, currentIP: String)
        case found(DiscoveredBridge)
        case completed([DiscoveredBridge])
        case failed(Error)
    }

    // MARK: - Properties

    private var isScanning = false
    private let logger = Logger(subsystem: "com.fyr.app", category: "Discovery")

    /// Serial queue for NWConnection - CRITICAL: must be serial, not concurrent
    private let networkQueue = DispatchQueue(label: "com.fyr.discovery.network", qos: .userInitiated)

    /// Number of IPs to scan concurrently
    /// Note: DRU bridge only allows ONE connection at a time, so we scan in very small batches
    /// Larger batches cause connection failures due to bridge limitations
    private let concurrentScans = 3

    /// Connection timeout in seconds
    /// DRU bridge can be slow to respond, needs longer timeout
    private let connectionTimeout: TimeInterval = 2.5

    /// Delay after finding bridge to let it recover before main connection
    /// DRU bridge needs significant recovery time after connection attempts
    private let postScanDelay: TimeInterval = 2.0

    // MARK: - Public Methods

    /// Scan the local network for Modbus TCP devices on port 502
    /// - Parameters:
    ///   - progressHandler: Handler for progress updates
    ///   - stopOnFirstFound: If true, stops scanning after finding the first bridge
    /// - Returns: Array of discovered bridges
    func scanNetwork(
        stopOnFirstFound: Bool = true,
        progressHandler: (@Sendable (DiscoveryProgress) -> Void)? = nil
    ) async -> [DiscoveredBridge] {
        guard !isScanning else { return [] }
        isScanning = true

        logger.info("Starting network scan")

        progressHandler?(.started)

        var discovered: [DiscoveredBridge] = []

        // Get the local network range first
        guard let baseIP = getLocalNetworkBase() else {
            isScanning = false
            logger.error("No network access - could not determine local IP range")
            progressHandler?(.failed(DiscoveryError.noNetworkAccess))
            return []
        }

        logger.info("Network base: \(baseIP)")

        // CRITICAL: Trigger local network permission by making a test connection
        // iOS shows the permission prompt when the first network connection is attempted
        // We need to wait for the user to grant permission before starting the actual scan
        logger.info("Triggering local network permission prompt...")
        let permissionGranted = await triggerNetworkPermission(baseIP: baseIP)

        if !permissionGranted {
            // Wait and retry - user may have just granted permission
            logger.warning("Initial permission check failed, waiting for user to grant permission...")
            try? await Task.sleep(for: .seconds(2))

            // Try again after user has had time to grant permission
            let retryGranted = await triggerNetworkPermission(baseIP: baseIP)
            if !retryGranted {
                isScanning = false
                logger.error("Local network permission not granted")
                progressHandler?(.failed(DiscoveryError.noNetworkAccess))
                return []
            }
        }

        logger.info("Network permission granted, proceeding with scan")

        logger.info("Scanning network range: \(baseIP).1-254")

        // Generate all IPs to scan
        let allIPs = (1...254).map { "\(baseIP).\($0)" }
        var scannedCount = 0
        var shouldStop = false

        // Process in batches for parallel scanning
        for batchStart in stride(from: 0, to: allIPs.count, by: concurrentScans) {
            // Check for cancellation at each batch
            if Task.isCancelled {
                logger.info("Scan cancelled by user")
                isScanning = false
                return discovered
            }

            if shouldStop { break }

            let batchEnd = min(batchStart + concurrentScans, allIPs.count)
            let batch = Array(allIPs[batchStart..<batchEnd])

            // Scan batch in parallel
            let results = await withTaskGroup(of: DiscoveredBridge?.self) { group in
                for ip in batch {
                    group.addTask {
                        // Check cancellation before starting each connection
                        guard !Task.isCancelled else { return nil }
                        return await self.testConnection(ip: ip)
                    }
                }

                var batchResults: [DiscoveredBridge] = []
                for await result in group {
                    if let bridge = result {
                        batchResults.append(bridge)
                    }
                }
                return batchResults
            }

            // Check for cancellation after batch completes
            if Task.isCancelled {
                logger.info("Scan cancelled by user")
                isScanning = false
                return discovered
            }

            // Process results
            for bridge in results {
                discovered.append(bridge)
                logger.info("Found bridge at \(bridge.ipAddress) (response: \(String(format: "%.0fms", bridge.responseTime * 1000)))")
                progressHandler?(.found(bridge))

                if stopOnFirstFound {
                    shouldStop = true
                    break
                }
            }

            // Update progress
            scannedCount += batch.count
            let progress = Double(scannedCount) / 254.0
            let lastIP = batch.last ?? ""
            progressHandler?(.scanning(progress: progress, currentIP: lastIP))
        }

        isScanning = false
        logger.info("Scan complete. Found \(discovered.count) bridge(s)")

        // Add delay after scan to let bridge recover before main connection attempt
        // DRU bridge only allows one connection at a time
        if !discovered.isEmpty {
            logger.debug("Waiting \(self.postScanDelay)s for bridge to recover...")
            try? await Task.sleep(for: .seconds(postScanDelay))
        }

        progressHandler?(.completed(discovered))
        return discovered
    }

    /// Test connection to a specific IP address
    /// - Parameter ip: IP address to test
    /// - Returns: DiscoveredBridge if connection successful, nil otherwise
    func testConnection(ip: String) async -> DiscoveredBridge? {
        let startTime = Date()

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(ip),
            port: NWEndpoint.Port(rawValue: DRUConstants.modbusPort)!
        )

        let parameters = NWParameters.tcp
        parameters.serviceClass = .responsiveData

        let connection = NWConnection(to: endpoint, using: parameters)
        let flag = ConnectionFlag()

        let success = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            connection.stateUpdateHandler = { [logger] (state: NWConnection.State) in
                switch state {
                case .ready:
                    if flag.setTrueIfFalse() {
                        // Clear handler before resuming to prevent further callbacks
                        connection.stateUpdateHandler = nil
                        continuation.resume(returning: true)
                    }
                case .failed, .cancelled:
                    if flag.setTrueIfFalse() {
                        connection.stateUpdateHandler = nil
                        continuation.resume(returning: false)
                    }
                case .waiting(let error):
                    // Connection waiting (likely no route), treat as failure
                    logger.debug("Connection to \(ip) waiting: \(error.localizedDescription)")
                    if flag.setTrueIfFalse() {
                        connection.stateUpdateHandler = nil
                        connection.cancel()
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }

            // CRITICAL: Use serial queue, not global concurrent queue
            connection.start(queue: networkQueue)

            // Short timeout for quick scanning
            Task {
                try? await Task.sleep(for: .seconds(connectionTimeout))
                if flag.setTrueIfFalse() {
                    connection.stateUpdateHandler = nil
                    connection.cancel()
                    continuation.resume(returning: false)
                }
            }
        }

        // Cancel connection after we're done (cleanup for successful connections)
        // Clear handler first to prevent "is already cancelled" warnings
        connection.stateUpdateHandler = nil
        connection.cancel()

        if success {
            let responseTime = Date().timeIntervalSince(startTime)
            return DiscoveredBridge(ipAddress: ip, responseTime: responseTime)
        }

        return nil
    }

    /// Validate an IP address format
    /// - Parameter ip: IP address string to validate
    /// - Returns: True if valid IPv4 address
    func isValidIPAddress(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }

        for part in parts {
            guard let num = Int(part), num >= 0, num <= 255 else {
                return false
            }
        }

        return true
    }

    /// Verify a manually entered IP address has a Modbus device
    /// - Parameter ip: IP address to test
    /// - Returns: DiscoveredBridge if connection successful, nil otherwise
    func verifyManualIP(_ ip: String) async -> DiscoveredBridge? {
        guard isValidIPAddress(ip) else {
            logger.error("Invalid IP address format: \(ip)")
            return nil
        }

        logger.info("Testing manual IP: \(ip)")

        // First ensure we have network permission
        let baseIP = ip.split(separator: ".").dropLast().joined(separator: ".")
        let hasPermission = await triggerNetworkPermission(baseIP: baseIP)

        if !hasPermission {
            logger.warning("Cannot verify IP - no network permission")
            return nil
        }

        return await testConnection(ip: ip)
    }

    // MARK: - Private Methods

    /// Request and wait for local network permission
    ///
    /// Key insight: NWConnection doesn't automatically retry when permission is granted.
    /// It stays stuck in error 50 state. We must periodically create NEW connections
    /// to detect when permission has been granted.
    ///
    /// Strategy:
    /// 1. First connection triggers the iOS permission dialog (error 50)
    /// 2. Poll with new connections every second to detect when permission is granted
    /// 3. Permission granted = new connection gets error 65 (no route) instead of error 50
    private func triggerNetworkPermission(baseIP: String) async -> Bool {
        logger.info("Requesting local network permission...")

        // Use a non-gateway IP to properly trigger iOS permission dialog
        let testIP = "\(baseIP).254"

        // First, trigger the permission dialog
        let dialogTriggered = await triggerPermissionDialog(testIP: testIP)

        if !dialogTriggered {
            // No error 50 means permission might already be granted
            logger.info("No permission dialog needed - already granted")
            return true
        }

        // Permission dialog was shown (error 50), now poll until permission is granted
        logger.info("Permission dialog shown - polling for user response...")

        // Poll every 0.5 seconds for up to 60 seconds
        for _ in 0..<120 {
            try? await Task.sleep(for: .milliseconds(500))

            let granted = await checkPermissionGranted(testIP: testIP)
            if granted {
                logger.info("Permission granted by user")
                return true
            }
        }

        logger.warning("Permission check timed out - user did not grant permission")
        return false
    }

    /// Trigger the iOS permission dialog by making a connection
    /// Returns true if dialog was triggered (error 50), false if already granted
    private func triggerPermissionDialog(testIP: String) async -> Bool {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(testIP),
            port: NWEndpoint.Port(rawValue: 502)!
        )

        let connection = NWConnection(to: endpoint, using: .tcp)
        let flag = ConnectionFlag()

        let sawError50 = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            connection.stateUpdateHandler = { [logger] state in
                switch state {
                case .ready:
                    logger.debug("Trigger: connection ready")
                    if flag.setTrueIfFalse() {
                        continuation.resume(returning: false) // No dialog needed
                    }

                case .waiting(let error):
                    let errorCode = (error as NSError).code
                    logger.debug("Trigger: waiting with error \(errorCode)")

                    if errorCode == 50 {
                        // Error 50 = permission dialog triggered
                        if flag.setTrueIfFalse() {
                            continuation.resume(returning: true)
                        }
                    } else {
                        // Other error = network accessible, no dialog needed
                        if flag.setTrueIfFalse() {
                            continuation.resume(returning: false)
                        }
                    }

                case .failed(let error):
                    let errorCode = (error as NSError).code
                    logger.debug("Trigger: failed with error \(errorCode)")
                    if flag.setTrueIfFalse() {
                        continuation.resume(returning: errorCode == 50)
                    }

                case .cancelled:
                    if flag.setTrueIfFalse() {
                        continuation.resume(returning: false)
                    }

                default:
                    break
                }
            }

            connection.start(queue: networkQueue)

            // Short timeout just to trigger the dialog
            Task {
                try? await Task.sleep(for: .seconds(2))
                if flag.setTrueIfFalse() {
                    continuation.resume(returning: false)
                }
            }
        }

        connection.stateUpdateHandler = nil
        connection.cancel()

        return sawError50
    }

    /// Check if permission has been granted by making a fresh connection
    /// Returns true if permission granted (any error except 50), false if still denied
    private func checkPermissionGranted(testIP: String) async -> Bool {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(testIP),
            port: NWEndpoint.Port(rawValue: 502)!
        )

        let connection = NWConnection(to: endpoint, using: .tcp)
        let flag = ConnectionFlag()

        let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Connected = permission granted
                    if flag.setTrueIfFalse() {
                        continuation.resume(returning: true)
                    }

                case .waiting(let error):
                    let errorCode = (error as NSError).code
                    if errorCode == 50 {
                        // Still denied
                        if flag.setTrueIfFalse() {
                            continuation.resume(returning: false)
                        }
                    } else {
                        // Any other error = permission granted
                        if flag.setTrueIfFalse() {
                            continuation.resume(returning: true)
                        }
                    }

                case .failed(let error):
                    let errorCode = (error as NSError).code
                    // Error 50 = still denied, anything else = granted
                    if flag.setTrueIfFalse() {
                        continuation.resume(returning: errorCode != 50)
                    }

                case .cancelled:
                    if flag.setTrueIfFalse() {
                        continuation.resume(returning: false)
                    }

                default:
                    break
                }
            }

            connection.start(queue: networkQueue)

            // Quick timeout - we just want to check current state
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                if flag.setTrueIfFalse() {
                    continuation.resume(returning: false)
                }
            }
        }

        connection.stateUpdateHandler = nil
        connection.cancel()

        return granted
    }

    private func getLocalNetworkBase() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return nil
        }

        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)

                // Skip loopback interface
                if name == "lo0" { continue }

                // Only consider WiFi (en0) or Ethernet interfaces
                if name.hasPrefix("en") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )

                    let ip = String(decoding: hostname.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                    // Return the base (first 3 octets)
                    let parts = ip.split(separator: ".")
                    if parts.count == 4 {
                        return "\(parts[0]).\(parts[1]).\(parts[2])"
                    }
                }
            }
        }

        return nil
    }
}

// MARK: - Discovery Errors

enum DiscoveryError: Error, LocalizedError {
    case noNetworkAccess
    case scanCancelled
    case invalidIPAddress

    var errorDescription: String? {
        switch self {
        case .noNetworkAccess:
            return "Cannot access the local network"
        case .scanCancelled:
            return "Network scan was cancelled"
        case .invalidIPAddress:
            return "Invalid IP address format"
        }
    }
}
