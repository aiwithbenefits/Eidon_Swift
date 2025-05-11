import Cocoa
import os.log
import Carbon.HIToolbox // For kVK_ANSI_E
import ServiceManagement // For SMAppService if macOS 13+

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.Eidon.AppDelegate", category: "AppDelegate")

    // Keep references to services to ensure they are not deallocated if they manage their own timers/threads.
    private let persistenceController = PersistenceController.shared
    private let screenshotService = ScreenshotService.shared
    private let archiverService = ArchiverService.shared
    // NLPService and OCRService are typically used on-demand.
    private var statusBarController: StatusBarController?
    
    // Window Controllers
    private var timelineWindowController: TimelineWindowController?
    private var searchWindowController: SearchWindowController?
    private var settingsWindowController: SettingsWindowController?

    // XPC Listener for the capture service, vended by the main app.
    private var captureServiceListener: NSXPCListener?
    private var xpcDelegate: XPCServiceDelegate? // Keep a strong reference to the delegate


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        logger.log("Application did finish launching.")

        // Ensure Core Data stack is ready
        _ = persistenceController.container 
        logger.info("PersistenceController initialized.")

        // Start services (they will read their intervals from AppSettings)
        screenshotService.startCaptureLoop() 
        logger.info("ScreenshotService capture loop initiated.")

        archiverService.startPeriodicArchiving() 
        logger.info("ArchiverService periodic archiving initiated.")
        
        // Optional: Initial archive run shortly after launch
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 30) {
            self.logger.info("Performing initial archive run post-launch.")
            self.archiverService.runArchiver()
        }

        // Status Bar
        statusBarController = StatusBarController()
        statusBarController?.appDelegate = self // Not strictly needed if using Notifications for all actions
        logger.info("StatusBarController initialized.")

        // Notification Observers for Window Requests
        NotificationCenter.default.addObserver(self, selector: #selector(handleOpenTimelineWindow), name: .requestOpenTimelineWindow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleOpenSearchWindow), name: .requestOpenSearchWindow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleOpenSettingsWindow), name: .requestOpenSettingsWindow, object: nil)
        
        // Observe AppSettings changes specifically for Launch at Login
        NotificationCenter.default.addObserver(self, selector: #selector(appSettingsDidChange(_:)), name: AppSettings.didChangeNotification, object: nil)

        // Setup Global Hotkey
        setupGlobalHotkey()
        
        // Initial check for launch at login state from settings
        // This ensures the app's login item status matches the stored preference at startup.
        updateLaunchAtLoginStatus(enabled: AppSettings.shared.launchAtLogin)

        // Start XPC listener for the capture service
        startXPCListener()
    }

    @objc func handleOpenTimelineWindow() {
        logger.info("AppDelegate: Received request to open Timeline window.")
        // Ensure only one timeline window or re-use existing
        if timelineWindowController == nil || timelineWindowController?.window?.isVisible == false {
            timelineWindowController = TimelineWindowController()
        }
        timelineWindowController?.showWindowAndFocus()
    }

    @objc func handleOpenSearchWindow() {
        logger.info("AppDelegate: Received request to open Search window.")
        if searchWindowController == nil || searchWindowController?.window?.isVisible == false {
            searchWindowController = SearchWindowController()
        }
        searchWindowController?.showWindowAndFocus()
    }
    
    @objc func handleOpenSettingsWindow() {
        logger.info("AppDelegate: Received request to open Settings window.")
        // Settings windows are typically single instances.
        if settingsWindowController == nil || settingsWindowController?.window == nil {
             // If controller exists but window is nil (closed), recreate.
            settingsWindowController = SettingsWindowController()
        }
        // Ensure it's brought to front even if already created but not key.
        settingsWindowController?.showWindowAndFocus()
    }
    
    @objc private func appSettingsDidChange(_ notification: Notification) {
        // Check if the launchAtLogin setting was the one that changed.
        if let change = notification.userInfo?[AppSettings.Keys.launchAtLogin] as? Bool {
            logger.info("AppDelegate: Launch at login setting changed to: \(change) via notification.")
            updateLaunchAtLoginStatus(enabled: change)
        }
        // Other settings might trigger service restarts if necessary.
        // For example, if captureInterval changes, ScreenshotService might observe this
        // directly and restart its timer.
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        logger.log("Application will terminate.")
        
        screenshotService.stopCaptureLoop()
        logger.info("ScreenshotService capture loop stopped.")
        
        archiverService.stopPeriodicArchiving()
        logger.info("ArchiverService periodic archiving stopped.")

        logger.info("Application cleanup complete.")
    }

    // MARK: - Global Hotkey
    private func setupGlobalHotkey() {
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] (event) in
            self?.handleGlobalKeyDown(event: event)
        }
        logger.info("Global key down monitor for ad-hoc capture started (Ctrl+Shift+E).")
    }

    private func handleGlobalKeyDown(event: NSEvent) {
        guard event.modifierFlags.contains(.control),
              event.modifierFlags.contains(.shift),
              !event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.option),
              event.keyCode == kVK_ANSI_E else { // kVK_ANSI_E is from Carbon.HIToolbox
            return
        }
        logger.info("Global hotkey (Control + Shift + E) detected for ad-hoc capture.")
        ScreenshotService.shared.captureAndProcessSingleFrame(completion: nil)
    }
    
    // MARK: - XPC Service Listener Setup
    private func startXPCListener() {
        // Create and hold a strong reference to the delegate.
        // Ensure XPCServiceDelegate class is defined and accessible in the main app target.
        self.xpcDelegate = XPCServiceDelegate()

        // Use the service name defined in EidonXPCConstants.
        // This listener runs in the main app's process and vends EidonCaptureServiceProvider.
        self.captureServiceListener = NSXPCListener(machServiceName: EidonXPCConstants.captureServiceName)
        self.captureServiceListener?.delegate = self.xpcDelegate 
        self.captureServiceListener?.resume()
        
        logger.info("Main App XPC Listener initiated for service name: \(EidonXPCConstants.captureServiceName)")
    }

    // MARK: - Launch at Login Helper
    private func updateLaunchAtLoginStatus(enabled: Bool) {
        logger.info("Updating Launch At Login status to: \(enabled)")
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status == .notRegistered {
                        try SMAppService.mainApp.register()
                        logger.info("Successfully registered app for launch at login using SMAppService.")
                    } else {
                        logger.info("App already registered or in a non-registerable state for launch at login: \(SMAppService.mainApp.status.rawValue)")
                    }
                } else {
                    // Check if it's enabled or requires approval before trying to unregister
                    if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                         try SMAppService.mainApp.unregister()
                         logger.info("Successfully unregistered app from launch at login using SMAppService.")
                    } else {
                        logger.info("App not in an enabled/requiresApproval state to unregister for launch at login: \(SMAppService.mainApp.status.rawValue)")
                    }
                }
            } catch {
                logger.error("SMAppService: Failed to update launch at login status: \(error.localizedDescription)")
            }
        } else {
            // Fallback for macOS versions older than 13.0
            // This often involved SMLoginItemSetEnabled, which is deprecated and had complexities with sandboxing.
            // For a modern app, targeting macOS 13+ for this feature simplifies things greatly.
            // If older system support is critical, this part would need a more elaborate (and likely helper-tool based) solution.
            logger.warning("Launch at login for macOS older than 13.0 requires a different implementation (e.g., SMLoginItemSetEnabled or a helper app) which is not fully implemented here.")
            // You might still store the preference, but the actual enabling/disabling would not work on older OS without further code.
        }
    }

     func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
         return false // Keep app running if it's a background utility primarily
     }
}