import Foundation

/// Route pattern matcher using regex for parameterized routes
struct RoutePattern {
    let pattern: String
    private let regex: NSRegularExpression
    
    init(_ pattern: String) {
        self.pattern = pattern
        
        // Convert route pattern to regex
        // Example: "/organizations/:id/log-in" -> "^/organizations/([^/]+)/log-in$"
        var regexPattern = pattern
        
        // Escape special regex characters except :
        regexPattern = regexPattern.replacingOccurrences(of: ".", with: "\\.")
        
        // Replace :param with capture group
        regexPattern = regexPattern.replacingOccurrences(
            of: #":([a-zA-Z_][a-zA-Z0-9_]*)"#,
            with: "([^/]+)",
            options: .regularExpression
        )
        
        // Add anchors
        regexPattern = "^" + regexPattern + "$"
        
        // Create regex
        self.regex = try! NSRegularExpression(pattern: regexPattern, options: [])
    }
    
    /// Match a path against this pattern and extract parameters
    func match(_ path: String) -> [String: String]? {
        let nsPath = path as NSString
        let range = NSRange(location: 0, length: nsPath.length)
        
        guard let match = regex.firstMatch(in: path, options: [], range: range) else {
            return nil
        }
        
        // Extract parameter names from pattern
        let paramNames = extractParameterNames(from: pattern)
        
        // Extract captured values
        var params: [String: String] = [:]
        for (index, paramName) in paramNames.enumerated() {
            let captureIndex = index + 1 // Capture groups start at 1
            if captureIndex < match.numberOfRanges {
                let captureRange = match.range(at: captureIndex)
                if captureRange.location != NSNotFound {
                    let value = nsPath.substring(with: captureRange)
                    params[paramName] = value
                }
            }
        }
        
        return params
    }
    
    /// Extract parameter names from pattern (e.g., ":id" -> "id")
    private func extractParameterNames(from pattern: String) -> [String] {
        let paramRegex = try! NSRegularExpression(pattern: #":([a-zA-Z_][a-zA-Z0-9_]*)"#, options: [])
        let nsPattern = pattern as NSString
        let range = NSRange(location: 0, length: nsPattern.length)
        let matches = paramRegex.matches(in: pattern, options: [], range: range)
        
        return matches.map { match in
            let captureRange = match.range(at: 1) // First capture group
            return nsPattern.substring(with: captureRange)
        }
    }
}
