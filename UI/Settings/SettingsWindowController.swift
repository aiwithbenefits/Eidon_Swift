import Cocoa
import os.log

class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.Eidon.Settings", category: "SettingsWindowController")
    
    private var settingsViewController: SettingsViewController?

    convenience init() {
        // Using the frame from SettingsViewController's loadView as a guide for contentRect
        // The window will typically be slightly larger than its content view.
        // Width and Height should accommodate the SettingsViewController's view.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420), 
            styleMask: [.titled, .closable, .miniaturizable], // Standard settings window style
            backing: .buffered,
            defer: false
        )
        window.center() 
        window.title = "Eidon Settings"
        // Settings windows usually don't need frame autosave unless they are resizable and user expects it.
        // window.setFrameAutosaveName("EidonSettingsWindow")
        
        // Standard appearance for settings/preferences
        // window.titlebarAppearsTransparent = false 
        // window.titleVisibility = .visible

        super.init(window: window) 
        
        window.delegate = self 
        
        settingsViewController = SettingsViewController()
        window.contentViewController = settingsViewController
        
        logger.info("SettingsWindowController initialized.")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented. Use init().")
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        logger.info("Settings window did load.")
        // Prevent resizing for a fixed layout settings panel
        self.window?.styleMask.remove(.resizable)
    }

    // MARK: - NSWindowDelegate Methods
    func windowWillClose(_ notification: Notification) {
        logger.info("Settings window will close.")
        // Any cleanup specific to the window controller when closed.
        // The controller will be deallocated if AppDelegate (or whoever holds it) releases its strong reference.
    }
    
    // MARK: - Public Access
    public func showWindowAndFocus() {
        guard let window = self.window else {
            logger.error("Window is nil for SettingsWindowController. Cannot show.")
            return
        }
        
        // If not visible, ensure it's centered before showing.
        if !window.isVisible {
            window.center()
        }
        
        self.showWindow(nil) 
        window.makeKeyAndOrderFront(nil) 
        NSApp.activate(ignoringOtherApps: true) 
        logger.info("Settings window shown and focused.")
    }
}