import AppKit
import os

private nonisolated let commonLogger = Logger(
    subsystem: "com.muxctl.app",
    category: "CommonLogger"
)

private enum ThemeNotifications {
    static let reloadConfig = Notification.Name("com.muxctl.themes.reload-config")
}

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        commonLogger.info("muxctl launched")
    }
}
