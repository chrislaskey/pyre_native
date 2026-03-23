import Foundation
import Combine

// MARK: - TestLogLevel

enum TestLogLevel {
    case info, success, warning, error, debug
}

// MARK: - TestLogEntry

struct TestLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let elapsed: TimeInterval
    let message: String
    let level: TestLogLevel
    let detail: String?
}

// MARK: - ConnectionTester

/// Tests connectivity to a Pyre server through a 4-step sequence:
/// 1. HTTP reachability check
/// 2. WebSocket socket connection
/// 3. Channel join (pyre:hello)
/// 4. Ping/pong message round-trip
///
/// Produces detailed timestamped log entries for debugging integration issues.
@MainActor
class ConnectionTester: ObservableObject {
    @Published var isTesting = false
    @Published var logEntries: [TestLogEntry] = []
    @Published var testPassed = false
    @Published var testComplete = false
    @Published var resolvedWsUrl: String?

    private var socket: PhoenixSocket?
    private var channel: PhoenixChannel?
    private var cancellables = Set<AnyCancellable>()
    private var testStartTime: Date?
    private var pendingTimeouts: [DispatchWorkItem] = []

    init() {}

    // MARK: - Public API

    func test(baseUrl: String) {
        reset()
        isTesting = true
        testStartTime = Date()

        let trimmedUrl = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedUrl.isEmpty else {
            log("Base URL is empty", level: .error)
            finishTest(passed: false)
            return
        }

        log("Testing connection to: \(trimmedUrl)", level: .info)

        let tempConnection = Connection(name: "Test", baseUrl: trimmedUrl)
        let wsUrl = PhoenixSocket.buildWebSocketURL(connection: tempConnection, channelPath: "")
        resolvedWsUrl = wsUrl

        let wsProtocol = wsUrl.hasPrefix("wss://") ? "wss" : "ws"
        let httpProtocol = trimmedUrl.hasPrefix("https://") ? "https" : trimmedUrl.hasPrefix("http://") ? "http" : "https (assumed)"
        log("Protocol mapping: \(httpProtocol) -> \(wsProtocol)", level: .debug)
        log("WebSocket URL: \(wsUrl)", level: .debug)

        performHTTPCheck(baseUrl: trimmedUrl) { [weak self] in
            self?.performSocketConnect(wsUrl: wsUrl)
        }
    }

    func cancel() {
        guard isTesting else { return }
        log("Test cancelled by user", level: .warning)
        cleanup()
        isTesting = false
    }

    func reset() {
        cleanup()
        logEntries = []
        testPassed = false
        testComplete = false
        isTesting = false
        resolvedWsUrl = nil
        testStartTime = nil
    }

    /// Plain text log for clipboard
    var logText: String {
        var lines: [String] = [
            "Pyre Connection Test Log",
            "========================",
            "Date: \(ISO8601DateFormatter().string(from: Date()))",
        ]
        if let wsUrl = resolvedWsUrl {
            lines.append("WebSocket URL: \(wsUrl)")
        }
        if testComplete {
            lines.append("Result: \(testPassed ? "PASSED" : "FAILED")")
        }
        lines.append("")

        for entry in logEntries {
            let elapsed = String(format: "%6.3fs", entry.elapsed)
            let level: String
            switch entry.level {
            case .info:    level = "INFO "
            case .success: level = "OK   "
            case .warning: level = "WARN "
            case .error:   level = "ERROR"
            case .debug:   level = "DEBUG"
            }
            lines.append("[\(elapsed)] [\(level)] \(entry.message)")
            if let detail = entry.detail {
                for detailLine in detail.components(separatedBy: "\n") {
                    lines.append("                     \(detailLine)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Step 1: HTTP Reachability

    private func performHTTPCheck(baseUrl: String, then: @escaping () -> Void) {
        log("Step 1/4: HTTP reachability check", level: .info)

        var httpUrlString = baseUrl
        if !httpUrlString.hasPrefix("http://") && !httpUrlString.hasPrefix("https://") {
            httpUrlString = "https://\(httpUrlString)"
            log("No scheme provided, using: \(httpUrlString)", level: .debug)
        }

        guard let url = URL(string: httpUrlString) else {
            log("Cannot parse URL: \(httpUrlString)", level: .warning)
            then()
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        log("GET \(httpUrlString) (timeout: 5s)", level: .debug)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self = self, self.isTesting else { return }

                if let error = error {
                    let nsError = error as NSError
                    switch nsError.code {
                    case NSURLErrorTimedOut:
                        self.log("HTTP request timed out (5s) - server may be slow or unreachable", level: .warning)
                    case NSURLErrorCannotConnectToHost:
                        self.log("Cannot connect to host - is the server running?", level: .warning)
                    case NSURLErrorCannotFindHost:
                        self.log("Cannot find host - check the hostname in the URL", level: .error)
                    case NSURLErrorAppTransportSecurityRequiresSecureConnection:
                        self.log("ATS blocked HTTP connection - use https:// or allow local networking", level: .warning)
                    case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
                        self.log("SSL/TLS error - certificate issue or self-signed cert", level: .warning,
                                 detail: error.localizedDescription)
                    default:
                        self.log("HTTP error: \(error.localizedDescription)", level: .warning,
                                 detail: "NSURLError code: \(nsError.code)")
                    }
                } else if let httpResponse = response as? HTTPURLResponse {
                    let bytes = data?.count ?? 0
                    let statusEmoji = (200..<400).contains(httpResponse.statusCode) ? "Server reachable" : "Server responded"
                    self.log("\(statusEmoji) - HTTP \(httpResponse.statusCode) (\(Self.formatBytes(bytes)))", level: .success)
                }

                then()
            }
        }.resume()
    }

    // MARK: - Step 2: WebSocket Connection

    private func performSocketConnect(wsUrl: String) {
        guard isTesting else { return }
        log("Step 2/4: WebSocket connection", level: .info)
        log("Connecting to \(wsUrl)...", level: .debug)

        let socket = PhoenixSocket(url: wsUrl)
        self.socket = socket

        socket.onSocketError { [weak self] error in
            Task { @MainActor in
                guard let self = self else { return }
                let nsError = error as NSError
                var detailParts: [String] = ["Domain: \(nsError.domain)", "Code: \(nsError.code)"]
                if let statusCode = nsError.userInfo["statusCode"] as? Int {
                    detailParts.append("HTTP Status: \(statusCode)")
                }
                if let url = nsError.userInfo["url"] as? String {
                    detailParts.append("URL: \(url)")
                }
                self.log("Socket error: \(nsError.localizedDescription)", level: .error,
                         detail: detailParts.joined(separator: ", "))
            }
        }

        var completed = false
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, !completed else { return }
            completed = true
            self.log("Socket connection timed out (10s)", level: .error)
            self.log("Troubleshooting:", level: .info)
            self.log("  1. Is the Phoenix server running?", level: .info)
            self.log("  2. Is PyreWeb.Socket mounted in your endpoint.ex?", level: .info)
            self.log("     socket \"/pyre\", PyreWeb.Socket, websocket: [...]", level: .info)
            self.log("  3. Check for firewall or proxy issues", level: .info)
            self.finishTest(passed: false)
        }
        pendingTimeouts.append(timeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)

        socket.$isConnected
            .dropFirst()
            .sink { [weak self] connected in
                guard let self = self, !completed else { return }
                if connected {
                    completed = true
                    timeout.cancel()
                    self.log("WebSocket connected!", level: .success)
                    self.performChannelJoin()
                }
            }
            .store(in: &cancellables)

        socket.connect()
    }

    // MARK: - Step 3: Channel Join

    private func performChannelJoin() {
        guard isTesting, let socket = socket else { return }
        log("Step 3/4: Joining channel \"pyre:hello\"", level: .info)

        let channel = socket.channel("pyre:hello")
        self.channel = channel

        var completed = false
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, !completed else { return }
            completed = true
            self.log("Channel join timed out (10s)", level: .error)
            self.log("Troubleshooting:", level: .info)
            self.log("  Socket connected OK, but channel join failed.", level: .info)
            self.log("  1. Verify PyreWeb.Socket has: channel \"pyre:*\", PyreWeb.Channel", level: .info)
            self.log("  2. Verify PyreWeb.Channel handles join for \"pyre:hello\"", level: .info)
            self.finishTest(passed: false)
        }
        pendingTimeouts.append(timeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)

        channel.join { [weak self] result in
            guard let self = self, !completed else { return }
            completed = true
            timeout.cancel()

            Task { @MainActor in
                switch result {
                case .success(let payload):
                    self.log("Channel joined!", level: .success, detail: self.formatPayload(payload))

                    if let response = payload["response"] as? [String: Any],
                       let message = response["message"] as? String {
                        self.log("Server says: \"\(message)\"", level: .success)
                    } else if let message = payload["message"] as? String {
                        self.log("Server says: \"\(message)\"", level: .success)
                    } else {
                        self.log("Join response has unexpected format", level: .warning,
                                 detail: "Expected {\"response\": {\"message\": \"hello world\"}}")
                    }

                    self.performPingTest()

                case .failure(let error):
                    let nsError = error as NSError
                    let reason = (nsError.userInfo["message"] as? [String: Any])
                        .flatMap { $0["reason"] as? String }
                    let errorMessage = reason ?? nsError.localizedDescription
                    self.log("Channel join failed: \(errorMessage)", level: .error, detail: "\(error)")
                    self.finishTest(passed: false)
                }
            }
        }
    }

    // MARK: - Step 4: Ping/Pong

    private func performPingTest() {
        guard isTesting, let channel = channel else { return }
        log("Step 4/4: Ping/pong test", level: .info)

        var completed = false
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, !completed else { return }
            completed = true
            self.log("Ping timed out (5s) - channel join worked, but no ping reply", level: .warning)
            self.finishTest(passed: true)
        }
        pendingTimeouts.append(timeout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)

        channel.push("ping", [:]) { [weak self] result in
            guard let self = self, !completed else { return }
            completed = true
            timeout.cancel()

            Task { @MainActor in
                switch result {
                case .success(let payload):
                    self.log("Pong received!", level: .success, detail: self.formatPayload(payload))

                    if let response = payload["response"] as? [String: Any],
                       let message = response["message"] as? String {
                        self.log("Server responded: \"\(message)\"", level: .success)
                    }

                    self.finishTest(passed: true)

                case .failure(let error):
                    self.log("Ping failed: \(error.localizedDescription)", level: .warning)
                    self.log("Channel join succeeded so marking as passed", level: .info)
                    self.finishTest(passed: true)
                }
            }
        }
    }

    // MARK: - Internal

    private func finishTest(passed: Bool) {
        guard isTesting else { return }

        if passed {
            log("All tests passed!", level: .success)
        } else {
            log("Test failed", level: .error)
        }

        cleanup()
        testPassed = passed
        testComplete = true
        isTesting = false
    }

    private func cleanup() {
        pendingTimeouts.forEach { $0.cancel() }
        pendingTimeouts.removeAll()

        if let channel = channel, let socket = socket {
            socket.removeChannel(channel)
        }
        channel = nil

        socket?.disconnect()
        socket = nil

        cancellables.removeAll()
    }

    private func log(_ message: String, level: TestLogLevel, detail: String? = nil) {
        let elapsed = testStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let entry = TestLogEntry(
            timestamp: Date(),
            elapsed: elapsed,
            message: message,
            level: level,
            detail: detail
        )
        logEntries.append(entry)

        let levelStr: String
        switch level {
        case .info:    levelStr = "INFO"
        case .success: levelStr = "OK"
        case .warning: levelStr = "WARN"
        case .error:   levelStr = "ERROR"
        case .debug:   levelStr = "DEBUG"
        }
        DebugLogger.info("[ConnectionTest] [\(String(format: "%.3fs", elapsed))] [\(levelStr)] \(message)")
        if let detail = detail {
            DebugLogger.debug("[ConnectionTest] \(detail)")
        }
    }

    private func formatPayload(_ payload: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "\(payload)"
    }

    private static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
