import Foundation

/// Enhanced debugging logger for development builds only
/// Provides detailed, formatted output for WebSocket connections and data
class DebugLogger {
    
    // MARK: - Log Levels
    
    enum LogLevel: String, Comparable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        
        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }
        
        var priority: Int {
            switch self {
            case .debug: return 0
            case .info: return 1
            case .warning: return 2
            case .error: return 3
            }
        }
        
        static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            return lhs.priority < rhs.priority
        }
    }
    
    // MARK: - Configuration
    
    /// Configure which log levels are enabled
    static var enabledLevels: Set<LogLevel> = {
        #if DEBUG
        return [.info, .warning, .error]
        #else
        return []
        #endif
    }()
    
    /// Whether to show sensitive data (tokens, passwords, etc)
    /// Only enable in local development!
    static var showSensitiveData: Bool {
        #if DEBUG
        // You can make this even more restrictive if needed
        return true
        #else
        return false
        #endif
    }
    
    // MARK: - Core Logging Methods
    
    /// Log a debug message (detailed technical information)
    static func debug(_ message: String) {
        log(message, level: .debug)
    }
    
    /// Log an info message (general informational messages)
    static func info(_ message: String) {
        log(message, level: .info)
    }
    
    /// Log a warning message (potentially problematic situations)
    static func warning(_ message: String) {
        log(message, level: .warning)
    }
    
    /// Log an error message (error events)
    static func error(_ message: String) {
        log(message, level: .error)
    }
    
    /// Internal logging method
    private static func log(_ message: String, level: LogLevel) {
        guard enabledLevels.contains(level) else { return }
        print("[\(level.rawValue)] \(message)")
    }
    
    // MARK: - Specialized Logging Methods
    
    /// Log socket connection
    static func logConnection(url: String, level: LogLevel = .debug) {
        guard enabledLevels.contains(level) else { return }
        print("\n🔌 CONNECTING TO SOCKET")
        print("└─ URL: \(url)")
    }
    
    /// Log socket disconnection
    static func logDisconnection(url: String, level: LogLevel = .debug) {
        guard enabledLevels.contains(level) else { return }
        print("\n🔌 DISCONNECTING FROM SOCKET")
        print("└─ URL: \(url)")
    }
    
    /// Log channel join attempt
    static func logChannelJoin(topic: String, params: [String: Any]? = nil, level: LogLevel = .debug) {
        guard enabledLevels.contains(level) else { return }
        print("\n📡 JOINING CHANNEL")
        print("├─ Topic: \(topic)")
        if let params = params, !params.isEmpty {
            print("└─ Params:")
            prettyPrint(params, indent: "   ")
        }
    }
    
    /// Log channel joined successfully
    static func logChannelJoined(topic: String, response: [String: Any]? = nil, level: LogLevel = .info) {
        guard enabledLevels.contains(level) else { return }
        print("\n✅ CHANNEL JOINED")
        print("├─ Topic: \(topic)")
        if let response = response {
            print("└─ Response:")
            prettyPrint(response, indent: "   ", sanitize: true)
        }
    }
    
    /// Log channel join error
    static func logChannelError(topic: String, error: Any, level: LogLevel = .error) {
        guard enabledLevels.contains(level) else { return }
        print("\n❌ CHANNEL JOIN ERROR")
        print("├─ Topic: \(topic)")
        print("└─ Error: \(error)")
    }
    
    /// Log outgoing message
    static func logPush(topic: String, event: String, payload: [String: Any], level: LogLevel = .debug) {
        guard enabledLevels.contains(level) else { return }
        print("\n📤 PUSH MESSAGE")
        print("├─ Topic: \(topic)")
        print("├─ Event: \(event)")
        print("└─ Payload:")
        prettyPrint(payload, indent: "   ", sanitize: true)
    }
    
    /// Log incoming message
    static func logReceive(topic: String, event: String, payload: [String: Any], level: LogLevel = .debug) {
        guard enabledLevels.contains(level) else { return }
        print("\n📥 RECEIVED MESSAGE")
        print("├─ Topic: \(topic)")
        print("├─ Event: \(event)")
        print("└─ Payload:")
        prettyPrint(payload, indent: "   ", sanitize: true)
    }
    
    // MARK: - Pretty Printing
    
    /// Pretty print a dictionary with indentation
    static func prettyPrint(_ dict: [String: Any], indent: String, sanitize: Bool = false) {
        let keys = dict.keys.sorted()
        
        for (index, key) in keys.enumerated() {
            let isLast = index == keys.count - 1
            let prefix = isLast ? "└─" : "├─"
            let childIndent = isLast ? "   " : "│  "
            
            var value = dict[key]
            
            // Sanitize sensitive data if needed
            if sanitize && !showSensitiveData {
                value = sanitizeIfSensitive(key: key, value: value)
            }
            
            if let nestedDict = value as? [String: Any] {
                print("\(indent)\(prefix) \(key):")
                prettyPrint(nestedDict, indent: indent + childIndent, sanitize: sanitize)
            } else if let array = value as? [[String: Any]] {
                print("\(indent)\(prefix) \(key): [\(array.count) items]")
                for (idx, item) in array.enumerated() {
                    print("\(indent)\(childIndent)[\(idx)]:")
                    prettyPrint(item, indent: indent + childIndent + "   ", sanitize: sanitize)
                }
            } else if let array = value as? [Any] {
                print("\(indent)\(prefix) \(key): \(formatValue(array))")
            } else {
                print("\(indent)\(prefix) \(key): \(formatValue(value))")
            }
        }
    }
    
    /// Sanitize sensitive values (hide in non-local environments)
    private static func sanitizeIfSensitive(key: String, value: Any?) -> Any? {
        let sensitiveKeys = ["token", "password", "secret", "api_key", "private_key", "auth_token", "user_token", "encoded_user_token", "encoded_identity_token"]
        
        let keyLower = key.lowercased()
        if sensitiveKeys.contains(where: { keyLower.contains($0) }) {
            if let stringValue = value as? String {
                // Show first/last 4 characters
                let length = stringValue.count
                if length > 8 {
                    let start = stringValue.prefix(4)
                    let end = stringValue.suffix(4)
                    return "\(start)...\(end) [REDACTED]"
                } else {
                    return "****** [REDACTED]"
                }
            }
            return "****** [REDACTED]"
        }
        
        return value
    }
    
    /// Format a value for display
    private static func formatValue(_ value: Any?) -> String {
        if value == nil {
            return "nil"
        }
        
        if let string = value as? String {
            return "\"\(string)\""
        }
        
        if let number = value as? NSNumber {
            return "\(number)"
        }
        
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        
        if let array = value as? [Any] {
            if array.isEmpty {
                return "[]"
            }
            let items = array.map { formatValue($0) }.joined(separator: ", ")
            return "[\(items)]"
        }
        
        return "\(value ?? "nil")"
    }
    
    // MARK: - Helpers
    
    /// Log separator line
    static func separator(level: LogLevel = .debug) {
        guard enabledLevels.contains(level) else { return }
        print("─────────────────────────────────────────────────")
    }
    
    /// Log a section header
    static func section(_ title: String, level: LogLevel = .debug) {
        guard enabledLevels.contains(level) else { return }
        print("\n" + String(repeating: "=", count: 50))
        print("  \(title)")
        print(String(repeating: "=", count: 50))
    }
}
