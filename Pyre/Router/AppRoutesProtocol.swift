import Foundation

protocol AppRoutesProtocol {
    // Central registry of all application routes
    // Single source of truth for route patterns, guards, socket types, and views
    //
    // - Returns: The routes
    static var routes: [Route] { get }
}