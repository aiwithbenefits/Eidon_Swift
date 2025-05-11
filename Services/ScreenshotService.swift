import Foundation
import AppKit // For NSImage, NSScreen, NSWorkspace, runningApplication
import CoreGraphics // For CGImage, CGDisplay, CGEvent
import Vision // For potential image hashing algorithms if not using a dedicated lib
import ImageIO // For image saving options
import os.log // Import for Logger
import CoreData // Import for NSFetchRequest

// Simple Difference Hash (dHash) implementation
// For a production app, use a robust, well-tested image hashing library or implement a more sophisticated algorithm.
struct PerceptualHash: Equatable {
    let hashValue: UInt64

    // dHash typically works on a small, grayscale image, e.g., 9x8 pixels to get 8x8 differences.
    private static let dhashWidth = 9
    private static let dhashHeight = 8

    init(nsImage: NSImage) {
        var calculatedHash: UInt64 = 0

        // 1. Resize to dhashWidth x dhashHeight
        // Important: NSImage drawing should be to a context of the target size for proper resizing.
        let targetSize = NSSize(width: PerceptualHash.dhashWidth, height: PerceptualHash.dhashHeight)
        guard let resizedImage = NSImage(size: targetSize, flipped: false, drawingHandler: { bounds in
            nsImage.draw(in: bounds)
            return true
        }), let cgImageResized = resizedImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            self.hashValue = 0 // Error hash
            return
        }


        // 2. Convert to grayscale
        let width = cgImageResized.width
        let height = cgImageResized.height
        // Ensure dimensions match dHash dimensions after potential internal adjustments by cgImage.
        guard width == PerceptualHash.dhashWidth && height == PerceptualHash.dhashHeight else {
            self.hashValue = 0 // Error hash
            return
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        var rawData = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(data: &rawData,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: width, // Each pixel is 1 byte
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            self.hashValue = 0
            return
        }
        context.draw(cgImageResized, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // 3. Compute differences (row-wise)
        // Compare adjacent pixels: pixel[x] > pixel[x+1] ?
        var tempHash: UInt64 = 0
        var bitIndex = 0
        for y in 0..<height {
            for x in 0..<(width - 1) { // Iterate to width-1 for pairs
                if bitIndex >= 64 { break } // Max 64 bits for UInt64
                let leftPixelIndex = y * width + x
                let rightPixelIndex = y * width + (x + 1)
                
                if rawData[leftPixelIndex] > rawData[rightPixelIndex] {
                    tempHash |= (1 << UInt64(bitIndex)) // Build hash bit by bit
                }
                bitIndex += 1
            }
            if bitIndex >= 64 { break }
        }
        calculatedHash = tempHash
        self.hashValue = calculatedHash
    }
    
    init(hashValue: UInt64) { // For default/error hash
        self.hashValue = hashValue
    }

    static func -(lhs: PerceptualHash, rhs: PerceptualHash) -> Int {
        return (lhs.hashValue ^ rhs.hashValue).nonzeroBitCount // Hamming distance
    }
    
    static func fromHex(_ hex: String) -> PerceptualHash { // For default/error phashes
        return PerceptualHash(hashValue: UInt64(hex, radix: 16) ?? 0)
    }
}


class ScreenshotService {

    // MARK: - Configuration (mirrors parts of Python config.py)
    // idleTimeThreshold, screenshotSaveFormat, and screenshotSaveCompressionFactor
    // will now be read from AppSettings.
    private let similarityThresholdMSSIM: Float = 0.85 
    private let minHammingDistance: Int = 7       
    
    private let maxImageWidth: CGFloat = 960.0
    private let maxImageHeight: CGFloat = 600.0

    // MARK: - Properties
    static let shared = ScreenshotService()
    private let ocrService = OCRService.shared
    private let nlpService = NLPService.shared
    private let persistenceController = PersistenceController.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.Eidon.ScreenshotService", category: "ScreenshotService")


    private var captureTimer: Timer?
    private var isCaptureLoopActive: Bool = false
    private var captureGloballyEnabled: Bool = true // True means capture, false means paused

    private var lastCapturedScreenshotsCG: [CGImage?] = [] 
    private var lastCapturedPerceptualHashes: [PerceptualHash?] = []
    
    private let fileManager = FileManager.default
    private var screenshotsPath: URL? {
        // Determine screenshots path (e.g., Application Support/YourApp/screenshots)
        // This should align with your app's data storage strategy
        if let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            logger.error("Could not find Application Support directory.")
            return nil
        }
        let eidonDir = appSupportDir.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.example.EidonApp") // Consistent naming
        let screenshotsDir = eidonDir.appendingPathComponent("screenshots")
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: screenshotsDir.path) {
            do {
                try fileManager.createDirectory(at: screenshotsDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                #if DEBUG
                print("Error creating screenshots directory: \(error)")
                #endif
                return nil
            }
        }
        return screenshotsDir
    }

    // MARK: - Initialization
    private init() {}
        // Note: Consider adding an observer for AppSettings.didChangeNotification if dynamic updates are needed
        // For instance, to re-schedule the timer if captureInterval changes.
    // MARK: - Capture Control
    public func startCaptureLoop(interval: TimeInterval = 3.0) { // Fallback interval if needed, but settings will be primary
        guard !isCaptureLoopActive else {
            logger.info("Capture loop already active.")
            return
        }
        isCaptureLoopActive = true
        captureGloballyEnabled = true
        
        let currentInterval = AppSettings.shared.captureInterval
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            self.initialBaselineCapture() 
            
            // Schedule the timer on the background thread's run loop
            self.captureTimer = Timer(timeInterval: currentInterval, repeats: true) { [weak self] _ in
                self?.captureAndProcessScreenshots()
            }
            guard let timer = self.captureTimer else { return }
            RunLoop.current.add(timer, forMode: .common)
            RunLoop.current.run() 
        }
        logger.info("Capture loop started with interval \(currentInterval, privacy: .public)s (from settings).")
    }

    public func stopCaptureLoop() {
        captureTimer?.invalidate()
        captureTimer = nil
        isCaptureLoopActive = false
        logger.info("Capture loop stopped.")
        // The run loop will exit when the timer is invalidated if it's the only input source on its thread.
    }

    public func pauseCapture() {
        captureGloballyEnabled = false
        logger.info("Screenshot capture PAUSED by user.")
    }

    public func resumeCapture() {
        captureGloballyEnabled = true
        logger.info("Screenshot capture RESUMED by user.")
    }

    public func isCaptureGloballyEnabled() -> Bool {
        return captureGloballyEnabled
    }
    
    private func initialBaselineCapture() {
        let currentScreenshots = takeScreenshotsForAllDisplays()
        if !currentScreenshots.isEmpty {
            self.lastCapturedScreenshotsCG = currentScreenshots
            self.lastCapturedPerceptualHashes = currentScreenshots.map { cgImgOpt in
                cgImgOpt.flatMap { NSImage(cgImage: $0, size: .zero) }.map { PerceptualHash(nsImage: $0) }
            }
            logger.info("Initial screenshot baseline established with \(currentScreenshots.compactMap { $0 }.count) screens.")
        } else {
            logger.warning("Initial baseline capture failed to get any screens.")
        }
    }

    /// Captures the current screen(s), processes, and saves data for a single frame, bypassing idle and similarity checks.
    /// This is intended for ad-hoc captures initiated by the user.
    public func captureAndProcessSingleFrame(completion: ((_ success: Bool) -> Void)? = nil) {
        logger.info("Ad-hoc capture requested. Processing single frame.")

        DispatchQueue.global(qos: .userInitiated).async {
            let currentScreenshotsCG = self.takeScreenshotsForAllDisplays()
            guard !currentScreenshotsCG.isEmpty, currentScreenshotsCG.contains(where: { $0 != nil }) else {
                self.logger.error("Ad-hoc capture: No screens captured or all captures failed.")
                completion?(false)
                return
            }
            
            let activeInfo = self.getActiveApplicationInfo() // Get active info for this ad-hoc capture
            
            // For ad-hoc, we might not want to skip self-view, or make it configurable.
            // For now, let's assume ad-hoc captures always proceed.
            // if let currentBundleID = activeInfo.bundleID, currentBundleID == Bundle.main.bundleIdentifier {
            //     self.logger.info("Ad-hoc capture: Self-view detected. Skipping processing, but considered 'successful' capture.")
            //     completion?(true) 
            //     return
            // }

            let cycleTimestamp = Date() 
            var overallSuccess = true 
            var processedAtLeastOneScreen = false

            for (index, currentCGImageOptional) in currentScreenshotsCG.enumerated() {
                guard let currentCGImage = currentCGImageOptional else {
                    self.logger.warning("Ad-hoc capture: Screen \(index): Capture failed for this screen.")
                    continue // Skip this screen, don't mark overallSuccess false for one screen failure
                }
                processedAtLeastOneScreen = true

                let currentNSImage = NSImage(cgImage: currentCGImage, size: NSSize(width: currentCGImage.width, height: currentCGImage.height))
                let currentThumbnailNSImage = self.resizeImage(currentNSImage, maxWidth: self.maxImageWidth, maxHeight: self.maxImageHeight)

                self.logger.info("Ad-hoc capture: Screen \(index): Processing...")

                let saveSettings = AppSettings.shared.getScreenshotSaveSettings()
                let fileTypeForSave = saveSettings.isPNG ? NSBitmapImageRep.FileType.png : .jpeg
                let compressionFactorForSave = saveSettings.jpegQuality
                let fileExtension = saveSettings.isPNG ? "png" : "jpg"
                // Append "_adhoc" to differentiate from regular captures if timestamps are very close
                let uniqueFilenameComponent = "\(Int(cycleTimestamp.timeIntervalSince1970))_\(index)_\(UUID().uuidString.prefix(8))_adhoc"
                let uniqueFilename = "\(uniqueFilenameComponent).\(fileExtension)"
                
                var savedImageURL: URL? = nil
                if let screenshotsDir = self.screenshotsPath {
                    let imagePath = screenshotsDir.appendingPathComponent(uniqueFilename)
                    
                    guard let tiffData = currentThumbnailNSImage.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiffData),
                          let imageData = bitmap.representation(using: fileTypeForSave, properties: [.compressionFactor: compressionFactorForSave as NSNumber]) else {
                        self.logger.error("Ad-hoc capture: Error converting thumbnail for saving \(uniqueFilename, privacy: .public).")
                        overallSuccess = false // Mark as false if critical step fails
                        continue
                    }
                    do {
                        try imageData.write(to: imagePath)
                        savedImageURL = imagePath
                        self.logger.info("Ad-hoc capture: Saved image: \(uniqueFilename, privacy: .public)")
                    } catch {
                        self.logger.error("Ad-hoc capture: Error saving image \(uniqueFilename, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        overallSuccess = false
                        continue
                    }
                } else {
                    self.logger.error("Ad-hoc capture: Screenshots path not available. Cannot save images.")
                    overallSuccess = false 
                    break // Critical failure, stop processing further screens
                }

                var extractedText: String?
                switch self.ocrService.extractText(from: currentCGImage) {
                case .success(let text): extractedText = text
                case .failure(let error): self.logger.warning("Ad-hoc capture OCR failed for \(uniqueFilename, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
                
                var embeddingData: Data?
                if let text = extractedText, !text.isEmpty {
                    switch self.nlpService.getSentenceEmbedding(for: text) {
                    case .success(let vector): embeddingData = vector.withUnsafeBufferPointer { Data(buffer: $0) }
                    case .failure(let error): self.logger.warning("Ad-hoc capture embedding failed for \(uniqueFilename, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    }
                }

                let smartTitle = AppUtils.generateSmartTitle(
                    appName: activeInfo.name,
                    windowTitle: activeInfo.title,
                    url: activeInfo.url
                )
                
                let dbContext = self.persistenceController.newBackgroundContext()
                // For ad-hoc captures, we usually want to save it regardless of recent identical captures.
                // The existing `saveEntryToCoreData` has a duplicate check based on timestamp & filename.
                // The "_adhoc" in filename should make it unique from timed captures.
                // If an ad-hoc capture is triggered twice rapidly, the duplicate check will prevent exact re-save.
                self.saveEntryToCoreData(context: dbContext, timestamp: cycleTimestamp, appInfo: activeInfo, smartTitle: smartTitle, ocrText: extractedText, embedding: embeddingData, savedImageURL: savedImageURL)
            }
            
            // Overall success is true if at least one screen was processed without critical error.
            completion?(overallSuccess && processedAtLeastOneScreen)
        }
    }


    // MARK: - System Interaction
    private func getUserIdleTime() -> TimeInterval {
        // Uses CGEventSourceSecondsSinceLastEventType, similar to Python version
        var idleTime: TimeInterval = 0
        if let eventSource = CGEventSource(stateID: .combinedSessionState) {
            idleTime = eventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .null) // .null means any event type
        }
        return idleTime
    }
    
    private func getActiveApplicationInfo() -> (name: String?, bundleID: String?, title: String?, url: URL?) {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return (nil, nil, nil, nil)
        }
        let appName = frontmostApp.localizedName
        let bundleIdentifier = frontmostApp.bundleIdentifier
        var windowTitle: String? = nil
        var pageURL: URL? = nil

        // Getting window title (requires accessibility permissions or specific window querying)
        // This is a simplified placeholder; robust title fetching is complex.
        // One common approach is to use CGWindowListCopyWindowInfo and filter for the frontmost app's main window.
        let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements, .optionOnScreenOnly)
        let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as NSArray?
        if let windowList = windowListInfo {
            for windowInfo in windowList {
                if let dict = windowInfo as? NSDictionary,
                   let ownerPID = dict[kCGWindowOwnerPID as String] as? pid_t,
                   ownerPID == frontmostApp.processIdentifier,
                   let name = dict[kCGWindowName as String] as? String,
                   !name.isEmpty {
                    windowTitle = name
                    break // Found the likely main window
                }
            }
        }

        // Getting URL for known browsers (requires AppleScript or other inter-app communication)
        if let bundleID = bundleIdentifier {
            switch bundleID {
            case "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "com.microsoft.edgemac", "org.mozilla.firefox":
                let scriptSource: String?
                switch bundleID {
                    case "com.apple.Safari": scriptSource = "tell application \"Safari\" to return URL of front document"
                    case "com.google.Chrome": scriptSource = "tell application \"Google Chrome\" to return URL of active tab of front window"
                    case "company.thebrowser.Browser": scriptSource = "tell application \"Arc\" to return URL of active tab of front window" // For Arc Browser
                    case "com.microsoft.edgemac": scriptSource = "tell application \"Microsoft Edge\" to return URL of active tab of front window"
                    case "org.mozilla.firefox": scriptSource = "tell application \"Firefox\" to return URL of active tab of front window"
                    default: scriptSource = nil
                }
                if let source = scriptSource, let script = NSAppleScript(source: source) {
                    var errorDict: NSDictionary?
                    if let output = script.executeAndReturnError(&errorDict).stringValue, !output.isEmpty {
                        pageURL = URL(string: output)
                    } else if let error = errorDict {
                        logger.debug("AppleScript Error for \(bundleID, privacy: .public): \(error.description, privacy: .public)")
                    }
                }
            default:
                break
            }
        }
        return (appName, bundleIdentifier, windowTitle, pageURL)
    }

    // MARK: - Screenshot Capture & Processing
    private func takeScreenshotsForAllDisplays() -> [CGImage?] {
        var images: [CGImage?] = []
        for screen in NSScreen.screens {
            // Capture entire screen bounds
            if let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               let cgImage = CGDisplayCreateImage(displayID) {
                images.append(cgImage)
            } else {
                logger.warning("Failed to capture screenshot for screen: \(screen.localizedName)")
                images.append(nil) 
            }
        }
        return images
    }
    
    private func resizeImage(_ image: NSImage, maxWidth: CGFloat, maxHeight: CGFloat) -> NSImage {
        let oldWidth = image.size.width
        let oldHeight = image.size.height
        
        guard oldWidth > 0 && oldHeight > 0 else { return image } // Avoid division by zero

        let scaleFactorWidth = maxWidth / oldWidth
        let scaleFactorHeight = maxHeight / oldHeight
        let scaleFactor = min(scaleFactorWidth, scaleFactorHeight, 1.0) // Don't upscale

        if scaleFactor == 1.0 { return image } // No resize needed

        let newWidth = oldWidth * scaleFactor
        let newHeight = oldHeight * scaleFactor
        
        let newImage = NSImage(size: NSSize(width: newWidth, height: newHeight))
        newImage.lockFocus()
        image.draw(in: NSRect(x: 0, y: 0, width: newWidth, height: newHeight),
                   from: NSRect(x: 0, y: 0, width: oldWidth, height: oldHeight),
                   operation: .sourceOver,
                   fraction: 1.0)
        newImage.unlockFocus()
        return newImage
    }
    
    // MARK: - Image Similarity (Windowed Grayscale SSIM/MSSIM)
    // This implementation provides a windowed SSIM calculation. For true MSSIM as per literature,
    // specific window sizes (e.g., 8x8 or 11x11), Gaussian weighting of windows, and potentially
    // multi-scale analysis would be required. This version uses non-overlapping windows (tiles).

    /// Converts a CGImage to a buffer of grayscale pixel values.
    private func convertToGrayscalePixelBuffer(cgImage: CGImage) -> (pixels: [Float], width: Int, height: Int)? {
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0 && height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        // Using Float for pixel data to work with Accelerate framework easily.
        var floatPixelData = [Float](repeating: 0, count: width * height)
        
        // Create a context with Float components.
        // Note: CGContext for float data is more complex. Easier to get UInt8 then convert.
        var rawDataUInt8 = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &rawDataUInt8,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            logger.error("Failed to create grayscale CGContext for pixel buffer generation.")
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Convert UInt8 pixel data to Float for Accelerate
        vDSP.convertElements(of: rawDataUInt8, to: &floatPixelData)
        
        return (floatPixelData, width, height)
    }

    // Helper struct for statistics, calculated using Accelerate
    private struct WindowStats {
        let mean: Float
        let variance: Float
    }

    private func calculateStats(pixels: [Float]) -> WindowStats? {
        guard !pixels.isEmpty else { return nil }
        var mean: Float = 0
        var stdDev: Float = 0 // vDSP_rmsqv calculates root mean square, which is std dev if mean is 0.
                              // For variance, we need E[X^2] - (E[X])^2

        // Calculate E[X] (mean)
        vDSP_meanv(pixels, 1, &mean, vDSP_Length(pixels.count))

        // Calculate E[X^2] (mean of squares)
        var meanOfSquares: Float = 0
        vDSP_measqv(pixels, 1, &meanOfSquares, vDSP_Length(pixels.count))
        
        let variance = meanOfSquares - (mean * mean)
        
        return WindowStats(mean: mean, variance: max(0, variance)) // Ensure variance is non-negative
    }

    private func calculateCovariance(pixels1: [Float], stats1: WindowStats, pixels2: [Float], stats2: WindowStats) -> Float? {
        guard pixels1.count == pixels2.count, !pixels1.isEmpty else { return nil }
        
        // Cov(X,Y) = E[(X-muX)(Y-muY)]
        // Create (X - muX) and (Y - muY) vectors
        var X_minus_muX = [Float](repeating: 0, count: pixels1.count)
        var Y_minus_muY = [Float](repeating: 0, count: pixels2.count)
        
        var negMeanX = -stats1.mean
        var negMeanY = -stats2.mean
        
        vDSP_vsadd(pixels1, 1, &negMeanX, &X_minus_muX, 1, vDSP_Length(pixels1.count))
        vDSP_vsadd(pixels2, 1, &negMeanY, &Y_minus_muY, 1, vDSP_Length(pixels2.count))
        
        // Multiply (X-muX) * (Y-muY) element-wise
        var productXY = [Float](repeating: 0, count: pixels1.count)
        vDSP_vmul(X_minus_muX, 1, Y_minus_muY, 1, &productXY, 1, vDSP_Length(pixels1.count))
        
        // Calculate E[productXY] (mean of the product vector)
        var covariance: Float = 0
        vDSP_meanv(productXY, 1, &covariance, vDSP_Length(productXY.count))
        
        return covariance
    }

    /// Calculates SSIM for a single pair of grayscale float pixel buffers (representing a window).
    private func _calculateSSIMForPixelBuffers(
        pixels1: [Float], stats1: WindowStats,
        pixels2: [Float], stats2: WindowStats
    ) -> Float? {
        
        let L: Float = 255.0 // Dynamic range of original UInt8 pixel values
        let K1: Float = 0.01
        let K2: Float = 0.03
        let C1 = pow(K1 * L, 2)
        let C2 = pow(K2 * L, 2)

        guard let sigma12 = calculateCovariance(pixels1: pixels1, stats1: stats1, pixels2: pixels2, stats2: stats2) else {
            logger.warning("SSIM: Could not calculate covariance.")
            return 0.0 // Or handle as error
        }

        let mu1_sq = pow(stats1.mean, 2)
        let mu2_sq = pow(stats2.mean, 2)
        let sigma1_sq = stats1.variance
        let sigma2_sq = stats2.variance

        let numerator = (2 * stats1.mean * stats2.mean + C1) * (2 * sigma12 + C2)
        let denominator = (mu1_sq + mu2_sq + C1) * (sigma1_sq + sigma2_sq + C2)

        if denominator == 0 {
            return numerator == 0 ? 1.0 : 0.0 // If both are zero (e.g. identical black windows), SSIM is 1.
        }
        
        let ssim = numerator / denominator
        return max(0, min(1, ssim)) // Clamp to [0, 1]
    }

    // The old grid-based calculateMeanSSIM method has been removed.
    // It is replaced by calculateSlidingWindowSSIM in the extension below.

    @objc private func captureAndProcessScreenshots() {
        guard captureGloballyEnabled, isCaptureLoopActive else {
            // logger.debug("Capture globally disabled or loop not active. Skipping.")
            return
        }

        let idleSeconds = getUserIdleTime() // Read current idle time
        let currentIdleTimeThreshold = AppSettings.shared.idleTimeThreshold // Get threshold from settings
        if idleSeconds >= currentIdleTimeThreshold {
            return
        }

        let currentScreenshotsCG = takeScreenshotsForAllDisplays()
        guard !currentScreenshotsCG.isEmpty, currentScreenshotsCG.contains(where: { $0 != nil }) else {
            logger.info("No screens captured or all captures failed.")
            return
        }
        
        let activeInfo = getActiveApplicationInfo()
        
        if let currentBundleID = activeInfo.bundleID, currentBundleID == Bundle.main.bundleIdentifier {
            logger.info("Self-view detected. Skipping capture.")
            self.lastCapturedScreenshotsCG = currentScreenshotsCG // Update baseline
            self.lastCapturedPerceptualHashes = currentScreenshotsCG.map { $0.flatMap { NSImage(cgImage: $0, size: .zero)}.map { PerceptualHash(nsImage: $0) } }
            return
        }

        if lastCapturedScreenshotsCG.count != currentScreenshotsCG.count {
            logger.info("Monitor configuration changed. Resetting baseline.")
            lastCapturedScreenshotsCG = currentScreenshotsCG
            lastCapturedPerceptualHashes = currentScreenshotsCG.map { $0.flatMap { NSImage(cgImage: $0, size: .zero)}.map { PerceptualHash(nsImage: $0) } }
            return // Skip processing this cycle, baseline updated
        }
        
        var somethingProcessedThisCycle = false
        let cycleTimestamp = Date() // Timestamp for this capture batch

        for (index, currentCGImageOptional) in currentScreenshotsCG.enumerated() {
            guard let currentCGImage = currentCGImageOptional else {
                logger.warning("Screen \(index): Capture failed for this screen.")
                // Ensure baseline for this screen is also cleared or handled
                if index < lastCapturedScreenshotsCG.count { lastCapturedScreenshotsCG[index] = nil }
                if index < lastCapturedPerceptualHashes.count { lastCapturedPerceptualHashes[index] = nil }
                continue
            }

            let currentNSImage = NSImage(cgImage: currentCGImage, size: NSSize(width: currentCGImage.width, height: currentCGImage.height))
            let currentThumbnailNSImage = resizeImage(currentNSImage, maxWidth: maxImageWidth, maxHeight: maxImageHeight)
            let currentPHash = PerceptualHash(nsImage: currentThumbnailNSImage) // Use the resized NSImage for phash

            var isSimilar = false
            if index < lastCapturedScreenshotsCG.count, let lastCGImg = lastCapturedScreenshotsCG[index],
               index < lastCapturedPerceptualHashes.count, let lastPH = lastCapturedPerceptualHashes[index] {
                
                let hammingDistance = currentPHash - lastPH
                // Use the new Sliding Window SSIM calculation.
                // windowSize: 8, stride: 4 (tune for performance vs. accuracy)
                // A stride of 1 would be true pixel-by-pixel but very slow.
                // A stride equal to windowSize would be non-overlapping tiles.
                let ssimValue = calculateSlidingWindowSSIM(cgImage1: currentCGImage, cgImage2: lastCGImg, windowSize: 8, stride: 4)
                
                if ssimValue >= similarityThresholdMSSIM && hammingDistance <= minHammingDistance {
                    isSimilar = true
                }
                 logger.debug("Screen \(index): Sliding Window SSIM: \(ssimValue, privacy: .public), Hamming: \(hammingDistance). Similar: \(isSimilar)")
            } else {
                 logger.debug("Screen \\(index): No previous data for comparison, processing as new.")
            }

            if isSimilar {
                continue // Skip this screen
            }

            somethingProcessedThisCycle = true
            logger.info("Screen \(index): Change detected. Processing...")

            // Update baselines
            if index < lastCapturedScreenshotsCG.count {
                lastCapturedScreenshotsCG[index] = currentCGImage
            } else { // Should not happen if counts match
                lastCapturedScreenshotsCG.append(currentCGImage)
            }
            if index < lastCapturedPerceptualHashes.count {
                lastCapturedPerceptualHashes[index] = currentPHash
            } else {
                lastCapturedPerceptualHashes.append(currentPHash)
            }
            
            // --- Save image, OCR, Embed, Store to DB ---
            let saveSettings = AppSettings.shared.getScreenshotSaveSettings()
            let fileTypeForSave = saveSettings.isPNG ? NSBitmapImageRep.FileType.png : .jpeg
            let compressionFactorForSave = saveSettings.jpegQuality
            let fileExtension = saveSettings.isPNG ? "png" : "jpg"
            let uniqueFilenameComponent = "\(Int(cycleTimestamp.timeIntervalSince1970))_\(index)_\(UUID().uuidString.prefix(8))"
            let uniqueFilename = "\(uniqueFilenameComponent).\(fileExtension)"
            
            var savedImageURL: URL? = nil
            if let screenshotsDir = self.screenshotsPath {
                let imagePath = screenshotsDir.appendingPathComponent(uniqueFilename)
                guard let tiffData = currentThumbnailNSImage.tiffRepresentation, 
                      let bitmap = NSBitmapImageRep(data: tiffData),
                      let imageData = bitmap.representation(using: fileTypeForSave, properties: [.compressionFactor: compressionFactorForSave as NSNumber]) else {
                    logger.error("Error converting thumbnail to \(fileExtension, privacy: .public) data for saving \(uniqueFilename, privacy: .public).")
                    continue
                }
                do {
                    try imageData.write(to: imagePath)
                    savedImageURL = imagePath 
                    logger.info("Saved image: \(uniqueFilename, privacy: .public)")
                } catch {
                    logger.error("Error saving image \(uniqueFilename, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    continue 
                }
            }

            var extractedText: String?
            switch ocrService.extractText(from: currentCGImage) { 
            case .success(let text): extractedText = text
            case .failure(let error): logger.warning("OCR failed for \(uniqueFilename, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            
            var embeddingData: Data?
            if let text = extractedText, !text.isEmpty {
                switch nlpService.getSentenceEmbedding(for: text) {
                case .success(let vector): embeddingData = vector.withUnsafeBufferPointer { Data(buffer: $0) }
                case .failure(let error): logger.warning("Embedding failed for \(uniqueFilename, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }

            let smartTitle = AppUtils.generateSmartTitle( // Call as static method
                appName: activeInfo.name,
                windowTitle: activeInfo.title,
                url: activeInfo.url
            )
            
            // --- Database Insertion ---
            let context = persistenceController.newBackgroundContext() // Get a background context
            context.perform { // Asynchronously perform on the context's queue
                // Check if an entry with this exact timestamp and filename already exists
                // This is a more specific check than just timestamp if multiple screens are processed rapidly
                // and assigned slightly offset timestamps or if filenames are the key differentiator.
                // However, with cycleTimestamp being the same for all screens in a batch,
                // a unique constraint on timestamp in Core Data is still the primary guard.
            
                let dbContext = self.persistenceController.newBackgroundContext()
                // Pass activeInfo and smartTitle which are relevant for this specific entry context
                self.saveEntryToCoreData(context: dbContext, timestamp: cycleTimestamp, appInfo: activeInfo, smartTitle: smartTitle, ocrText: extractedText, embedding: embeddingData, savedImageURL: savedImageURL)

            } 
        }
    }

    // MARK: - Extended Image Similarity Logic (Sliding Window SSIM)
    extension ScreenshotService {

        /// Extracts a window of pixel data from a larger grayscale float pixel buffer.
        private func extractWindow(fromPixelBuffer buffer: [Float], imageWidth: Int, windowRect: CGRect) -> [Float]? {
            let rectX = Int(windowRect.origin.x)
            let rectY = Int(windowRect.origin.y)
            let rectWidth = Int(windowRect.width)
            let rectHeight = Int(windowRect.height)

            guard rectX >= 0, rectY >= 0,
                  rectX + rectWidth <= imageWidth,
                  rectY + rectHeight <= (buffer.count / imageWidth) else {
                // self.logger.error("Window extraction out of bounds.") // Log sparingly if called often
                return nil
            }

            var windowPixels = [Float](repeating: 0, count: rectWidth * rectHeight)
            for y_win in 0..<rectHeight {
                for x_win in 0..<rectWidth {
                    let bufferIndex = (rectY + y_win) * imageWidth + (rectX + x_win)
                    let windowIndex = y_win * rectWidth + x_win
                    windowPixels[windowIndex] = buffer[bufferIndex]
                }
            }
            return windowPixels
        }

        private func calculateSlidingWindowSSIM(cgImage1: CGImage, cgImage2: CGImage, windowSize: Int, stride: Int) -> Float {
            guard cgImage1.width == cgImage2.width && cgImage1.height == cgImage2.height else {
                logger.debug("SlidingWindowSSIM: Image dimensions do not match. (\(cgImage1.width)x\(cgImage1.height) vs \(cgImage2.width)x\(cgImage2.height))")
                return 0.0
            }
            guard windowSize > 0, stride > 0 else {
                logger.warning("SlidingWindowSSIM: Window size and stride must be positive.")
                return 0.0
            }

            guard let grayBuffer1 = convertToGrayscalePixelBuffer(cgImage: cgImage1),
                  let grayBuffer2 = convertToGrayscalePixelBuffer(cgImage: cgImage2) else {
                logger.error("SlidingWindowSSIM: Failed to convert images to grayscale buffers.")
                return 0.0
            }

            let imageWidth = cgImage1.width
            let imageHeight = cgImage1.height

            guard windowSize <= imageWidth && windowSize <= imageHeight else {
                logger.warning("SlidingWindowSSIM: Window size (\(windowSize)) is larger than image dimensions (\(imageWidth)x\(imageHeight)). Falling back to global SSIM.")
                // Fallback to global SSIM if window is too big for sliding.
                if let stats1 = calculateStats(pixels: grayBuffer1.pixels),
                   let stats2 = calculateStats(pixels: grayBuffer2.pixels) {
                    return _calculateSSIMForPixelBuffers(pixels1: grayBuffer1.pixels, stats1: stats1, pixels2: grayBuffer2.pixels, stats2: stats2) ?? 0.0
                }
                return 0.0
            }

            var totalSSIM: Float = 0
            var validWindowCount: Int = 0

            // Using Swift.stride to avoid ambiguity if there's another 'stride' variable in scope
            for y_coord in Swift.stride(from: 0, to: imageHeight - windowSize + 1, by: stride) {
                for x_coord in Swift.stride(from: 0, to: imageWidth - windowSize + 1, by: stride) {
                    let windowRect = CGRect(x: x_coord, y: y_coord, width: windowSize, height: windowSize)

                    guard let window1Pixels = extractWindow(fromPixelBuffer: grayBuffer1.pixels, imageWidth: grayBuffer1.width, windowRect: windowRect),
                          let window2Pixels = extractWindow(fromPixelBuffer: grayBuffer2.pixels, imageWidth: grayBuffer2.width, windowRect: windowRect),
                          let stats1 = calculateStats(pixels: window1Pixels),
                          let stats2 = calculateStats(pixels: window2Pixels) else {
                        // self.logger.debug("Skipping window at (\(x_coord), \(y_coord)) due to extraction/stats error.") // Log sparingly
                        continue 
                    }
                
                    if let ssimForWindow = _calculateSSIMForPixelBuffers(pixels1: window1Pixels, stats1: stats1, pixels2: window2Pixels, stats2: stats2) {
                        totalSSIM += ssimForWindow
                        validWindowCount += 1
                    }
                }
            }
        
            guard validWindowCount > 0 else {
                logger.warning("SlidingWindowSSIM: No valid windows processed. This might happen if stride is too large or image too small for given window/stride.")
                // Fallback to global SSIM if no windows were processed but images were valid.
                if let stats1 = calculateStats(pixels: grayBuffer1.pixels),
                   let stats2 = calculateStats(pixels: grayBuffer2.pixels) {
                    return _calculateSSIMForPixelBuffers(pixels1: grayBuffer1.pixels, stats1: stats1, pixels2: grayBuffer2.pixels, stats2: stats2) ?? 0.0
                }
                return 0.0
            }
            return totalSSIM / Float(validWindowCount)
        }
    }

    // Helper method to encapsulate Core Data saving logic, callable from multiple places
    extension ScreenshotService {
        private func saveEntryToCoreData(context: NSManagedObjectContext, timestamp: Date, appInfo: (name: String?, bundleID: String?, title: String?, url: URL?), smartTitle: String, ocrText: String?, embedding: Data?, savedImageURL: URL?) {
        context.perform {
            // Check if an entry with this exact timestamp and filename already exists.
            // This is important for the regular capture loop. For ad-hoc, filename might be different.
            let fetchRequest: NSFetchRequest<EidonEntryEntity> = EidonEntryEntity.fetchRequest()
            let filenameForDBCheck = savedImageURL?.lastPathComponent ?? "" // Use a non-optional string for predicate

            // Only perform strict duplicate check if filename is not empty
            if !filenameForDBCheck.isEmpty {
                fetchRequest.predicate = NSPredicate(format: "timestamp == %@ AND filename == %@", timestamp as NSDate, filenameForDBCheck)
                fetchRequest.fetchLimit = 1

                do {
                    let existingEntries = try context.fetch(fetchRequest)
                    if !existingEntries.isEmpty {
                        self.logger.info("ScreenshotService: DB entry for timestamp \(timestamp, privacy: .public) and filename \(filenameForDBCheck, privacy: .public) likely already exists. Skipping insert.")
                        // If file was saved but DB entry exists, consider deleting the new file
                        if let tempSavedURL = savedImageURL, self.fileManager.fileExists(atPath: tempSavedURL.path) {
                            try? self.fileManager.removeItem(at: tempSavedURL)
                            self.logger.info("Removed duplicate image file: \(tempSavedURL.lastPathComponent, privacy: .public) due to existing DB entry.")
                        }
                        return // Exit if entry already exists
                    }
                } catch {
                    self.logger.error("ScreenshotService: Error fetching existing entry for \(filenameForDBCheck, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    // Proceed with attempting to save, as this check is a safeguard.
                }
            }


            let newEntry = EidonEntryEntity(context: context)
            newEntry.id = UUID()
            newEntry.timestamp = timestamp
            newEntry.app = appInfo.name
            newEntry.title = smartTitle
            newEntry.text = ocrText
            newEntry.embedding = embedding
            newEntry.filename = savedImageURL?.lastPathComponent
            newEntry.pageURL = appInfo.url?.absoluteString
            newEntry.isArchived = false

            do {
                try context.save()
                self.logger.info("Successfully saved new entry to Core Data for file: \(savedImageURL?.lastPathComponent ?? "N/A", privacy: .public)")
            } catch {
                let nsError = error as NSError
                self.logger.error("Failed to save Core Data context for file \(savedImageURL?.lastPathComponent ?? "N/A", privacy: .public): \(nsError.localizedDescription, privacy: .public), \(nsError.userInfo, privacy: .public)")
                // If DB save fails, consider deleting the saved image file to prevent orphans
                if let imgURL = savedImageURL, self.fileManager.fileExists(atPath: imgURL.path) {
                    do {
                        try self.fileManager.removeItem(at: imgURL)
                        self.logger.info("Deleted image file \(imgURL.lastPathComponent, privacy: .public) due to DB save failure.")
                    } catch let removeError {
                        self.logger.error("Error deleting image file \(imgURL.lastPathComponent, privacy: .public) after DB save failure: \(removeError.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
    }
}

#if canImport(AppKit)
// This extension is fine here or in a dedicated extensions file.
// It was commented out in the original context but is useful.
extension NSImage {
    var cgImage: CGImage? {
        var rect = NSRect(origin: .zero, size: self.size)
        return self.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
#endif
            // Potentially adjust next capture interval if something was processed
        }
    }
    
    // MARK: - Smart Title Generation (Moved to AppUtils)
    // This method is now expected to be called as AppUtils.generateSmartTitle(...)
    // The implementation has been moved to AppUtils.swift
}

// MARK: - NSImage Extension for CGImage (if not using AppKit extensions elsewhere)
// This might already exist or be preferred in a separate AppKit extensions file.
#if canImport(AppKit)
extension NSImage {
    var cgImage: CGImage? {
        var rect = NSRect(origin: .zero, size: self.size)
        return self.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
#endif
        let isBrowser = browserAppNames.contains { appNameLower.contains($0) }

        if isBrowser, let pageURL = url {
            let urlString = pageURL.absoluteString
            if !originalWindowTitle.isEmpty &&
               originalWindowTitle.lowercased() != urlString.lowercased() &&
               originalWindowTitle.lowercased() != "new tab" {
                
                var cleanedTitle = originalWindowTitle
                let suffixesToRemove = [
                    " - \(appName ?? "")", " - Google Chrome", " - Mozilla Firefox", " - Safari",
                    " - Microsoft Edge", " - Arc"
                ].filter { !(appName ?? "").isEmpty || !$0.contains("appName") }

                for suffix in suffixesToRemove {
                    if cleanedTitle.hasSuffix(suffix) {
                        cleanedTitle = String(cleanedTitle.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                    }
                }
                if !cleanedTitle.isEmpty && cleanedTitle.lowercased() != urlString.lowercased() {
                    return cleanedTitle
                }
            }
            
            let pathComponents = pageURL.pathComponents.filter { $0 != "/" }
            if let lastPathComponent = pathComponents.last, lastPathComponent.contains(".") {
                return URL(fileURLWithPath: lastPathComponent).deletingPathExtension().lastPathComponent // Decoded filename without extension
            }
            
            var titleFromURL = pageURL.host ?? ""
            if let firstPathComponent = pathComponents.first, !firstPathComponent.isEmpty {
                titleFromURL += "/\(firstPathComponent.removingPercentEncoding ?? firstPathComponent)"
            }
            
            if !titleFromURL.isEmpty { return titleFromURL }
        }

        let commonFileExtensions = [
            ".py", ".js", ".ts", ".html", ".css", ".json", ".xml", ".yaml", ".md", ".txt",
            ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
            ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".mov", ".mp4"
        ]

        let firstPartOfTitle = originalWindowTitle.components(separatedBy: " - ").first?.trimmingCharacters(in: .whitespaces) ?? ""
        if commonFileExtensions.contains(where: { firstPartOfTitle.lowercased().hasSuffix($0) }) {
            return firstPartOfTitle
        }
        if commonFileExtensions.contains(where: { originalWindowTitle.lowercased().hasSuffix($0) }) {
            return originalWindowTitle
        }
        
        if appNameLower.contains("finder") && !originalWindowTitle.isEmpty && originalWindowTitle.lowercased() != "finder" {
            return originalWindowTitle
        }

        if !originalWindowTitle.isEmpty && (appNameLower.isEmpty || originalWindowTitle.lowercased() != appNameLower) {
            return originalWindowTitle
        }
        
        return appName ?? "Untitled Capture"
    }
}
```