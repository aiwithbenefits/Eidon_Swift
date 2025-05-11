import Cocoa
import os.log

class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.Eidon.StatusBar", category: "StatusBarController")

    // Keep a reference to services if direct interaction is needed for status updates
    private let screenshotService = ScreenshotService.shared
    // We'll need a way to open windows, typically via AppDelegate or a dedicated WindowCoordinator

    private var statusMenuItem: NSMenuItem!
    private var toggleCaptureMenuItem: NSMenuItem!
    private var openTimelineMenuItem: NSMenuItem!
    private var captureNowMenuItem: NSMenuItem! 
    private var openSearchMenuItem: NSMenuItem!
    private var openSettingsMenuItem: NSMenuItem! // Added
    // Keep a reference to the AppDelegate or a WindowCoordinator to open windows
    weak var appDelegate: AppDelegate?


    override init() {
        super.init()
        setupStatusItem()
        updateMenuItems() // Initial setup of menu item states

        // Observe capture status changes if ScreenshotService emits them (e.g., via NotificationCenter or Combine)
        // For now, we'll rely on direct checks or manual updates when menu is about to open.
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            // Use a template image so it adapts to light/dark mode automatically
            // You'll need to add an icon named "EidonStatusIcon" to your Assets.xcassets
            // For placeholder, using a system icon or a simple SF Symbol if available via code.
            if #available(macOS 11.0, *) {
                if let iconImage = NSImage(systemSymbolName: "camera.on.rectangle.fill", accessibilityDescription: "Eidon Status") {
                    button.image = iconImage
                } else {
                    button.image = NSImage(named: "EidonStatusIcon") // Fallback to custom asset
                     // As a last resort if no icon is found:
                    if button.image == nil { button.title = "E" }
                }
            } else {
                 button.image = NSImage(named: "EidonStatusIcon")
                 if button.image == nil { button.title = "E" }
            }
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp]) // Handle both clicks if needed
            button.target = self
        }

        constructMenu()
    }

    private func constructMenu() {
        let menu = NSMenu()
        menu.delegate = self // To update items before menu shows

        statusMenuItem = NSMenuItem(title: "Status: Unknown", action: nil, keyEquivalent: "")
        menu.addItem(statusMenuItem)

        toggleCaptureMenuItem = NSMenuItem(title: "Pause Capture", action: #selector(toggleCapture(_:)), keyEquivalent: "")
        toggleCaptureMenuItem.target = self
        menu.addItem(toggleCaptureMenuItem)

        menu.addItem(NSMenuItem.separator())

        captureNowMenuItem = NSMenuItem(title: "Capture Now", action: #selector(captureNow(_:)), keyEquivalent: "N")
        captureNowMenuItem.keyEquivalentModifierMask = [.command, .shift] // Cmd+Shift+N
        captureNowMenuItem.target = self
        menu.addItem(captureNowMenuItem)

        openTimelineMenuItem = NSMenuItem(title: "Open Timeline...", action: #selector(openTimelineWindow(_:)), keyEquivalent: "t")
        openTimelineMenuItem.keyEquivalentModifierMask = [.command]
        openTimelineMenuItem.target = self
        menu.addItem(openTimelineMenuItem)

        openSearchMenuItem = NSMenuItem(title: "Open Search...", action: #selector(openSearchWindow(_:)), keyEquivalent: "f")
        openSearchMenuItem.keyEquivalentModifierMask = [.command, .shift] // Cmd+Shift+F
        openSearchMenuItem.target = self
        menu.addItem(openSearchMenuItem)
        
        // Placeholder for Command Palette / Quick Search (if different from general search)
        // let quickSearchItem = NSMenuItem(title: "Quick Search...", action: #selector(openCommandPalette(_:)), keyEquivalent: "k")
        // quickSearchItem.keyEquivalentModifierMask = [.command]
        // quickSearchItem.target = self
        // menu.addItem(quickSearchItem)


        menu.addItem(NSMenuItem.separator())

        let quitMenuItem = NSMenuItem(title: "Quit Eidon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitMenuItem.target = NSApp // NSApp is the shared NSApplication instance
        menu.addItem(quitMenuItem)

        statusItem.menu = menu
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        // This action is primarily for when the button itself is configured to perform an action on left click
        // without a menu. If a menu is present, it will show automatically on left click.
        // For right-click to show menu, or if menu is set, this might not be strictly needed
        // unless you want a different action for a direct click.
        // statusItem.menu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) // If menu not auto-showing
        logger.debug("Status item clicked.")
    }

    @objc private func toggleCapture(_ sender: Any?) {
        if screenshotService.isCaptureGloballyEnabled() {
            screenshotService.pauseCapture()
        } else {
            screenshotService.resumeCapture()
        }
        updateMenuItems()
    }

    @objc private func captureNow(_ sender: Any?) {
        logger.info("Action: Capture Now triggered from status bar.")
        screenshotService.captureAndProcessSingleFrame { success in
            self.logger.info("Ad-hoc capture completed. Success: \(success)")
            // Optionally, provide user feedback like a notification here
            // For example, if you have a NotificationService:
            // if success {
            //     NotificationService.shared.showNotification(title: "Eidon", body: "Screenshot captured!")
            // } else {
            //     NotificationService.shared.showNotification(title: "Eidon", body: "Failed to capture screenshot.")
            // }
        }
    }

    @objc private func openSettingsWindow(_ sender: Any?) {
        logger.info("Action: Open Settings Window triggered.")
        NotificationCenter.default.post(name: .requestOpenSettingsWindow, object: nil)
    }

    @objc private func openTimelineWindow(_ sender: Any?) {
        logger.info("Action: Open Timeline Window triggered.")
        // This would typically call a method on AppDelegate or a WindowCoordinator to show the timeline window.
        // Example: (appDelegate ?? NSApp.delegate as? AppDelegate)?.showTimelineWindow()
        NotificationCenter.default.post(name: .requestOpenTimelineWindow, object: nil)
    }

    @objc private func openSearchWindow(_ sender: Any?) {
        logger.info("Action: Open Search Window triggered.")
        // Example: (appDelegate ?? NSApp.delegate as? AppDelegate)?.showSearchWindow()
         NotificationCenter.default.post(name: .requestOpenSearchWindow, object: nil)
    }
    
    // @objc private func openCommandPalette(_ sender: Any?) {
    //     logger.info("Action: Open Command Palette triggered.")
    // NotificationCenter.default.post(name: .requestOpenCommandPalette, object: nil)
    // }


    private func updateMenuItems() {
        if screenshotService.isCaptureGloballyEnabled() {
            statusMenuItem.title = "Status: Capturing"
            toggleCaptureMenuItem.title = "Pause Capture"
            if #available(macOS 11.0, *) {
                toggleCaptureMenuItem.image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "Pause Capture")
            }
        } else {
            statusMenuItem.title = "Status: Paused"
            toggleCaptureMenuItem.title = "Resume Capture"
             if #available(macOS 11.0, *) {
                toggleCaptureMenuItem.image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: "Resume Capture")
            }
        }
    }
}

// MARK: - NSMenuDelegate
extension StatusBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        logger.debug("Status bar menu will open. Updating items.")
        updateMenuItems() // Ensure menu items are up-to-date when menu is about to be shown
    }
}

// MARK: - Notification Names
// Define custom notification names for window requests
extension Notification.Name {
    static let requestOpenTimelineWindow = Notification.Name("com.eidon.requestOpenTimelineWindow")
    static let requestOpenSearchWindow = Notification.Name("com.eidon.requestOpenSearchWindow")
    static let requestOpenSettingsWindow = Notification.Name("com.eidon.requestOpenSettingsWindow")
    // static let requestOpenCommandPalette = Notification.Name("com.eidon.requestOpenCommandPalette")
    static let captureStatusChanged = Notification.Name("com.eidon.captureStatusChanged") // If ScreenshotService posts this
}
```