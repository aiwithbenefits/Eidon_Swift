import Cocoa
import os.log

class TimelineWindowController: NSWindowController, NSWindowDelegate {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.Eidon.Timeline", category: "TimelineWindowController")
    
    // Strong reference to the view controller
    var timelineViewController: TimelineViewController?

    // Convenience initializer
    convenience init() {
        // Create a window programmatically.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), // Adjusted initial size
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], // Added fullSizeContentView
            backing: .buffered,
            defer: false
        )
        window.center() 
        window.title = "Eidon Timeline"
        window.setFrameAutosaveName("EidonTimelineWindow")

        // For a modern look with title bar integration
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden // Or .visible if you want the title text
        // window.styleMask.insert(.fullSizeContentView) // If not set in styleMask init

        self.init(window: window)
        window.delegate = self 
        
        timelineViewController = TimelineViewController()
        window.contentViewController = timelineViewController
        
        logger.info("TimelineWindowController initialized.")
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        logger.info("Timeline window did load.")
        // Configure window appearance further if needed
        // Example: window?.backgroundColor = NSColor.windowBackgroundColor
    }

    // MARK: - NSWindowDelegate Methods

    func windowWillClose(_ notification: Notification) {
        logger.info("Timeline window will close.")
        // This allows the window controller to be deallocated if AppDelegate only holds it weakly or when it's closed.
        // If AppDelegate holds a strong reference, this specific line might not be strictly necessary for deallocation
        // but can be good practice to break cycles if the window has a strong reference back.
        // For this setup, AppDelegate will manage the lifecycle.
    }
    
    // MARK: - Public Access
    
    public func showWindowAndFocus() {
        guard let window = self.window else {
            logger.error("Window is nil for TimelineWindowController. Cannot show.")
            return
        }
        
        if !window.isVisible {
            window.center() // Re-center if it was closed or hidden
        }
        
        self.showWindow(nil) 
        window.makeKeyAndOrderFront(nil) 
        NSApp.activate(ignoringOtherApps: true)
        logger.info("Timeline window shown and focused.")
    }
}