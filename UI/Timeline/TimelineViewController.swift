import Cocoa
import CoreData
import os.log

class TimelineViewController: NSViewController {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.Eidon.Timeline", category: "TimelineViewController")
    private let persistenceController = PersistenceController.shared

    // UI Elements
    private var discreteSlider: NSSlider!
    private var sliderValueLabel: NSTextField!
    private var timestampImageView: NSImageView!
    
    // Metadata UI Elements - Replaced NSTextView
    private var appIconImageView: NSImageView!
    private var appNameLabel: NSTextField!
    private var titleLabel: NSTextField! // Changed from metadataTextView
    private var urlLabel: NSTextField!    // New label for URL
    private var metadataTextStackView: NSStackView! // To hold the text labels
    private var overallMetadataStackView: NSStackView! // To hold icon and textLabelsStackView

    private var timestamps: [Date] = []
    private var currentEntry: EidonEntryEntity?
    private var lastFetchedTimestampCount: Int = 0
    private var clickableURL: URL? // For clickable URL

    private var screenshotsPathURL: URL? {
        guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let eidonDir = appSupportDir.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.example.EidonApp")
        return eidonDir.appendingPathComponent("screenshots")
    }
    
    private var archivePathURL: URL? {
         guard let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let eidonDir = appSupportDir.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.example.EidonApp")
        return eidonDir.appendingPathComponent("archive")
    }

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadTimestamps()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCoreDataChange(_:)),
            name: .NSManagedObjectContextObjectsDidChange,
            object: persistenceController.viewContext
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleCoreDataChange(_ notification: Notification) {
        if let insertedObjects = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>,
           insertedObjects.contains(where: { $0 is EidonEntryEntity }) {
            logger.debug("Core Data change detected, reloading timestamps for timeline.")
            let newCount = fetchTimestampCount()
            if newCount != lastFetchedTimestampCount {
                 loadTimestamps()
            }
        }
    }
    
    private func fetchTimestampCount() -> Int {
        let context = persistenceController.viewContext
        let fetchRequest: NSFetchRequest<EidonEntryEntity> = EidonEntryEntity.fetchRequest()
        fetchRequest.resultType = .countResultType
        do {
            let count = try context.count(for: fetchRequest)
            return count
        } catch {
            logger.error("Error fetching timestamp count: \(error.localizedDescription)")
            return 0
        }
    }
    
    // Helper for creating metadata labels
    private func createMetadataLabel(textColor: NSColor = .labelColor, font: NSFont = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small)), lines: Int = 1, isSelectable: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: "") // Start with empty string
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isEditable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.font = font
        label.textColor = textColor
        label.maximumNumberOfLines = lines
        label.lineBreakMode = (lines > 1) ? .byWordWrapping : .byTruncatingTail
        label.isSelectable = isSelectable
        return label
    }

    private func setupUI() {
        let mainPadding: CGFloat = 20
        let intraPadding: CGFloat = 8 // Spacing between smaller related elements
        let interGroupPadding: CGFloat = 12 // Spacing between distinct groups

        // Slider
        discreteSlider = NSSlider(value: 0, minValue: 0, maxValue: 0, target: self, action: #selector(sliderChanged(_:)))
        discreteSlider.sliderType = .linear
        discreteSlider.numberOfTickMarks = 0 
        discreteSlider.allowsTickMarkValuesOnly = true
        discreteSlider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(discreteSlider)

        // Slider Value Label
        sliderValueLabel = NSTextField(labelWithString: "No data")
        sliderValueLabel.alignment = .center
        sliderValueLabel.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular), weight: .medium)
        sliderValueLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sliderValueLabel)
        
        // --- Metadata Area ---
        overallMetadataStackView = NSStackView()
        overallMetadataStackView.translatesAutoresizingMaskIntoConstraints = false
        overallMetadataStackView.orientation = .horizontal
        overallMetadataStackView.spacing = 10 // Space between icon and text stack
        overallMetadataStackView.alignment = .top 
        view.addSubview(overallMetadataStackView)

        // App Icon Image View
        appIconImageView = NSImageView()
        appIconImageView.translatesAutoresizingMaskIntoConstraints = false
        appIconImageView.imageScaling = .scaleProportionallyDown
        // Constraints for icon size will be added below
        overallMetadataStackView.addArrangedSubview(appIconImageView)
        
        // Vertical stack for text labels (App Name, Title, URL)
        metadataTextStackView = NSStackView()
        metadataTextStackView.translatesAutoresizingMaskIntoConstraints = false
        metadataTextStackView.orientation = .vertical
        metadataTextStackView.alignment = .leading
        metadataTextStackView.spacing = 4 // Small spacing between text lines

        appNameLabel = createMetadataLabel(font: NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .semibold))
        metadataTextStackView.addArrangedSubview(appNameLabel)

        titleLabel = createMetadataLabel(font: NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small)), lines: 2) // Allow title to wrap to 2 lines
        metadataTextStackView.addArrangedSubview(titleLabel)
        
        urlLabel = createMetadataLabel(textColor: .linkColor, font: NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small)), isSelectable: true)
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(urlClicked(_:)))
        urlLabel.addGestureRecognizer(clickGesture)
        metadataTextStackView.addArrangedSubview(urlLabel)
        
        overallMetadataStackView.addArrangedSubview(metadataTextStackView)
        // --- End Metadata Area ---

        // Timestamp Image View
        timestampImageView = NSImageView()
        timestampImageView.imageScaling = .scaleProportionallyUpOrDown
        timestampImageView.translatesAutoresizingMaskIntoConstraints = false
        timestampImageView.wantsLayer = true
        timestampImageView.layer?.borderColor = NSColor.separatorColor.cgColor
        timestampImageView.layer?.borderWidth = 1
        timestampImageView.layer?.cornerRadius = 5
        view.addSubview(timestampImageView)

        // Constraints
        NSLayoutConstraint.activate([
            discreteSlider.topAnchor.constraint(equalTo: view.topAnchor, constant: mainPadding),
            discreteSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: mainPadding),
            discreteSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -mainPadding),

            sliderValueLabel.topAnchor.constraint(equalTo: discreteSlider.bottomAnchor, constant: intraPadding),
            sliderValueLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            // Metadata Area Constraints
            overallMetadataStackView.topAnchor.constraint(equalTo: sliderValueLabel.bottomAnchor, constant: interGroupPadding),
            overallMetadataStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: mainPadding),
            overallMetadataStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -mainPadding),
            // Let metadata height be intrinsic, but not too tall
            overallMetadataStackView.heightAnchor.constraint(lessThanOrEqualToConstant: 80),


            appIconImageView.widthAnchor.constraint(equalToConstant: 32), // Icon size
            appIconImageView.heightAnchor.constraint(equalToConstant: 32),

            // Timestamp Image View takes remaining space
            timestampImageView.topAnchor.constraint(equalTo: overallMetadataStackView.bottomAnchor, constant: interGroupPadding), // Increased spacing
            timestampImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: mainPadding),
            timestampImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -mainPadding),
            timestampImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -mainPadding)
        ])
    }

    private func loadTimestamps() {
        let context = persistenceController.viewContext
        let fetchRequest: NSFetchRequest<EidonEntryEntity> = EidonEntryEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \EidonEntryEntity.timestamp, ascending: true)]

        do {
            let fetchedEntries = try context.fetch(fetchRequest)
            self.timestamps = fetchedEntries.compactMap { $0.timestamp }
            self.lastFetchedTimestampCount = self.timestamps.count
            logger.info("Loaded \(self.timestamps.count) timestamps for timeline.")

            if !self.timestamps.isEmpty {
                discreteSlider.isEnabled = true
                discreteSlider.minValue = 0
                discreteSlider.maxValue = Double(self.timestamps.count - 1)
                discreteSlider.numberOfTickMarks = self.timestamps.count > 1 ? self.timestamps.count : 0
                discreteSlider.doubleValue = Double(self.timestamps.count - 1) 
                
                if let newestEntry = fetchedEntries.last {
                    currentEntry = newestEntry
                    updateDisplayedEntry()
                } else {
                     clearDisplayedEntry()
                }
            } else {
                discreteSlider.isEnabled = false
                discreteSlider.minValue = 0
                discreteSlider.maxValue = 0
                clearDisplayedEntry()
                sliderValueLabel.stringValue = "No data available"
            }
        } catch {
            logger.error("Failed to fetch timestamps: \(error.localizedDescription)")
            discreteSlider.isEnabled = false
            clearDisplayedEntry()
            sliderValueLabel.stringValue = "Error loading data"
        }
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let sliderIntValue = Int(sender.doubleValue.rounded())

        guard sliderIntValue >= 0 && sliderIntValue < timestamps.count else {
            logger.error("Slider value out of bounds: \(sliderIntValue) for \(timestamps.count) timestamps.")
            clearDisplayedEntry()
            return
        }

        let selectedTimestamp = timestamps[sliderIntValue]
        
        let context = persistenceController.viewContext
        let fetchRequest: NSFetchRequest<EidonEntryEntity> = EidonEntryEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "timestamp == %@", selectedTimestamp as NSDate)
        fetchRequest.fetchLimit = 1

        do {
            let entries = try context.fetch(fetchRequest)
            if let entry = entries.first {
                currentEntry = entry
                updateDisplayedEntry()
            } else {
                logger.warning("No entry found for selected timestamp: \(selectedTimestamp)")
                clearDisplayedEntry()
            }
        } catch {
            logger.error("Error fetching entry for timestamp \(selectedTimestamp): \(error.localizedDescription)")
            clearDisplayedEntry()
        }
    }

    private func updateDisplayedEntry() {
        guard let entry = currentEntry, let timestamp = entry.timestamp else {
            clearDisplayedEntry()
            return
        }

        sliderValueLabel.stringValue = AppUtils.timestampToShortFormat(date: timestamp)
        
        // Update metadata labels
        appNameLabel.stringValue = entry.app ?? "Unknown App"
        titleLabel.stringValue = entry.title ?? "No Title"
        
        if let urlString = entry.pageURL, !urlString.isEmpty, let url = URL(string: urlString) {
            self.clickableURL = url
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small)) // Match other metadata labels
            ]
            // Display full URL if possible, or truncated if too long for the label
            // urlLabel.lineBreakMode handles truncation
            let attributedURLString = NSAttributedString(string: urlString, attributes: attributes)
            urlLabel.attributedStringValue = attributedURLString
            urlLabel.toolTip = urlString // Full URL in tooltip
            urlLabel.isHidden = false
        } else {
            urlLabel.stringValue = "" 
            urlLabel.isHidden = true // Hide if no URL, or set to "No URL" and make visible
            self.clickableURL = nil
        }

        // Load App Icon
        if let appName = entry.app, !appName.isEmpty {
            if let appPath = NSWorkspace.shared.fullPath(forApplication: appName) {
                appIconImageView.image = NSWorkspace.shared.icon(forFile: appPath)
            } else if let bundleID = NSWorkspace.shared.bundleIdentifier(forApplication: appName), // Try by name if fullPath fails
                      let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                 appIconImageView.image = NSWorkspace.shared.icon(forFile: appURL.path)
            } else if #available(macOS 11.0, *) {
                appIconImageView.image = NSImage(systemSymbolName: "app.badge", accessibilityDescription: "App Icon")
            } else {
                appIconImageView.image = NSImage(named: NSImage.applicationIconName)
            }
        } else if #available(macOS 11.0, *) {
            appIconImageView.image = NSImage(systemSymbolName: "questionmark.app", accessibilityDescription: "Unknown App")
        } else {
             appIconImageView.image = NSImage(named: NSImage.applicationIconName)
        }
        appIconImageView.image?.size = NSSize(width: 32, height: 32)


        // Load screenshot image
        if let filename = entry.filename, let screenshotsDir = screenshotsPathURL {
            var imageData: Data?

            if entry.isArchived, 
               let archivedFilename = entry.archivedFilename, 
               let archiveBase = archivePathURL { // Check entryTimestamp exists if needed by date logic
                
                let dateFormatter = DateFormatter() // Ensure timestamp is valid for creating path
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let dateString = dateFormatter.string(from: timestamp) // Use the entry's actual timestamp
                let dayArchiveDir = archiveBase.appendingPathComponent(dateString)
                let archivedFilePath = dayArchiveDir.appendingPathComponent(archivedFilename)
                
                if let compressedData = try? Data(contentsOf: archivedFilePath) {
                    imageData = ArchiverService.shared.decompressDataPublic(compressedData)
                }
                 if imageData == nil { logger.error("Failed to load or decompress archived image: \(archivedFilename, privacy: .public)")}
            } else {
                let imageURL = screenshotsDir.appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: imageURL.path) {
                    imageData = try? Data(contentsOf: imageURL)
                } else {
                     logger.error("Screenshot file not found at: \(imageURL.path, privacy: .public)")
                }
            }
            
            if let data = imageData, let image = NSImage(data: data) {
                timestampImageView.image = image
            } else {
                if #available(macOS 11.0, *){
                    timestampImageView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "Image not found")
                } else {
                    timestampImageView.image = NSImage(named: NSImage.quickLookTemplateName) // Placeholder
                }
                logger.warning("Failed to load image data for: \(filename, privacy: .public)")
            }
        } else {
             if #available(macOS 11.0, *){
                timestampImageView.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "No image file")
            } else {
                 timestampImageView.image = NSImage(named: NSImage.quickLookTemplateName) // Placeholder
            }
            logger.warning("No filename for entry with timestamp: \(timestamp.description, privacy: .public)")
        }
    }

    private func clearDisplayedEntry() {
        sliderValueLabel.stringValue = "N/A"
        appNameLabel.stringValue = ""
        titleLabel.stringValue = ""
        urlLabel.attributedStringValue = NSAttributedString(string: "") // Clear attributed string
        urlLabel.isHidden = true
        clickableURL = nil
        timestampImageView.image = nil
        appIconImageView.image = nil
        currentEntry = nil
    }

    @objc private func urlClicked(_ sender: NSClickGestureRecognizer) {
        if let urlToOpen = clickableURL {
            logger.info("Opening URL: \(urlToOpen.absoluteString, privacy: .public)")
            NSWorkspace.shared.open(urlToOpen)
        } else {
            logger.warning("URL label clicked, but no valid URL was stored.")
        }
    }
}