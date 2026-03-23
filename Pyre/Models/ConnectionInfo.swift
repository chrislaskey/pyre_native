import Foundation

/// System information about the local machine, sent to the server on channel join.
struct ConnectionInfo {
    let name: String
    let cpuCores: Int
    let cpuBrand: String
    let memoryGB: Int
    let osVersion: String
    let connectionId: String

    /// Gather current system information.
    static func current() -> ConnectionInfo {
        ConnectionInfo(
            name: localName(),
            cpuCores: ProcessInfo.processInfo.processorCount,
            cpuBrand: cpuBrandString(),
            memoryGB: Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            connectionId: persistedConnectionId()
        )
    }

    /// Convert to dictionary for channel join params.
    func toDictionary() -> [String: Any] {
        [
            "name": name,
            "cpu_cores": cpuCores,
            "cpu_brand": cpuBrand,
            "memory_gb": memoryGB,
            "os_version": osVersion,
            "connection_id": connectionId
        ]
    }

    // MARK: - Private

    private static let connectionIdKey = "pyre_connection_id"

    private static func persistedConnectionId() -> String {
        if let data = UserDefaultsService.get(key: connectionIdKey),
           let id = String(data: data, encoding: .utf8) {
            return id
        }
        let id = UUID().uuidString
        if let data = id.data(using: .utf8) {
            UserDefaultsService.update(key: connectionIdKey, value: data)
        }
        return id
    }

    private static func localName() -> String {
        #if os(macOS)
        return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }

    private static func cpuBrandString() -> String {
        #if os(macOS)
        var size: size_t = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        return String(cString: brand)
        #else
        return "Apple Silicon"
        #endif
    }
}
