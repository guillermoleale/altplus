import Foundation

enum AppInfo {
    static let name = "AltPlus"
    static let bundleID = Bundle.main.bundleIdentifier ?? "org.altplus.AltPlus"
    static let version: String = {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return short ?? "dev"
    }()
    static let repositoryURL = URL(string: "https://github.com/guillermoleale/altplus")!
}
