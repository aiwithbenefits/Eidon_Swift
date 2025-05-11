```swift
import Cocoa
import os.log

class DetailViewController: NSViewController {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.Eidon.Detail", category: "DetailViewController")

    // MARK: - UI Elements
    var screenshotImageView: NSImageView!
    var imageLoadingIndicator: NSProgressIndicator!
    var titleLabel: NSTextField!
    var appLabel: NSTextField!
    var timestampLabel: NSTextField!
    var urlLabel: NSTextField!
    var imageInfoLabel: NSTextField!      // For dimensions/size
    var ocrTextScrollView: NSScrollView!
    var ocrTextView: NSTextView!
    var controlsStackView: NSStackView!   // For buttons

    // Data
    private var entry: EidonEntryEntity?
    private var clickableURL: URL? 

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
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 700))
        self.view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        populateData()
        logger.debug("DetailViewController did load for entry: \(self.entry?.title ?? "Unknown", privacy: .public)")
    }

    private func setupUI() {
        screenshotImageView = NSImageView()
        screenshotImageView.translatesAutoresizingMaskIntoConstraints = false
        screenshotImageView.imageScaling = .scaleProportionallyUpOrDown
        screenshotImageView.wantsLayer = true
        screenshotImageView.layer?.borderColor = NSColor.separatorColor.cgColor
        screenshotImageView.layer?.borderWidth = 1
        screenshotImageView.layer?.cornerRadius = 4
        view.addSubview(screenshotImageView)

        imageLoadingIndicator = NSProgressIndicator()
        imageLoadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        imageLoadingIndicator.style = .spinning
        imageLoadingIndicator.isDisplayedWhenStopped = false
        imageLoadingIndicator.isHidden = true
        view.addSubview(imageLoadingIndicator)

        titleLabel = createLabel(font: .systemFont(ofSize: 16, weight: .bold), lines: 2)
        view.addSubview(titleLabel)
        
        imageInfoLabel = createLabel(font: .systemFont(ofSize: 10), color: .tertiaryLabelColor, alignment: .left) 
        view.addSubview(imageInfoLabel)

        appLabel = createLabel(font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        view.addSubview(appLabel)

        timestampLabel = createLabel(font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
        view.addSubview(timestampLabel)
        
        urlLabel = createLabel(font: .systemFont(ofSize: 12), color: .linkColor)
        urlLabel.lineBreakMode = .byTruncatingTail
        urlLabel.isSelectable = true 
        view.addSubview(urlLabel)
        
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(urlClicked(_:)))
        urlLabel.addGestureRecognizer(clickGesture)

        ocrTextScrollView = NSScrollView()
        ocrTextScrollView.translatesAutoresizingMaskIntoConstraints = false
        ocrTextScrollView.hasVerticalScroller = true
        ocrTextScrollView.borderType = .bezelBorder

        ocrTextView = NSTextView()
        ocrTextView.translatesAutoresizingMaskIntoConstraints = false
        ocrTextView.isEditable = false
        ocrTextView.isSelectable = true
        ocrTextView.font = NSFont.userFixedPitchFont(ofSize: 12)
        ocrTextView.backgroundColor = .textBackgroundColor
        ocrTextView.textColor = .textColor
        
        ocrTextScrollView.documentView = ocrTextView
        view.addSubview(ocrTextScrollView)

        // Buttons Stack View
        let openImageButton = NSButton(title: "Open Image", target: self, action: #selector(openImageClicked(_:)))
        let copyOcrButton = NSButton(title: "Copy Text", target: self, action: #selector(copyOcrTextClicked(_:)))
        openImageButton.bezelStyle = .rounded 
        copyOcrButton.bezelStyle = .rounded

        controlsStackView = NSStackView(views: [openImageButton, copyOcrButton])
        controlsStackView.translatesAutoresizingMaskIntoConstraints = false
        controlsStackView.orientation = .horizontal
        controlsStackView.spacing = 12
        controlsStackView.alignment = .centerY
        controlsStackView.distribution = .fillEqually 
        view.addSubview(controlsStackView)

        let padding: CGFloat = 15
        NSLayoutConstraint.activate([
            screenshotImageView.topAnchor.constraint(equalTo: view.topAnchor, constant: padding),
            screenshotImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            screenshotImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            screenshotImageView.heightAnchor.constraint(equalTo: view.heightAnchor, multiplier: 0.35),

            imageLoadingIndicator.centerXAnchor.constraint(equalTo: screenshotImageView.centerXAnchor),
            imageLoadingIndicator.centerYAnchor.constraint(equalTo: screenshotImageView.centerYAnchor),

            titleLabel.topAnchor.constraint(equalTo: screenshotImageView.bottomAnchor, constant: padding),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            
            imageInfoLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            imageInfoLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            imageInfoLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            appLabel.topAnchor.constraint(equalTo: imageInfoLabel.bottomAnchor, constant: 8),
            appLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            appLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            timestampLabel.topAnchor.constraint(equalTo: appLabel.bottomAnchor, constant: 5),
            timestampLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            timestampLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            
            urlLabel.topAnchor.constraint(equalTo: timestampLabel.bottomAnchor, constant: 5),
            urlLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            urlLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            ocrTextScrollView.topAnchor.constraint(equalTo: urlLabel.bottomAnchor, constant: 10),
            ocrTextScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            ocrTextScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            ocrTextScrollView.bottomAnchor.constraint(equalTo: controlsStackView.topAnchor, constant: -padding),
            
            controlsStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: padding),
            controlsStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -padding),
            controlsStackView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -padding),
            controlsStackView.heightAnchor.constraint(equalToConstant: 28) 
        ])
    }

    private func createLabel(font: NSFont, color: NSColor = .labelColor, alignment: NSTextAlignment = .left, lines: Int = 1) -> NSTextField {
        let textField = NSTextField()
        textField.isEditable = false
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.font = font
        textField.textColor = color
        textField.alignment = alignment
        textField.maximumNumberOfLines = lines
        if lines != 1 {
             textField.lineBreakMode = .byWordWrapping
        } else {
            textField.lineBreakMode = .byTruncatingTail
        }
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }

    public func configure(with entry: EidonEntryEntity) {
        self.entry = entry
        if isViewLoaded {
            populateData()
        }
    }

    private func populateData() {
        guard let entry = self.entry, isViewLoaded else {
            logger.warning("Entry not set or view not loaded. Cannot populate data.")
            titleLabel.stringValue = "No Data"
            appLabel.stringValue = ""
            timestampLabel.stringValue = ""
            urlLabel.attributedStringValue = NSAttributedString(string: "")
            imageInfoLabel.stringValue = ""
            urlLabel.isHidden = true
            clickableURL = nil
            ocrTextView.string = ""
            screenshotImageView.image = nil
            return
        }

        titleLabel.stringValue = entry.title ?? "Untitled Entry"
        appLabel.stringValue = "App: \(entry.app ?? "N/A")"
        
        if let ts = entry.timestamp {
            timestampLabel.stringValue = "Captured: \(AppUtils.timestampToHumanReadable(date: ts, format: "MMM d, yyyy 'at' h:mm:ss a"))"
        } else {
            timestampLabel.stringValue = "Captured: N/A"
        }
        
        if let urlString = entry.pageURL, !urlString.isEmpty, let url = URL(string: urlString) {
            self.clickableURL = url
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .font: NSFont.systemFont(ofSize: 12)
            ]
            let displayURLString = urlString
            let attributedURLString = NSAttributedString(string: "URL: \(displayURLString)", attributes: attributes)
            urlLabel.attributedStringValue = attributedURLString
            urlLabel.toolTip = urlString 
            urlLabel.isHidden = false
        } else {
            urlLabel.attributedStringValue = NSAttributedString(string: "")
            urlLabel.isHidden = true
            self.clickableURL = nil
        }

        ocrTextView.string = entry.text ?? "No OCR text available."
        imageInfoLabel.stringValue = "" 
        loadFullResolutionImage(for: entry)
    }
    
    private func loadFullResolutionImage(for entry: EidonEntryEntity) {
        guard let filename = entry.filename else {
            logger.warning("No filename for entry to load image: \(entry.id?.uuidString ?? "Unknown ID")")
            setPlaceholderImage()
            imageInfoLabel.stringValue = "Image not available"
            return
        }

        imageLoadingIndicator.isHidden = false
        imageLoadingIndicator.startAnimation(nil)
        screenshotImageView.image = nil 

        DispatchQueue.global(qos: .userInitiated).async {
            var imageData: Data?
            let fileManager = FileManager.default

            if entry.isArchived, 
               let archivedFilename = entry.archivedFilename,
               let archiveBase = self.archivePathURL, 
               let entryTimestamp = entry.timestamp {
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let dateString = dateFormatter.string(from: entryTimestamp)
                let dayArchiveDir = archiveBase.appendingPathComponent(dateString)
                let archivedFilePath = dayArchiveDir.appendingPathComponent(archivedFilename)
                
                self.logger.debug("Attempting to load archived image: \(archivedFilePath.path, privacy: .public)")
                if fileManager.fileExists(atPath: archivedFilePath.path) {
                    if let compressedData = try? Data(contentsOf: archivedFilePath) {
                        imageData = ArchiverService.shared.decompressDataPublic(compressedData)
                        if imageData == nil {
                            self.logger.error("Failed to decompress archived image: \(archivedFilename, privacy: .public)")
                        }
                    } else {
                         self.logger.error("Failed to read compressed data for: \(archivedFilename, privacy: .public)")
                    }
                } else {
                    self.logger.error("Archived file not found: \(archivedFilePath.path, privacy: .public)")
                }
            } else if let screenshotsDir = self.screenshotsPathURL {
                let imageURL = screenshotsDir.appendingPathComponent(filename)
                self.logger.debug("Attempting to load screenshot image: \(imageURL.path, privacy: .public)")
                if fileManager.fileExists(atPath: imageURL.path) {
                    imageData = try? Data(contentsOf: imageURL)
                } else {
                     self.logger.error("Screenshot file not found at: \(imageURL.path, privacy: .public)")
                }
            }

            DispatchQueue.main.async {
                self.imageLoadingIndicator.stopAnimation(nil)
                if let data = imageData, let image = NSImage(data: data) {
                    self.screenshotImageView.image = image
                    let fileSize = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
                    self.imageInfoLabel.stringValue = "\(Int(image.size.width))x\(Int(image.size.height))  —  \(fileSize)"
                } else {
                    self.logger.warning("Failed to load image data for entry: \(entry.id?.uuidString ?? "Unknown ID")")
                    self.setPlaceholderImage()
                    self.imageInfoLabel.stringValue = "Image not available"
                }
            }
        }
    }
    
    private func setPlaceholderImage() {
        if #available(macOS 11.0, *) {
            screenshotImageView.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "Image not available")
        } else {
            screenshotImageView.image = NSImage(named: NSImage.cautionName)
        }
    }

    // MARK: - Actions
    @objc private func urlClicked(_ sender: NSClickGestureRecognizer) {
        if let urlToOpen = clickableURL {
            logger.info("Opening URL: \(urlToOpen.absoluteString, privacy: .public)")
            NSWorkspace.shared.open(urlToOpen)
        } else {
            logger.warning("URL label clicked, but no valid URL was stored.")
        }
    }

    @objc private func openImageClicked(_ sender: NSButton) {
        guard let entry = self.entry, let filename = entry.filename else {
            logger.warning("Open Image: No entry or filename.")
            return
        }

        var fileURLToOpen: URL?

        if entry.isArchived,
           let archivedFilename = entry.archivedFilename,
           let archiveBase = self.archivePathURL,
           let entryTimestamp = entry.timestamp {
            
            logger.info("Open Image: Entry is archived. Attempting to decompress for opening.")
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let dateString = dateFormatter.string(from: entryTimestamp)
            let dayArchiveDir = archiveBase.appendingPathComponent(dateString)
            let archivedFilePath = dayArchiveDir.appendingPathComponent(archivedFilename)

            if let compressedData = try? Data(contentsOf: archivedFilePath),
               let decompressedData = ArchiverService.shared.decompressDataPublic(compressedData) {
                let tempDir = FileManager.default.temporaryDirectory
                let uniqueTempFilename = "\(UUID().uuidString)_\(filename)" 
                let tempFileURL = tempDir.appendingPathComponent(uniqueTempFilename)
                do {
                    try decompressedData.write(to: tempFileURL)
                    fileURLToOpen = tempFileURL
                    logger.info("Open Image: Decompressed to temporary file: \(tempFileURL.path)")
                } catch {
                    logger.error("Open Image: Failed to write decompressed data to temporary file: \(error)")
                }
            } else {
                logger.error("Open Image: Failed to read or decompress archived file at \(archivedFilePath.path).")
            }
        } else if let screenshotsDir = self.screenshotsPathURL {
            fileURLToOpen = screenshotsDir.appendingPathComponent(filename)
             if !FileManager.default.fileExists(atPath: fileURLToOpen!.path) {
                logger.error("Open Image: Screenshot file not found at \(fileURLToOpen!.path)")
                fileURLToOpen = nil 
            }
        }

        if let url = fileURLToOpen {
            logger.info("Open Image: Opening image at \(url.path, privacy: .public)")
            NSWorkspace.shared.open(url)
        } else {
            logger.error("Open Image: Could not determine file URL to open for \(filename).")
        }
    }

    @objc private func copyOcrTextClicked(_ sender: NSButton) {
        guard let text = ocrTextView.string, !text.isEmpty else {
            logger.info("Copy OCR Text: No text to copy.")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        logger.info("Copy OCR Text: OCR text copied to pasteboard.")
    }
}
```