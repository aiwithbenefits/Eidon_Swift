import Foundation

struct AppSettings {

    static let shared = AppSettings()
    private let defaults = UserDefaults.standard

    // MARK: - Keys
    enum Keys {
        static let captureInterval = "captureInterval"
        static let idleTimeThreshold = "idleTimeThreshold"
        // For ScreenshotService format/quality
        static let screenshotFormatPNG = "screenshotFormatPNG" // Bool: true for PNG, false for JPEG
        static let jpegCompressionFactor = "jpegCompressionFactor" // Float: 0.0 to 1.0
        // Similarity thresholds (advanced, maybe not in first version of UI)
        // static let similarityThresholdSSIM = "similarityThresholdSSIM"
        // static let minHammingDistance = "minHammingDistance"
        static let archiveColdDays = "archiveColdDays"
        static let archiveIntervalHours = "archiveIntervalHours" // How often archiver runs
        static let launchAtLogin = "launchAtLogin"
    }
    
    // MARK: - Notification Names
    static let didChangeNotification = Notification.Name("com.eidon.appSettingsDidChangeNotification")

    // MARK: - Defaults
    struct Defaults {
        static let captureInterval: TimeInterval = 5.0 // Default 5 seconds
        static let idleTimeThreshold: TimeInterval = 60.0 // Default 60 seconds
        static let screenshotFormatPNG: Bool = true // Default to PNG
        static let jpegCompressionFactor: Float = 0.8 // Default 0.8 for JPEG if used
        // static let similarityThresholdSSIM: Float = 0.85
        // static let minHammingDistance: Int = 7
        static let archiveColdDays: Int = 30 // Default 30 days
        static let archiveIntervalHours: Int = 6 // Default: run archiver every 6 hours
        static let launchAtLogin: Bool = false
    }

    // MARK: - Computed Properties (Getters & Setters)

    var captureInterval: TimeInterval {
        get { defaults.object(forKey: Keys.captureInterval) as? TimeInterval ?? Defaults.captureInterval }
        set { defaults.set(newValue, forKey: Keys.captureInterval); postDidChangeNotification() }
    }

    var idleTimeThreshold: TimeInterval {
        get { defaults.object(forKey: Keys.idleTimeThreshold) as? TimeInterval ?? Defaults.idleTimeThreshold }
        set { defaults.set(newValue, forKey: Keys.idleTimeThreshold); postDidChangeNotification() }
    }
    
    var screenshotFormatIsPNG: Bool {
        get { defaults.object(forKey: Keys.screenshotFormatPNG) as? Bool ?? Defaults.screenshotFormatPNG }
        set { defaults.set(newValue, forKey: Keys.screenshotFormatPNG); postDidChangeNotification() }
    }

    var jpegCompressionFactor: Float {
        get { defaults.object(forKey: Keys.jpegCompressionFactor) as? Float ?? Defaults.jpegCompressionFactor }
        set { defaults.set(newValue, forKey: Keys.jpegCompressionFactor); postDidChangeNotification() }
    }

    var archiveColdDays: Int {
        // Ensure default if 0 and not explicitly set by user before (UserDefaults returns 0 for non-existent int)
        get { 
            if defaults.object(forKey: Keys.archiveColdDays) == nil { return Defaults.archiveColdDays }
            return defaults.integer(forKey: Keys.archiveColdDays) 
        }
        set { defaults.set(newValue, forKey: Keys.archiveColdDays); postDidChangeNotification() }
    }
    
    var archiveIntervalHours: Int {
        get { 
            if defaults.object(forKey: Keys.archiveIntervalHours) == nil { return Defaults.archiveIntervalHours }
            return defaults.integer(forKey: Keys.archiveIntervalHours) 
        }
        set { defaults.set(newValue, forKey: Keys.archiveIntervalHours); postDidChangeNotification() }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) } // Defaults to false if not set
        set {
            defaults.set(newValue, forKey: Keys.launchAtLogin)
            // Actual logic to add/remove from login items needs to be implemented elsewhere (e.g., AppDelegate or a helper)
            // This just stores the preference.
            postDidChangeNotification(userInfo: [Keys.launchAtLogin: newValue]) // Send specific info for this change
        }
    }
    
    // MARK: - Initialization and Migration
    init() {
        // Register default values to ensure they are available if not yet set by the user.
        // This is important so that getters return the default rather than 0 or false for unset values.
        defaults.register(defaults: [
            Keys.captureInterval: Defaults.captureInterval,
            Keys.idleTimeThreshold: Defaults.idleTimeThreshold,
            Keys.screenshotFormatPNG: Defaults.screenshotFormatPNG,
            Keys.jpegCompressionFactor: Defaults.jpegCompressionFactor,
            Keys.archiveColdDays: Defaults.archiveColdDays,
            Keys.archiveIntervalHours: Defaults.archiveIntervalHours,
            Keys.launchAtLogin: Defaults.launchAtLogin // Default for launchAtLogin is false
        ])
    }
    
    private func postDidChangeNotification(userInfo: [AnyHashable: Any]? = nil) {
        NotificationCenter.default.post(name: AppSettings.didChangeNotification, object: self, userInfo: userInfo)
    }
    
    // MARK: - For Services to read settings easily
    // Example: ScreenshotService specific settings
    func getScreenshotSaveSettings() -> (isPNG: Bool, jpegQuality: Float) {
        // jpegCompressionFactor is from 0.0 (low) to 1.0 (high) for NSBitmapImageRep
        return (screenshotFormatIsPNG, jpegCompressionFactor)
    }
}