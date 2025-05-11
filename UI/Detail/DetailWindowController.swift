import Cocoa
import os.log

class DetailWindowController: NSWindowController, NSWindowDelegate {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.Eidon.Detail", category: "DetailWindowController")
    
    private var detailViewController: DetailViewController?
    // Store the entry. This is useful for setting the window title or other context-dependent window behaviors.
    private var entry: EidonEntryEntity 

    // Convenience initializer accepting an EidonEntryEntity
    init(entry: EidonEntryEntity) {
        self.entry = entry // Store the passed entry
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 750), // Adjusted initial size
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center() // Center the new window
        
        // Set a more descriptive window title
        var windowTitle = "Eidon Detail"
        if let entryTitle = entry.title, !entryTitle.isEmpty {
            windowTitle = entryTitle
        } else if let entryApp = entry.app, !entryApp.isEmpty {
            // Fallback to app name if title is empty
            windowTitle = entryApp
        }
        window.title = windowTitle
        
        // For window state restoration. Consider making this unique per entry if many can be opened.
        // For now, a generic name means subsequent detail windows might share position/size.
        window.setFrameAutosaveName("EidonDetailWindow")

        // Modern window appearance
        window.titlebarAppearsTransparent = true
        // window.titleVisibility = .hidden // Uncomment if you prefer the title text to be hidden

        super.init(window: window) // Crucial: Call the designated initializer of NSWindowController
        
        window.delegate = self // Set self as the window's delegate
        
        // Create and configure the DetailViewController
        detailViewController = DetailViewController()
        detailViewController?.configure(with: entry) // Pass the entry to the view controller
        window.contentViewController = detailViewController // Set it as the window's content
        
        logger.info("DetailWindowController initialized for entry: \(entry.id?.uuidString ?? "Unknown ID", privacy: .public)")
    }

    // This is required if you have a custom designated initializer.
    // It ensures that if someone tries to init with a coder (e.g., from a Storyboard/NIB), it's handled.
    // For purely programmatic creation like this, it often just calls fatalError.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented. Use init(entry: EidonEntryEntity).")
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        logger.info("Detail window did load.")
        // Any additional window configuration after it has loaded can go here.
        // e.g., window?.minSize = NSSize(width: 400, height: 500)
    }

    // MARK: - NSWindowDelegate Methods

    func windowWillClose(_ notification: Notification) {
        logger.info("Detail window will close for entry: \(entry.id?.uuidString ?? "Unknown ID", privacy: .public)")
        // This method is called when the window is about to be closed.
        // You can perform cleanup here. The DetailWindowController instance will be deallocated
        // if the object that created it (e.g., SearchViewController) releases its reference.
    }
    
    // MARK: - Public Access to Show Window
    
    public func showWindowAndFocus() {
        guard let window = self.window else {
            logger.error("Window is nil for DetailWindowController. Cannot show.")
            return
        }
        
        // If you decide to reuse detail windows instead of creating new ones each time,
        // you might un-comment this to re-center if it was previously hidden.
        // if !window.isVisible { window.center() }
        
        self.showWindow(nil) // Pass nil as sender, standard way to show the window
        window.makeKeyAndOrderFront(nil) // Brings the window to the front and makes it the key window
        NSApp.activate(ignoringOtherApps: true) // Ensures the application itself is active
        logger.info("Detail window shown and focused for entry: \(entry.id?.uuidString ?? "Unknown ID", privacy: .public)")
    }
}