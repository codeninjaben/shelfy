import os

nonisolated enum Log {
    static let subsystem = "com.benbreslow.Shelfy"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let files = Logger(subsystem: subsystem, category: "files")
    static let edge = Logger(subsystem: subsystem, category: "edge")
    static let menuBar = Logger(subsystem: subsystem, category: "menubar")

    /// File names and paths are user data: readable in Debug builds (for verification),
    /// redacted entirely in Release builds.
    static func redacted(_ value: String) -> String {
        #if DEBUG
        value
        #else
        "<redacted>"
        #endif
    }
}
