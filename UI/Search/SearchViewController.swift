```swift
import Cocoa
import CoreData
import os.log

class SearchViewController: NSViewController {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.Eidon.Search", category: "SearchViewController")
    private let persistenceController = PersistenceController.shared

    // UI Elements
    private var searchField: NSSearchField!
    private var resultsTableView: NSTableView!
    private var resultsScrollView: NSScrollView!
    private var statusLabel: NSTextField!
    private var emptyStateContainerView: NSView! // Container for icon and label
    private var emptyStateImageView: NSImageView!
    private var emptyStateLabel: NSTextField!

    // Data
    private var searchResults: [EidonEntryEntity] = []
    
    // To keep detail windows alive
    private var openDetailWindows = Set<NSWindowController>()

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        self.view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        logger.info("SearchViewController did load.")
        self.view.window?.makeFirstResponder(searchField)
        updateEmptyState(for: .initial) // Set initial empty state
    }

    private enum EmptyStateType {
        case initial
        case noResults(query: String)
        case error(message: String)
    }

    private func updateEmptyState(for type: EmptyStateType) {
        resultsScrollView.isHidden = true
        emptyStateContainerView.isHidden = false
        statusLabel.stringValue = "" // Generally clear status when showing full empty state

        switch type {
        case .initial:
            if #available(macOS 11.0, *) {
                emptyStateImageView.image = NSImage(systemSymbolName: "magnifyingglass.circle", accessibilityDescription: "Search Icon")
            } else {
                emptyStateImageView.image = NSImage(named: NSImage.touchBarSearchTemplateName) // Fallback
            }
            emptyStateLabel.stringValue = "Enter a query above to find screenshots."
        case .noResults(let query):
            if #available(macOS 11.0, *) {
                emptyStateImageView.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: "No Results Icon")
            } else {
                emptyStateImageView.image = NSImage(named: NSImage.touchBarBookmarksTemplateName) // Fallback
            }
            emptyStateLabel.stringValue = "No results found for \"\(query)\".\nTip: Try filters like 'app:', 'date:', or 'title:'."
        case .error(let message):
             if #available(macOS 11.0, *) {
                emptyStateImageView.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Error Icon")
            } else {
                emptyStateImageView.image = NSImage(named: NSImage.statusUnavailableName) // Fallback
            }
            emptyStateLabel.stringValue = message
            statusLabel.stringValue = "Search Error" // Can also use statusLabel for brief error indication
        }
        if #available(macOS 10.14, *) { // contentTintColor available
            emptyStateImageView.contentTintColor = NSColor.secondaryLabelColor
        }
    }

    private func setupUI() {
        searchField = NSSearchField()
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        searchField.placeholderString = "Search (e.g., text, app:Safari, date:today, title:\"My Project\")"
        searchField.target = self
        searchField.action = #selector(searchFieldAction(_:))
        view.addSubview(searchField)

        resultsScrollView = NSScrollView()
        resultsScrollView.translatesAutoresizingMaskIntoConstraints = false
        resultsScrollView.hasVerticalScroller = true
        resultsScrollView.borderType = .noBorder
        view.addSubview(resultsScrollView) 

        resultsTableView = NSTableView()
        resultsTableView.headerView = nil
        resultsTableView.usesAlternatingRowBackgroundColors = true
        resultsTableView.allowsMultipleSelection = false
        resultsTableView.delegate = self
        resultsTableView.dataSource = self
        resultsTableView.doubleAction = #selector(tableViewDoubleClicked)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ResultColumn"))
        column.resizingMask = .autoresizingMask
        resultsTableView.addTableColumn(column)
        
        resultsScrollView.documentView = resultsTableView
        
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.alignment = .center
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        view.addSubview(statusLabel)

        // Empty State Container
        emptyStateContainerView = NSView()
        emptyStateContainerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyStateContainerView)

        emptyStateImageView = NSImageView()
        emptyStateImageView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateImageView.imageScaling = .scaleProportionallyUpOrDown
        emptyStateContainerView.addSubview(emptyStateImageView)

        emptyStateLabel = NSTextField(labelWithString: "")
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.alignment = .center
        emptyStateLabel.textColor = .secondaryLabelColor
        emptyStateLabel.font = NSFont.systemFont(ofSize: 13)
        emptyStateLabel.isBezeled = false
        emptyStateLabel.isEditable = false
        emptyStateLabel.maximumNumberOfLines = 3 
        emptyStateContainerView.addSubview(emptyStateLabel)
        
        resultsScrollView.isHidden = true 
        emptyStateContainerView.isHidden = false


        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),

            resultsScrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            resultsScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resultsScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resultsScrollView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -8),
            
            emptyStateContainerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateContainerView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -searchField.intrinsicContentSize.height / 2), 
            emptyStateContainerView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            emptyStateContainerView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),

            emptyStateImageView.topAnchor.constraint(equalTo: emptyStateContainerView.topAnchor),
            emptyStateImageView.centerXAnchor.constraint(equalTo: emptyStateContainerView.centerXAnchor),
            emptyStateImageView.widthAnchor.constraint(equalToConstant: 48),
            emptyStateImageView.heightAnchor.constraint(equalToConstant: 48),

            emptyStateLabel.topAnchor.constraint(equalTo: emptyStateImageView.bottomAnchor, constant: 10),
            emptyStateLabel.leadingAnchor.constraint(equalTo: emptyStateContainerView.leadingAnchor),
            emptyStateLabel.trailingAnchor.constraint(equalTo: emptyStateContainerView.trailingAnchor),
            emptyStateLabel.bottomAnchor.constraint(equalTo: emptyStateContainerView.bottomAnchor),

            statusLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            statusLabel.heightAnchor.constraint(equalToConstant: 16),
        ])
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        self.view.window?.makeFirstResponder(searchField)
    }

    @objc private func searchFieldAction(_ sender: NSSearchField) {
        performSearch(query: sender.stringValue)
    }
    
    @objc private func tableViewDoubleClicked() {
        let selectedRow = resultsTableView.selectedRow
        guard selectedRow != -1 && selectedRow < searchResults.count else { return }
        
        let selectedEntry = searchResults[selectedRow]
        logger.info("Requesting detail view for entry: \(selectedEntry.title ?? "No Title", privacy: .public)")

        let detailWC = DetailWindowController(entry: selectedEntry)
        detailWC.showWindowAndFocus()
        openDetailWindows.insert(detailWC)
    }

    private func performSearch(query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            searchResults = []
            resultsTableView.reloadData()
            updateEmptyState(for: .initial)
            return
        }
        
        emptyStateContainerView.isHidden = true 
        resultsScrollView.isHidden = true 
        statusLabel.stringValue = "Searching..."
        
        do {
            let (filters, coreQuery) = try AppUtils.parseSearchQuery(trimmedQuery) 
            logger.debug("Parsed Filters: \(filters.map { $0.description }.joined(separator: ", "), privacy: .public), Core Query: '\(coreQuery, privacy: .public)'")
            
            DispatchQueue.global(qos: .userInitiated).async {
                let fetchResult = self.fetchEntries(filters: filters, coreQuery: coreQuery)
                
                DispatchQueue.main.async {
                    switch fetchResult {
                    case .success(let fetchedEntries):
                        self.searchResults = fetchedEntries
                        self.resultsTableView.reloadData()
                        
                        if self.searchResults.isEmpty {
                            self.updateEmptyState(for: .noResults(query: trimmedQuery))
                        } else {
                            self.resultsScrollView.isHidden = false
                            self.emptyStateContainerView.isHidden = true 
                            self.statusLabel.stringValue = "\(self.searchResults.count) result(s) found."
                        }
                    case .failure(let error):
                        self.searchResults = []
                        self.resultsTableView.reloadData()
                        self.updateEmptyState(for: .error(message: "Search Error: \(error.localizedDescription)"))
                        self.logger.error("Search fetch failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        } catch { 
            searchResults = []
            resultsTableView.reloadData()
            let parsingErrorMessage = "Invalid search syntax: \(error.localizedDescription)" // Assumes error.localizedDescription is suitable
            updateEmptyState(for: .error(message: parsingErrorMessage))
            logger.error("Search query parsing failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fetchEntries(filters: [AppUtils.ParsedFilter], coreQuery: String) -> Result<[EidonEntryEntity], Error> {
        let context = persistenceController.viewContext
        let fetchRequest: NSFetchRequest<EidonEntryEntity> = EidonEntryEntity.fetchRequest()
        var subpredicates: [NSPredicate] = []

        for filter in filters {
            switch filter.key {
            case "date":
                if case .date(let dateValue) = filter.value {
                    let calendar = Calendar.current
                    let startOfDay = calendar.startOfDay(for: dateValue)
                    if let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) {
                        subpredicates.append(NSPredicate(format: "timestamp >= %@ AND timestamp < %@", startOfDay as NSDate, endOfDay as NSDate))
                    }
                }
            case "time":
                if case .timeRange(let startTimeComps, let endTimeComps) = filter.value {
                    let timestampExpression = NSExpression(forKeyPath: "timestamp")
                    
                    let hourExpression = NSExpression(forFunction: "hour:", arguments: [timestampExpression])
                    let minuteExpression = NSExpression(forFunction: "minute:", arguments: [timestampExpression])
                    let secondExpression = NSExpression(forFunction: "second:", arguments: [timestampExpression])

                    let tsHoursToSeconds = NSExpression(forFunction: "multiply:by:", arguments: [hourExpression, NSExpression(forConstantValue: 3600)])
                    let tsMinutesToSeconds = NSExpression(forFunction: "multiply:by:", arguments: [minuteExpression, NSExpression(forConstantValue: 60)])
                    let tsTotalSecondsPart1 = NSExpression(forFunction: "add:to:", arguments: [tsHoursToSeconds, tsMinutesToSeconds])
                    let timestampTotalSecondsExpr = NSExpression(forFunction: "add:to:", arguments: [tsTotalSecondsPart1, secondExpression])
                    
                    let sH = startTimeComps.hour ?? 0
                    let sM = startTimeComps.minute ?? 0
                    let sS = startTimeComps.second ?? 0
                    let startFilterTotalSeconds = sH * 3600 + sM * 60 + sS
                    
                    let eH = endTimeComps.hour ?? 23
                    let eM = endTimeComps.minute ?? 59
                    let eS = endTimeComps.second ?? 59
                    let endFilterTotalSeconds = eH * 3600 + eM * 60 + eS

                    let startComparisonPredicate = NSComparisonPredicate(
                        leftExpression: timestampTotalSecondsExpr,
                        rightExpression: NSExpression(forConstantValue: startFilterTotalSeconds),
                        modifier: .direct,
                        type: .greaterThanOrEqualTo,
                        options: []
                    )
                    let endComparisonPredicate = NSComparisonPredicate(
                        leftExpression: timestampTotalSecondsExpr,
                        rightExpression: NSExpression(forConstantValue: endFilterTotalSeconds),
                        modifier: .direct,
                        type: .lessThanOrEqualTo,
                        options: []
                    )
                    subpredicates.append(NSCompoundPredicate(andPredicateWithSubpredicates: [startComparisonPredicate, endComparisonPredicate]))
                }
            case "app", "title":
                if case .string(let stringValue) = filter.value {
                    subpredicates.append(NSPredicate(format: "%K CONTAINS[cd] %@", filter.key, stringValue))
                }
            case "url":
                if case .string(let stringValue) = filter.value {
                     subpredicates.append(NSPredicate(format: "pageURL CONTAINS[cd] %@", stringValue))
                }
            default:
                logger.warning("Unknown or already processed filter key: \(filter.key, privacy: .public)")
            }
        }
        
        if !coreQuery.isEmpty {
            var perKeywordPredicates: [NSPredicate] = []
            let queryKeywords = coreQuery.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            
            for keyword in queryKeywords {
                let textPredicate = NSPredicate(format: "text CONTAINS[cd] %@", keyword)
                let titlePredicate = NSPredicate(format: "title CONTAINS[cd] %@", keyword)
                let appPredicate = NSPredicate(format: "app CONTAINS[cd] %@", keyword)
                perKeywordPredicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: [textPredicate, titlePredicate, appPredicate]))
            }
            if !perKeywordPredicates.isEmpty {
                 subpredicates.append(NSCompoundPredicate(orPredicateWithSubpredicates: perKeywordPredicates))
            }
        }
        
        if !subpredicates.isEmpty {
            fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)
        }
        
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \EidonEntryEntity.timestamp, ascending: false)]
        
        do {
            let results = try context.fetch(fetchRequest)
            logger.info("Fetched \(results.count) entries for query.")
            return .success(results)
        } catch {
            return .failure(error)
        }
    }
}

// MARK: - NSSearchFieldDelegate
extension SearchViewController: NSSearchFieldDelegate {
    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        logger.debug("Search field ended searching (e.g., clear button pressed).")
        searchResults = []
        resultsTableView.reloadData()
        updateEmptyState(for: .initial) 
    }
}

// MARK: - NSTableViewDataSource
extension SearchViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return searchResults.count
    }
}

// MARK: - NSTableViewDelegate
extension SearchViewController: NSTableViewDelegate {
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 70 
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < searchResults.count else { return nil }
        let entry = searchResults[row]

        let identifier = NSUserInterfaceItemIdentifier("SearchResultCell")
        var cellView = tableView.makeView(withIdentifier: identifier, owner: nil) as? SearchResultCellView

        if cellView == nil {
            cellView = SearchResultCellView(frame: .zero)
            cellView?.identifier = identifier 
        }
        
        let (parsedFilters, coreQueryForHighlight) = AppUtils.parseSearchQuery(searchField.stringValue)
        let coreHighlightTerms = coreQueryForHighlight.components(separatedBy: .whitespaces).filter { !$0.isEmpty && $0.count > 1 }
        
        var filterHighlightValues: [String: String] = [:]
        for filter in parsedFilters {
            switch filter.value {
            case .string(let strVal):
                if strVal.count > 1 { 
                    filterHighlightValues[filter.key] = strVal
                }
            default: 
                break
            }
        }
        
        cellView?.configure(with: entry, coreHighlightTerms: coreHighlightTerms, filterHighlightValues: filterHighlightValues)
        return cellView
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard resultsTableView.selectedRow >= 0 && resultsTableView.selectedRow < searchResults.count else {
            return
        }
        let selectedEntry = searchResults[selectedRow]
        logger.info("Selected entry: \(selectedEntry.title ?? "No Title", privacy: .public)")
    }
}
```