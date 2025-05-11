import Cocoa
import UniformTypeIdentifiers // For UTType

class SearchResultCellView: NSTableCellView {

    // MARK: - UI Elements
    // Exposed as implicitly unwrapped optionals for convenience after setup
    var appIconImageView: NSImageView!
    var titleTextField: NSTextField!
    var metadataTextField: NSTextField! // For app name, timestamp
    var snippetTextField: NSTextField!   // For a snippet of the OCR text

    // MARK: - Initialization
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews() // Also call if initialized from a NIB/XIB in the future
    }

    // MARK: - View Setup
    private func setupViews() {
        // App Icon Image View
        appIconImageView = NSImageView()
        appIconImageView.translatesAutoresizingMaskIntoConstraints = false
        appIconImageView.imageScaling = .scaleProportionallyDown
        addSubview(appIconImageView)

        // Title Text Field
        titleTextField = createLabel(font: .systemFont(ofSize: 13, weight: .semibold), color: .labelColor, alignment: .left)
        titleTextField.lineBreakMode = .byTruncatingTail
        addSubview(titleTextField)

        // Metadata Text Field
        metadataTextField = createLabel(font: .systemFont(ofSize: 11, weight: .regular), color: .secondaryLabelColor, alignment: .left)
        metadataTextField.lineBreakMode = .byTruncatingTail // Allow it to show more if needed.
        metadataTextField.maximumNumberOfLines = 1 // Or 2 if metadata can be long
        addSubview(metadataTextField)
        
        snippetTextField = createLabel(font: .systemFont(ofSize: 11, weight: .light), color: .tertiaryLabelColor, alignment: .left)
        snippetTextField.lineBreakMode = .byTruncatingTail
        snippetTextField.maximumNumberOfLines = 2 // Allow snippet to wrap to two lines if needed
        addSubview(snippetTextField)

        // Constraints
        // Icon on the left, text stack on the right
        NSLayoutConstraint.activate([
            // App Icon
            appIconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            appIconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            appIconImageView.widthAnchor.constraint(equalToConstant: 36), // Slightly larger icon
            appIconImageView.heightAnchor.constraint(equalToConstant: 36),

            // Title
            titleTextField.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            titleTextField.leadingAnchor.constraint(equalTo: appIconImageView.trailingAnchor, constant: 10),
            titleTextField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            // Metadata
            metadataTextField.topAnchor.constraint(equalTo: titleTextField.bottomAnchor, constant: 2),
            metadataTextField.leadingAnchor.constraint(equalTo: titleTextField.leadingAnchor),
            metadataTextField.trailingAnchor.constraint(equalTo: titleTextField.trailingAnchor),
            
            // Snippet
            snippetTextField.topAnchor.constraint(equalTo: metadataTextField.bottomAnchor, constant: 2),
            snippetTextField.leadingAnchor.constraint(equalTo: titleTextField.leadingAnchor),
            snippetTextField.trailingAnchor.constraint(equalTo: titleTextField.trailingAnchor),
            snippetTextField.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6) // Ensure it doesn't overflow
        ])
        
        // To use these properties (imageView, textField) from the NSTableCellView superclass
        // they need to be assigned. We are using custom ones here, so this is more for context.
        // self.imageView = appIconImageView // If we were to use the default imageView property
        // self.textField = titleTextField // If we were to use the default textField property
    }

    // Helper to create configured NSTextFields (as labels)
    private func createLabel(font: NSFont, color: NSColor, alignment: NSTextAlignment) -> NSTextField {
        let textField = NSTextField()
        textField.isEditable = false
        textField.isBordered = false
        textField.backgroundColor = .clear
        textField.font = font
        textField.textColor = color
        textField.alignment = alignment
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }
    
    // MARK: - Configuration
    func configure(with entry: EidonEntryEntity, coreHighlightTerms: [String], filterHighlightValues: [String: String]) {
        // Title
        var titleText = entry.title ?? "Untitled Entry"
        if titleText.isEmpty { titleText = "Untitled Entry" }
        var termsForTitle = coreHighlightTerms
        if let titleFilter = filterHighlightValues["title"] { termsForTitle.append(titleFilter) }
        titleTextField.attributedStringValue = highlight(terms: termsForTitle, in: titleText, defaultAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor])

        // Metadata (App & Timestamp)
        var appNameForMeta = entry.app ?? ""
        var timestampForMeta = ""
        if let ts = entry.timestamp {
            timestampForMeta = AppUtils.timestampToShortFormat(date: ts)
        }
        
        let metaText = "\(appNameForMeta)\(!appNameForMeta.isEmpty && !timestampForMeta.isEmpty ? "  •  " : "")\(timestampForMeta)"
        var termsForMeta = coreHighlightTerms // Core terms can appear in app name
        if let appFilter = filterHighlightValues["app"] { termsForMeta.append(appFilter) }
        // Date/time filters are not directly strings in metadata, so not highlighted here unless AppUtils formats them in a way that matches a query term
        metadataTextField.attributedStringValue = highlight(terms: termsForMeta, in: metaText, defaultAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor])
        
        // Snippet (OCR text and potentially URL if present and queried)
        var snippetContent = ""
        var termsForSnippet = coreHighlightTerms
        
        if let ocrText = entry.text, !ocrText.isEmpty {
            snippetContent += ocrText.replacingOccurrences(of: "\n", with: " ").prefix(100) // Shorter snippet
        }
        if let pageURL = entry.pageURL, !pageURL.isEmpty {
            if !snippetContent.isEmpty { snippetContent += " — " }
            snippetContent += pageURL
            if let urlFilter = filterHighlightValues["url"] { termsForSnippet.append(urlFilter) }
        }
        if snippetContent.isEmpty { snippetContent = "No text content."}
        
        let finalSnippet = String(snippetContent.prefix(150)) + (snippetContent.count > 150 ? "..." : "")
        snippetTextField.attributedStringValue = highlight(terms: termsForSnippet, in: finalSnippet, defaultAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .light), .foregroundColor: NSColor.tertiaryLabelColor])


        // Fetch and set App Icon
        appIconImageView.image = getIcon(for: entry.app, filename: entry.filename)
        
        // Prepare tooltip string using the original non-highlighted titleText for clarity
        var tooltipString = "Title: \(entry.title ?? "Untitled Entry")\nApp: \(entry.app ?? "N/A")"
        if let ts = entry.timestamp { tooltipString += "\nDate: \(AppUtils.timestampToHumanReadable(date: ts))"}
        if let url = entry.pageURL, !url.isEmpty { tooltipString += "\nURL: \(url)"}
        if let text = entry.text, !text.isEmpty { tooltipString += "\nText: \(text.prefix(250))..."}
        self.toolTip = tooltipString
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        // Reset content for cell reuse
        appIconImageView.image = nil
        titleTextField.attributedStringValue = NSAttributedString(string: "")
        metadataTextField.attributedStringValue = NSAttributedString(string: "")
        snippetTextField.attributedStringValue = NSAttributedString(string: "")
        self.toolTip = nil
    }

    // MARK: - Icon Fetching Helper
    private func getIcon(for appName: String?, filename: String?) -> NSImage {
        let workspace = NSWorkspace.shared
        let defaultIconSize = NSSize(width: 32, height: 32)

        // Try to get icon by app name first
        if let appName = appName, !appName.isEmpty {
            // Attempt to find the app in /Applications or /System/Applications
            let appNameWithoutExtension = (appName as NSString).deletingPathExtension
            let searchPaths = ["/Applications/\(appNameWithoutExtension).app",
                               "/System/Applications/\(appNameWithoutExtension).app",
                               "/Applications/\(appName).app", // In case appName already has .app
                               "/System/Applications/\(appName).app"]

            for appPath in searchPaths {
                if FileManager.default.fileExists(atPath: appPath) {
                    let icon = workspace.icon(forFile: appPath)
                    icon.size = defaultIconSize
                    return icon
                }
            }
            // Try with bundle identifier if appName happens to be one (less common for entry.app)
            if let appURL = workspace.urlForApplication(withBundleIdentifier: appName) {
                 let icon = workspace.icon(forFile: appURL.path)
                 icon.size = defaultIconSize
                 return icon
            }
        }
        
        // Try to get icon by file extension from the filename
        if let filename = filename, let fileExtension = URL(fileURLWithPath: filename).pathExtension as String?, !fileExtension.isEmpty {
            if #available(macOS 11.0, *) {
                if let type = UTType(filenameExtension: fileExtension.lowercased()) {
                    let icon = workspace.icon(for: type)
                    icon.size = defaultIconSize
                    return icon
                }
            } else {
                // Fallback for older macOS using `icon(forFileType:)`
                let icon = workspace.icon(forFileType: fileExtension)
                icon.size = defaultIconSize
                return icon
            }
        }
        
        // Default generic icon if others fail
        let genericIcon: NSImage
        if #available(macOS 11.0, *) {
            genericIcon = NSImage(systemSymbolName: "doc", accessibilityDescription: "Generic Document Icon") ?? NSImage(named: NSImage.cautionName)!
        } else {
            genericIcon = workspace.icon(forFileType: "txt") // A very generic document icon
        }
        genericIcon.size = defaultIconSize
        return genericIcon
    }

    // MARK: - Text Highlighting Helper
    private func highlight(terms: [String], in text: String, defaultAttributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: text, attributes: defaultAttributes)
        // Ensure terms are not empty and text has content before attempting to highlight
        guard !terms.allSatisfy({ $0.isEmpty }), !text.isEmpty else { return attributedString }

        // Using a distinct highlight color, e.g., light yellow background.
        // For text color highlighting: .foregroundColor: NSColor.red
        let highlightAttributes: [NSAttributedString.Key: Any] = [.backgroundColor: NSColor.yellow.withAlphaComponent(0.4)]

        for term in terms where !term.isEmpty { // Iterate through each search term
            var searchRange = NSRange(location: 0, length: text.utf16.count)
            while searchRange.location != NSNotFound {
                // Perform case-insensitive search for the current term
                let foundRange = (text as NSString).range(of: term, options: .caseInsensitive, range: searchRange)
                if foundRange.location != NSNotFound {
                    // Apply highlight attributes to the found range
                    attributedString.addAttributes(highlightAttributes, range: foundRange)
                    // Advance the search location past the current find
                    searchRange.location = foundRange.location + foundRange.length
                    searchRange.length = text.utf16.count - searchRange.location
                } else {
                    // Term not found in the remaining string, break from while loop for this term
                    break
                }
            }
        }
        return attributedString
    }
}