public import Foundation

public extension Notification.Name {
    static let terminalSurfaceDidBecomeReady = 
        Notification.Name("muxctl.terminalSurfaceDidBecomeReady")
    
    static let terminalSurfaceDidCompleteClipboardRead = 
        Notification.Name("terminalSurfaceDidCompleteClipboardRead")
}
