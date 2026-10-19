import os

enum Log {
    static let app = Logger(subsystem: AppInfo.bundleID, category: "app")
    static let input = Logger(subsystem: AppInfo.bundleID, category: "input")
    static let windows = Logger(subsystem: AppInfo.bundleID, category: "windows")
}
