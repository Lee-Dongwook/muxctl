import SwiftUI
import os

private let commonLogger = Logger(
    subsystem: "com.muxctl.ios",
    category: "CommonLogger"
)

@main
struct MuxctlApp: App {
    init() {
        commonLogger.info("muxctl-ios launched")
    }

    var body: some Scene {
        WindowGroup {
            Text("muxctl")
        }
    }
}
