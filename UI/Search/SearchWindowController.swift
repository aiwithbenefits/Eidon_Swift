import Cocoa
import os.log

class SearchWindowController: NSWindowController, NSWindowDelegate {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.Eidon.Search", category: "SearchWindowController")

    // Strong reference to the view controller
    var searchViewController: SearchViewController?

    // Convenience initializer
    convenience init() {
        // Create a window programmatically.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500), // Initial size
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Eidon Search"
        window.setFrameAutosaveName("EidonSearchWindow") // For window state restoration

        // For a modern look with title bar integration
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden // Or .visible if you want the title text

        self.init(window: window)
        window.delegate = self

        // Create and assign the content view controller
        searchViewController = SearchViewController()
        window.contentViewController = searchViewController

        logger.info("SearchWindowController initialized.")
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        logger.info("Search window did load.")
        // Configure window appearance further if needed
        // Example: window?.minSize = NSSize(width: 400, height: 300)
        if let window = self.window, let searchVC = self.searchViewController {
            // Try to make search field first responder after window is loaded
            // and view controller's view is established.
            // SearchViewController's viewDidLoad or viewDidAppear is often a better place for this.
             window.makeFirstResponder(searchVC.view.subviews.first(where: { $0 is NSSearchField }))
        }
    }

    // MARK: - NSWindowDelegate Methods

    func windowWillClose(_ notification: Notification) {
        logger.info("Search window will close.")
        // Perform any cleanup if needed when the window is about to close
        // This SearchWindowController instance will be deallocated if AppDelegate
        // removes its strong reference or only holds it weakly when closed.
    }

    // MARK: - Public Access

    public func showWindowAndFocus() {
        guard let window = self.window else {
            logger.error("Window is nil for SearchWindowController. Cannot show.")
            return
        }

        if !window.isVisible {
            window.center() // Re-center if it was closed or hidden
        }

        self.showWindow(nil) // Pass nil as sender
        window.makeKeyAndOrderFront(nil) // Bring to front and make key
        NSApp.activate(ignoringOtherApps: true) // Bring application to front
        logger.info("Search window shown and focused.")
        
        // It's generally better to set first responder in the ViewController's viewDidAppear
        // or after the window is fully visible and set up.
        // However, if SearchViewController's view is already loaded, this might work.
        if let searchVC = self.searchViewController,
           let searchField = searchVC.view.subviews.first(where: { $0 is NSSearchField }) {
            window.makeFirstResponder(searchField)
        }
    }
}