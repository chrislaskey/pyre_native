import Foundation

/// Simple pattern-based URL matcher (no wildcards, no fragments)
struct URLPattern {
    let pattern: String
    private let components: [Component]
    
    init(_ pattern: String) {
        self.pattern = pattern
        self.components = pattern
            .split(separator: "/")
            .map { String($0) }
            .map { Component(from: $0) }
    }
    
    /// Extract parameters from URL if it matches
    func matches(pathComponents: [String]) -> [String: String]? {
        // Handle root path
        if pattern == "/" && pathComponents.isEmpty {
            return [:]
        }
        
        // Must have same number of components
        if components.count != pathComponents.count {
            return nil
        }
        
        var parameters: [String: String] = [:]
        
        for (index, component) in components.enumerated() {
            let pathComponent = pathComponents[index]
            
            switch component {
            case .literal(let value):
                if value != pathComponent {
                    return nil
                }
            case .parameter(let name):
                parameters[name] = pathComponent
            }
        }
        
        return parameters
    }
    
    // MARK: - Component Types
    
    private enum Component {
        case literal(String)      // "users"
        case parameter(String)    // ":id"
        
        init(from string: String) {
            if string.hasPrefix(":") {
                let name = String(string.dropFirst())
                self = .parameter(name)
            } else {
                self = .literal(string)
            }
        }
    }
}

// MARK: - URL Extension

extension URL {
    /// Match against a pattern and extract parameters
    func matches(pattern: String) -> [String: String]? {
        let matcher = URLPattern(pattern)
        // Get path components, removing leading "/" if present
        let components = self.path
            .split(separator: "/")
            .map(String.init)
        return matcher.matches(pathComponents: components)
    }
}

