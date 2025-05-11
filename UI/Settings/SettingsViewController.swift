```swift
import Cocoa
import os.log

class SettingsViewController: NSViewController {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.Eidon.Settings", category: "SettingsViewController")
    private let appSettings = AppSettings.shared

    // MARK: - UI Elements
    // Capture Settings
    private var captureIntervalLabel: NSTextField!
    private var captureIntervalField: NSTextField!
    private var captureIntervalStepper: NSStepper!
    private var captureIntervalUnitLabel: NSTextField!

    private var idleTimeLabel: NSTextField!
    private var idleTimeField: NSTextField!
    private var idleTimeStepper: NSStepper!
    private var idleTimeUnitLabel: NSTextField!

    // Screenshot Format
    private var imageFormatLabel: NSTextField!
    private var imageFormatSegmentedControl: NSSegmentedControl!
    private var jpegQualityLabel: NSTextField!
    private var jpegQualitySlider: NSSlider!
    private var jpegQualityValueLabel: NSTextField!

    // Archive Settings
    private var archiveColdDaysLabel: NSTextField!
    private var archiveColdDaysField: NSTextField!
    private var archiveColdDaysStepper: NSStepper!
    private var archiveColdDaysUnitLabel: NSTextField!
    
    private var archiveIntervalLabel: NSTextField!
    private var archiveIntervalField: NSTextField!
    private var archiveIntervalStepper: NSStepper!
    private var archiveIntervalUnitLabel: NSTextField!
    
    // Launch at Login
    private var launchAtLoginCheckbox: NSButton!

    // MARK: - Lifecycle
    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 420))
        self.view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadSettings()
        updateJPEGQualityVisibility()
        logger.debug("SettingsViewController did load.")
        
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChangedExternally(_:)), name: AppSettings.didChangeNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func settingsChangedExternally(_ notification: Notification) {
        if notification.object as? SettingsViewController == self {
            return
        }
        DispatchQueue.main.async {
             self.loadSettings()
             self.updateJPEGQualityVisibility()
        }
    }

    // MARK: - UI Setup Helper
    private func createLabel(text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        // label.alignment = .right // NSGridView handles cell alignment
        return label
    }
    
    private func createUnitLabel(text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        // label.alignment = .left // NSGridView handles cell alignment
        label.textColor = .secondaryLabelColor
        return label
    }

    private func setupUI() {
        let mainStackView = NSStackView()
        mainStackView.orientation = .vertical
        mainStackView.alignment = .centerX // Center sections horizontally
        mainStackView.spacing = 20 // Spacing between section groups + separators
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        
        // --- Capture Settings Group ---
        let captureGroup = NSStackView.createSectionStack(title: "Capture Settings")
        let captureGrid = NSGridView()
        captureGrid.translatesAutoresizingMaskIntoConstraints = false
        captureGrid.columnSpacing = 8
        captureGrid.rowSpacing = 10
        
        captureIntervalLabel = createLabel(text: "Capture every:")
        captureIntervalField = NSTextField()
        captureIntervalField.formatter = NumberFormatter.wholeNumberFormatter(min: 1, max: 3600)
        captureIntervalField.alignment = .right
        captureIntervalField.target = self; captureIntervalField.action = #selector(captureIntervalFieldChanged(_:))
        captureIntervalStepper = NSStepper(value: 5, minValue: 1, maxValue: 3600, increment: 1, target: self, action: #selector(captureIntervalStepperChanged(_:)))
        captureIntervalUnitLabel = createUnitLabel(text: "seconds")
        captureGrid.addRow(with: [captureIntervalLabel, captureIntervalField, captureIntervalStepper, captureIntervalUnitLabel])

        idleTimeLabel = createLabel(text: "Pause if idle for:")
        idleTimeField = NSTextField()
        idleTimeField.formatter = NumberFormatter.wholeNumberFormatter(min: 5, max: 7200)
        idleTimeField.alignment = .right
        idleTimeField.target = self; idleTimeField.action = #selector(idleTimeFieldChanged(_:))
        idleTimeStepper = NSStepper(value: 60, minValue: 5, maxValue: 7200, increment: 5, target: self, action: #selector(idleTimeStepperChanged(_:)))
        idleTimeUnitLabel = createUnitLabel(text: "seconds")
        captureGrid.addRow(with: [idleTimeLabel, idleTimeField, idleTimeStepper, idleTimeUnitLabel])
        
        captureGrid.column(at: 0).xPlacement = .trailing // Labels
        captureGrid.column(at: 1).width = 60            // TextFields
        captureGrid.column(at: 2).xPlacement = .leading  // Steppers
        captureGrid.column(at: 3).xPlacement = .leading  // Unit Labels

        captureGroup.addArrangedSubview(captureGrid)
        mainStackView.addArrangedSubview(captureGroup)
        mainStackView.addArrangedSubview(NSBox.separator(fullWidth: true))


        // --- Screenshot Format Group ---
        let formatGroup = NSStackView.createSectionStack(title: "Screenshot Settings")
        let formatGrid = NSGridView(numberOfColumns: 2) // Simple 2-column for this section
        formatGrid.translatesAutoresizingMaskIntoConstraints = false
        formatGrid.columnSpacing = 8
        formatGrid.rowSpacing = 10
        
        imageFormatLabel = createLabel(text: "Save thumbnails as:")
        imageFormatSegmentedControl = NSSegmentedControl(labels: ["PNG (Lossless)", "JPEG (Compressed)"], trackingMode: .selectOne, target: self, action: #selector(imageFormatChanged(_:)))
        imageFormatSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        formatGrid.addRow(with: [imageFormatLabel, imageFormatSegmentedControl])
        
        jpegQualityLabel = createLabel(text: "JPEG Quality:")
        let jpegQualityHStack = NSStackView.createHStack(spacing: 5) // Use Hstack for slider + value label
        jpegQualitySlider = NSSlider(value: 0.8, minValue: 0.1, maxValue: 1.0, target: self, action: #selector(jpegQualitySliderChanged(_:)))
        jpegQualitySlider.numberOfTickMarks = 10
        jpegQualitySlider.translatesAutoresizingMaskIntoConstraints = false
        jpegQualityValueLabel = createUnitLabel(text: "80%")
        jpegQualityValueLabel.alignment = .right // Align percentage to right
        jpegQualityHStack.addArrangedSubviews([jpegQualitySlider, jpegQualityValueLabel])
        formatGrid.addRow(with: [jpegQualityLabel, jpegQualityHStack])

        formatGrid.column(at: 0).xPlacement = .trailing // Labels
        formatGrid.column(at: 1).xPlacement = .leading  // Controls / Control Containers
        // Allow controls in column 1 to fill if they can
        if let cell1 = formatGrid.cell(for: imageFormatSegmentedControl) { cell1.xPlacement = .fill }
        if let cell2 = formatGrid.cell(for: jpegQualityHStack) { cell2.xPlacement = .fill }
        
        formatGroup.addArrangedSubview(formatGrid)
        mainStackView.addArrangedSubview(formatGroup)
        mainStackView.addArrangedSubview(NSBox.separator(fullWidth: true))

        // --- Archive Settings Group ---
        let archiveGroup = NSStackView.createSectionStack(title: "Archive Settings")
        let archiveGrid = NSGridView()
        archiveGrid.translatesAutoresizingMaskIntoConstraints = false
        archiveGrid.columnSpacing = 8
        archiveGrid.rowSpacing = 10

        archiveColdDaysLabel = createLabel(text: "Archive entries older than:")
        archiveColdDaysField = NSTextField()
        archiveColdDaysField.formatter = NumberFormatter.wholeNumberFormatter(min: 1, max: 3650)
        archiveColdDaysField.alignment = .right
        archiveColdDaysField.target = self; archiveColdDaysField.action = #selector(archiveColdDaysFieldChanged(_:))
        archiveColdDaysStepper = NSStepper(value: 30, minValue: 1, maxValue: 3650, increment: 1, target: self, action: #selector(archiveColdDaysStepperChanged(_:)))
        archiveColdDaysUnitLabel = createUnitLabel(text: "days")
        archiveGrid.addRow(with: [archiveColdDaysLabel, archiveColdDaysField, archiveColdDaysStepper, archiveColdDaysUnitLabel])

        archiveIntervalLabel = createLabel(text: "Run archiver every:")
        archiveIntervalField = NSTextField()
        archiveIntervalField.formatter = NumberFormatter.wholeNumberFormatter(min: 1, max: 168)
        archiveIntervalField.alignment = .right
        archiveIntervalField.target = self; archiveIntervalField.action = #selector(archiveIntervalFieldChanged(_:))
        archiveIntervalStepper = NSStepper(value: 6, minValue: 1, maxValue: 168, increment: 1, target: self, action: #selector(archiveIntervalStepperChanged(_:)))
        archiveIntervalUnitLabel = createUnitLabel(text: "hours")
        archiveGrid.addRow(with: [archiveIntervalLabel, archiveIntervalField, archiveIntervalStepper, archiveIntervalUnitLabel])

        archiveGrid.column(at: 0).xPlacement = .trailing // Labels
        archiveGrid.column(at: 1).width = 60             // TextFields
        archiveGrid.column(at: 2).xPlacement = .leading   // Steppers
        archiveGrid.column(at: 3).xPlacement = .leading   // Unit Labels

        archiveGroup.addArrangedSubview(archiveGrid)
        mainStackView.addArrangedSubview(archiveGroup)
        mainStackView.addArrangedSubview(NSBox.separator(fullWidth: true))
        
        // --- General Settings ---
        let generalGroup = NSStackView.createSectionStack(title: "General")
        launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch Eidon at login", target: self, action: #selector(launchAtLoginChanged(_:)))
        launchAtLoginCheckbox.translatesAutoresizingMaskIntoConstraints = false
        // To make checkbox align with grid content, embed it in a way that it can be leading aligned within the section
        let checkboxRow = NSGridView(views: [[launchAtLoginCheckbox]]) // Grid with one cell
        checkboxRow.column(at: 0).xPlacement = .leading
        generalGroup.addArrangedSubview(checkboxRow)
        
        mainStackView.addArrangedSubview(generalGroup)

        view.addSubview(mainStackView)
        NSLayoutConstraint.activate([
            mainStackView.topAnchor.constraint(equalTo: view.topAnchor),
            mainStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainStackView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),

            // Width constraints for specific controls not fully managed by GridView auto-sizing
            captureIntervalField.widthAnchor.constraint(equalToConstant: 60),
            idleTimeField.widthAnchor.constraint(equalTo: captureIntervalField.widthAnchor),
            archiveColdDaysField.widthAnchor.constraint(equalTo: captureIntervalField.widthAnchor),
            archiveIntervalField.widthAnchor.constraint(equalTo: captureIntervalField.widthAnchor),
            
            imageFormatSegmentedControl.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),
            jpegQualitySlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            jpegQualityValueLabel.widthAnchor.constraint(equalToConstant: 45), // For "100%"
            
            // Ensure section stack views take full width available in mainStackView
            captureGroup.widthAnchor.constraint(equalTo: mainStackView.widthAnchor, constant: -mainStackView.edgeInsets.left - mainStackView.edgeInsets.right),
            formatGroup.widthAnchor.constraint(equalTo: captureGroup.widthAnchor),
            archiveGroup.widthAnchor.constraint(equalTo: captureGroup.widthAnchor),
            generalGroup.widthAnchor.constraint(equalTo: captureGroup.widthAnchor),
        ])
        
        // Align steppers height to their text fields
        [captureIntervalStepper, idleTimeStepper, archiveColdDaysStepper, archiveIntervalStepper].forEach { stepper in
            if let field = (stepper == captureIntervalStepper ? captureIntervalField :
                           (stepper == idleTimeStepper ? idleTimeField :
                           (stepper == archiveColdDaysStepper ? archiveColdDaysField : archiveIntervalField))) {
                stepper?.heightAnchor.constraint(equalTo: field!.heightAnchor).isActive = true
            }
        }
    }

    // MARK: - Load & Save Settings
    private func loadSettings() {
        captureIntervalField.doubleValue = appSettings.captureInterval
        captureIntervalStepper.doubleValue = appSettings.captureInterval

        idleTimeField.doubleValue = appSettings.idleTimeThreshold
        idleTimeStepper.doubleValue = appSettings.idleTimeThreshold
        
        imageFormatSegmentedControl.selectedSegment = appSettings.screenshotFormatIsPNG ? 0 : 1
        jpegQualitySlider.floatValue = appSettings.jpegCompressionFactor
        jpegQualityValueLabel.stringValue = "\(Int(appSettings.jpegCompressionFactor * 100))%"

        archiveColdDaysField.integerValue = appSettings.archiveColdDays
        archiveColdDaysStepper.integerValue = appSettings.archiveColdDays
        
        archiveIntervalField.integerValue = appSettings.archiveIntervalHours
        archiveIntervalStepper.integerValue = appSettings.archiveIntervalHours
        
        launchAtLoginCheckbox.state = appSettings.launchAtLogin ? .on : .off
        
        logger.debug("Settings loaded into UI.")
    }
    
    private func updateJPEGQualityVisibility() {
        let isJPEGSelected = imageFormatSegmentedControl.selectedSegment == 1
        jpegQualityLabel.isHidden = !isJPEGSelected
        jpegQualitySlider.isHidden = !isJPEGSelected
        jpegQualityValueLabel.isHidden = !isJPEGSelected
    }

    // MARK: - UI Actions
    @objc private func captureIntervalFieldChanged(_ sender: NSTextField) {
        appSettings.captureInterval = sender.doubleValue
        captureIntervalStepper.doubleValue = sender.doubleValue
    }
    @objc private func captureIntervalStepperChanged(_ sender: NSStepper) {
        appSettings.captureInterval = sender.doubleValue
        captureIntervalField.doubleValue = sender.doubleValue
    }

    @objc private func idleTimeFieldChanged(_ sender: NSTextField) {
        appSettings.idleTimeThreshold = sender.doubleValue
        idleTimeStepper.doubleValue = sender.doubleValue
    }
    @objc private func idleTimeStepperChanged(_ sender: NSStepper) {
        appSettings.idleTimeThreshold = sender.doubleValue
        idleTimeField.doubleValue = sender.doubleValue
    }
    
    @objc private func imageFormatChanged(_ sender: NSSegmentedControl) {
        appSettings.screenshotFormatIsPNG = sender.selectedSegment == 0
        updateJPEGQualityVisibility()
    }
    
    @objc private func jpegQualitySliderChanged(_ sender: NSSlider) {
        appSettings.jpegCompressionFactor = sender.floatValue
        jpegQualityValueLabel.stringValue = "\(Int(sender.floatValue * 100))%"
    }

    @objc private func archiveColdDaysFieldChanged(_ sender: NSTextField) {
        appSettings.archiveColdDays = sender.integerValue
        archiveColdDaysStepper.integerValue = sender.integerValue
    }
    @objc private func archiveColdDaysStepperChanged(_ sender: NSStepper) {
        appSettings.archiveColdDays = sender.integerValue
        archiveColdDaysField.integerValue = sender.integerValue
    }
    
    @objc private func archiveIntervalFieldChanged(_ sender: NSTextField) {
        appSettings.archiveIntervalHours = sender.integerValue
        archiveIntervalStepper.integerValue = sender.integerValue
    }
    @objc private func archiveIntervalStepperChanged(_ sender: NSStepper) {
        appSettings.archiveIntervalHours = sender.integerValue
        archiveIntervalField.integerValue = sender.integerValue
    }
    
    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        appSettings.launchAtLogin = (sender.state == .on)
        logger.info("Launch at login preference changed to: \(appSettings.launchAtLogin)")
    }
}

// MARK: - NumberFormatter Extension
fileprivate extension NumberFormatter {
    static func wholeNumberFormatter(min: Int, max: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none 
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: min)
        formatter.maximum = NSNumber(value: max)
        return formatter
    }
}

// MARK: - NSStepper Convenience
fileprivate extension NSStepper {
    convenience init(value: Double, minValue: Double, maxValue: Double, increment: Double, target: AnyObject?, action: Selector?) {
        self.init()
        self.translatesAutoresizingMaskIntoConstraints = false
        self.doubleValue = value
        self.minValue = minValue
        self.maxValue = maxValue
        self.increment = increment
        self.valueWraps = false
        self.target = target
        self.action = action
    }
}

// MARK: - NSStackView Convenience for Settings UI
fileprivate extension NSStackView {
    static func createHStack(spacing: CGFloat = 8, alignment: NSLayoutConstraint.Attribute = .centerY) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = spacing
        stack.alignment = alignment
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
    
    static func createSectionStack(title: String) -> NSStackView {
        let sectionStack = NSStackView()
        sectionStack.orientation = .vertical
        sectionStack.spacing = 10 // Spacing within the section (between title and grid/controls)
        sectionStack.alignment = .leading // Align content (like grid) to leading edge
        sectionStack.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold) // Slightly bolder for section titles
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        sectionStack.addArrangedSubview(titleLabel)
        
        return sectionStack
    }
    
    func addArrangedSubviews(_ views: [NSView]) {
        views.forEach { self.addArrangedSubview($0) }
    }
}

// MARK: - NSBox Convenience for Separator
fileprivate extension NSBox {
    static func separator(fullWidth: Bool = false) -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        if fullWidth {
            // If used inside a stackview that manages width, this might not be strictly needed,
            // but can be helpful in other contexts or if the stackview's alignment isn't .fill
        }
        return box
    }
}

```