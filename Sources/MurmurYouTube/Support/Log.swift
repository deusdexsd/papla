import OSLog

enum Log {
    static let audio = Logger(subsystem: "ai.pivotstudio.murmur-youtube", category: "audio")
    static let speech = Logger(subsystem: "ai.pivotstudio.murmur-youtube", category: "speech")
    static let hotkey = Logger(subsystem: "ai.pivotstudio.murmur-youtube", category: "hotkey")
    static let inject = Logger(subsystem: "ai.pivotstudio.murmur-youtube", category: "inject")
    static let app = Logger(subsystem: "ai.pivotstudio.murmur-youtube", category: "app")
}
