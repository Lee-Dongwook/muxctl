private noisolated let commonLogger = Logger(
    subsystem: "com.muxctl.app",
    category: "CommonLogger"
)

private enum ThemeNotifications {
    static let reloadConfig = Notifications.Name("com.muxctl.themes.reload-config")
}
