import Foundation
import os.log

struct AppUtils {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.Eidon.AppUtils", category: "AppUtils")

    // MARK: - Time Formatting
    static func humanReadableTime(from timestamp: Date) -> String {
        let now = Date()
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric 

        let diffSeconds = Int(now.timeIntervalSince(timestamp))

        if diffSeconds < 0 { return "In the future" }
        if diffSeconds < 5 { return "Just now" }
        
        return formatter.localizedString(for: timestamp, relativeTo: now)
    }
    
    static func humanReadableTime(from unixTimestamp: TimeInterval) -> String {
        return humanReadableTime(from: Date(timeIntervalSince1970: unixTimestamp))
    }

    static func timestampToHumanReadable(date: Date, format: String = "yyyy-MM-dd HH:mm:ss") -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = format
        dateFormatter.locale = Locale(identifier: "en_US_POSIX") // Ensure consistent output
        return dateFormatter.string(from: date)
    }
    
    static func timestampToHumanReadable(unixTimestamp: TimeInterval, format: String = "yyyy-MM-dd HH:mm:ss") -> String {
        return timestampToHumanReadable(date: Date(timeIntervalSince1970: unixTimestamp), format: format)
    }
    
    static func timestampToShortFormat(date: Date) -> String {
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current // Use user's current locale for display

        if calendar.isDateInToday(date) {
            dateFormatter.dateFormat = "'Today,' hh:mm a" // e.g., Today, 09:30 AM
            return dateFormatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            dateFormatter.dateFormat = "'Yesterday,' hh:mm a" // e.g., Yesterday, 03:45 PM
            return dateFormatter.string(from: date)
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) { 
             dateFormatter.dateFormat = "EEEE, hh:mm a" // e.g., "Monday, 09:30 AM"
             return dateFormatter.string(from: date)
        } else { // Default for older dates
            dateFormatter.dateStyle = .medium // e.g., "Sep 12, 2023"
            dateFormatter.timeStyle = .short  // e.g., "9:30 AM"
            return dateFormatter.string(from: date) 
        }
    }
    
    static func timestampToShortFormat(unixTimestamp: TimeInterval) -> String {
        return timestampToShortFormat(date: Date(timeIntervalSince1970: unixTimestamp))
    }

    // MARK: - Smart Title Generation
    static func generateSmartTitle(appName: String?, windowTitle: String?, url: URL?) -> String {
        let appNameLower = appName?.lowercased() ?? ""
        let originalWindowTitle = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let browserAppNames = ["safari", "google chrome", "arc", "microsoft edge", "firefox", "opera", "vivaldi", "brave browser"]
        let isBrowser = browserAppNames.contains { appNameLower.contains($0) }

        if isBrowser, let pageURL = url {
            let urlString = pageURL.absoluteString
            if !originalWindowTitle.isEmpty &&
               originalWindowTitle.lowercased() != urlString.lowercased() &&
               !originalWindowTitle.lowercased().contains(appNameLower) && 
               originalWindowTitle.lowercased() != "new tab" &&
               originalWindowTitle.lowercased() != "start page" {
                
                var cleanedTitle = originalWindowTitle
                if let appName = appName, cleanedTitle.hasSuffix(" - \(appName)") {
                     cleanedTitle = String(cleanedTitle.dropLast(" - \(appName)".count)).trimmingCharacters(in: .whitespaces)
                }
                let browserSuffixes = ["- Google Chrome", "- Mozilla Firefox", "- Safari", "- Microsoft Edge", "- Arc", "- Opera", "- Vivaldi", "- Brave"]
                for suffix in browserSuffixes where cleanedTitle.hasSuffix(suffix) {
                    cleanedTitle = String(cleanedTitle.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
                }
                
                if !cleanedTitle.isEmpty && cleanedTitle.lowercased() != urlString.lowercased() {
                    return cleanedTitle
                }
            }
            
            let pathComponents = pageURL.pathComponents.filter { $0 != "/" }
            if let lastPathComponent = pathComponents.last?.removingPercentEncoding,
               !lastPathComponent.isEmpty,
               lastPathComponent.contains(".") { 
                return URL(fileURLWithPath: lastPathComponent).deletingPathExtension().lastPathComponent
            }
            
            var titleFromURL = pageURL.host?.replacingOccurrences(of: "www.", with: "") ?? ""
            if titleFromURL.isEmpty { titleFromURL = "Web Page" }

            if let firstPathComponent = pathComponents.first?.removingPercentEncoding,
                !firstPathComponent.isEmpty,
                !["index.html", "index.php", "home", "default.aspx"].contains(firstPathComponent.lowercased()),
                titleFromURL.count + firstPathComponent.count < 70 { 
                titleFromURL += "/\(firstPathComponent)"
            }
            return titleFromURL
        }

        let commonFileExtensions = [
            ".py", ".js", ".ts", ".swift", ".java", ".c", ".cpp", ".h", ".html", ".css", ".scss", ".json", ".xml", ".yaml", ".yml",
            ".md", ".txt", ".rtf", ".log", ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx", ".pages", ".numbers", ".key",
            ".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".heic", ".tiff", ".bmp", ".mov", ".mp4", ".avi", ".mkv", ".flv",
            ".zip", ".tar", ".gz", ".dmg", ".pkg", ".ipynb"
        ]
        
        if commonFileExtensions.contains(where: { originalWindowTitle.lowercased().hasSuffix($0) }) {
            if let urlRepresentation = URL(string: originalWindowTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""),
               !urlRepresentation.lastPathComponent.isEmpty, urlRepresentation.lastPathComponent != originalWindowTitle {
                return URL(fileURLWithPath: urlRepresentation.lastPathComponent.removingPercentEncoding ?? urlRepresentation.lastPathComponent).deletingPathExtension().lastPathComponent
            }
            return URL(fileURLWithPath: originalWindowTitle).deletingPathExtension().lastPathComponent
        }

        let titleParts = originalWindowTitle.components(separatedBy: " - ")
        if let firstPart = titleParts.first?.trimmingCharacters(in: .whitespaces), 
           commonFileExtensions.contains(where: { firstPart.lowercased().hasSuffix($0) }) {
            return firstPart
        }

        if appNameLower.contains("finder") && !originalWindowTitle.isEmpty && originalWindowTitle.lowercased() != "finder" {
            return originalWindowTitle 
        }
        if appNameLower.contains("terminal") || appNameLower.contains("iterm") {
            if !originalWindowTitle.isEmpty && originalWindowTitle.rangeOfCharacter(from: .letters) != nil { 
                return originalWindowTitle.count > 70 ? String(originalWindowTitle.prefix(67) + "...") : originalWindowTitle
            }
            return appName ?? "Terminal"
        }

        if !originalWindowTitle.isEmpty && (appNameLower.isEmpty || !originalWindowTitle.lowercased().contains(appNameLower) || originalWindowTitle.lowercased() != appNameLower) {
            return originalWindowTitle
        }
        
        if let appName = appName, !appName.isEmpty {
            return appName
        }
            
        return "Untitled Activity"
    }

    // MARK: - Search Filter Parsing
    
    enum FilterValue: CustomStringConvertible {
        case date(Date)
        case timeRange(start: DateComponents, end: DateComponents)
        case string(String)

        var description: String {
            switch self {
            case .date(let date):
                return AppUtils.timestampToHumanReadable(date: date, format: "yyyy-MM-dd")
            case .timeRange(let start, let end):
                let sh = start.hour ?? 0; let sm = start.minute ?? 0; let ss = start.second ?? 0
                let eh = end.hour ?? 0; let em = end.minute ?? 0; let es = end.second ?? 0
                return String(format: "%02d:%02d:%02d-%02d:%02d:%02d", sh,sm,ss, eh,em,es)
            case .string(let str):
                return "\"\(str)\""
            }
        }
    }

    struct ParsedFilter: CustomStringConvertible {
        let key: String 
        let value: FilterValue
        let originalQuerySubstring: String 

        var description: String {
            return "\(key):\(value.description)"
        }
    }

    static func parseSearchQuery(_ queryString: String) -> (filters: [ParsedFilter], coreQuery: String) {
        var filters: [ParsedFilter] = []
        var workString = queryString
        var coreQueryAccumulator: String = ""
        
        let filterKeys = ["date", "time", "app", "title", "url"]
        // Regex Explanation:
        // (date|time|app|title|url)   : Group 1, Captures the filter key
        // \\s*:\\s*                   : Matches colon with optional surrounding spaces
        // (?:                         : Start of non-capturing group for value alternatives
        //   \"([^\"]*)\"               : Group 2, Double-quoted value
        //  |\'([^\']*)\'               : Group 3, Single-quoted value
        //  |([^\\\"\\'\\s][^:\\s]*(?:\\s+[^\\\"\\'\\s:][^:\\s]*)*?(?=\\s+\\w+:|$)|[^\\\"\\'\\s]+) : Group 4, Unquoted value (complex)
        // )                             : End of non-capturing group for value
        // The unquoted value part is designed to grab words until the next filter key or end of string.
        let fullFilterRegexPattern = "(\(filterKeys.joined(separator: "|")))\\s*:\\s*((?:\"([^\"]*)\"|\'([^\']*)\'|([^\"\'\\s][^:\\s]*(?:\\s+[^\"\'\\s:][^:\\s]*)*?(?=\\s+\\w+:|$)|[^\"\'\\s]+)))"


        var lastFilterEndIndex = workString.startIndex

        while lastFilterEndIndex < workString.endIndex {
            let searchRange = lastFilterEndIndex..<workString.endIndex
            guard let regex = try? NSRegularExpression(pattern: fullFilterRegexPattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: workString, options: [], range: NSRange(searchRange, in: workString)),
                  let matchRangeInWorkString = Range(match.range, in: workString) else {
                if !searchRange.isEmpty { // Append remaining part if no more filters found
                    coreQueryAccumulator += String(workString[searchRange])
                }
                break
            }

            // Add text before this filter match as core query
            if matchRangeInWorkString.lowerBound > lastFilterEndIndex {
                coreQueryAccumulator += String(workString[lastFilterEndIndex..<matchRangeInWorkString.lowerBound])
            }

            let originalFilterSubstring = String(workString[matchRangeInWorkString])
            var key: String?
            var valueString: String? // This will be the content of group 2 (the whole value part)
            var filterParsedSuccessfully = false

            if let keyRange = Range(match.range(at: 1), in: workString) {
                key = String(workString[keyRange]).lowercased()
            }

            // Extract value from appropriate capture group (double-quoted, single-quoted, or unquoted)
            if let doubleQuotedRange = Range(match.range(at: 3), in: workString) {
                valueString = String(workString[doubleQuotedRange])
            } else if let singleQuotedRange = Range(match.range(at: 4), in: workString) {
                valueString = String(workString[singleQuotedRange])
            } else if let unquotedRange = Range(match.range(at: 5), in: workString) {
                valueString = String(workString[unquotedRange])
            }
            
            if let k = key, let v = valueString?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty {
                switch k {
                case "date":
                    if let date = parseDateFilterRobust(v) {
                        filters.append(ParsedFilter(key: k, value: .date(date), originalQuerySubstring: originalFilterSubstring))
                        filterParsedSuccessfully = true
                    }
                case "time":
                    if let timeTuple = parseTimeFilterRobust(v) {
                         filters.append(ParsedFilter(key: k, value: .timeRange(start: timeTuple.start, end: timeTuple.end), originalQuerySubstring: originalFilterSubstring))
                        filterParsedSuccessfully = true
                    }
                case "app", "title":
                    filters.append(ParsedFilter(key: k, value: .string(v), originalQuerySubstring: originalFilterSubstring))
                    filterParsedSuccessfully = true
                case "url":
                    filters.append(ParsedFilter(key: k, value: .string(v.lowercased()), originalQuerySubstring: originalFilterSubstring))
                    filterParsedSuccessfully = true
                default:
                    logger.debug("Unknown filter key encountered during regex match: \\(k, privacy: .public)")
                }
            }

            if !filterParsedSuccessfully {
                coreQueryAccumulator += originalFilterSubstring // Add unparsed/failed filter to core query
                logger.debug("Failed to parse filter, adding to core query: \\(originalFilterSubstring, privacy: .public)")
            }
            
            lastFilterEndIndex = matchRangeInWorkString.upperBound
        }
        
        let finalCoreQuery = coreQueryAccumulator
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        return (filters, finalCoreQuery)
    }


    private static func parseDateFilterRobust(_ dateString: String) -> Date? {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        let lowercasedDateString = dateString.lowercased()
        if lowercasedDateString == "today" { return today }
        if lowercasedDateString == "yesterday" {
            return calendar.date(byAdding: .day, value: -1, to: today)
        }

        let formatters: [(String, DateFormatter)] = [
            ("yyyy-MM-dd", { let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyy-MM-dd"; return df }()),
            ("MM/dd/yyyy", { let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "MM/dd/yyyy"; return df }()),
            ("MM-dd-yyyy", { let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "MM-dd-yyyy"; return df }()),
            ("dd-MM-yyyy", { let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "dd-MM-yyyy"; return df }()),
            ("dd/MM/yyyy", { let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "dd/MM/yyyy"; return df }()),
            ("MMM d, yyyy", { let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "MMM d, yyyy"; return df }()),
            ("MMMM d, yyyy", { let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "MMMM d, yyyy"; return df }()),
            ("MM/dd", { let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "MM/dd"; return df }()), // Default to current year handled below
            ("MM-dd", { let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "MM-dd"; return df }()), // Default to current year handled below
            ("MMM d", { let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "MMM d"; return df }()), 
            ("MMMM d", { let df = DateFormatter(); df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "MMMM d"; return df }())
        ]

        for (formatString, formatter) in formatters {
            if let date = formatter.date(from: dateString) {
                var components = calendar.dateComponents([.year, .month, .day], from: date)
                if formatString == "MM/dd" || formatString == "MM-dd" || formatString == "MMM d" || formatString == "MMMM d" { // If year was not in format string
                    components.year = calendar.component(.year, from: today)
                }
                if let adjustedDate = calendar.date(from: components) {
                    return calendar.startOfDay(for: adjustedDate)
                }
            }
        }
        
        if #available(macOS 10.13, iOS 11.0, *) {
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
            let fullRange = NSRange(dateString.startIndex..., in: dateString)
            if let match = detector?.firstMatch(in: dateString, options: [], range: fullRange),
               match.range.length >= fullRange.length - 2, 
               match.resultType == .date, let detectedDate = match.date {
                logger.debug("Date parsed using NSDataDetector: \\(dateString, privacy: .public) -> \\(detectedDate, privacy: .public)")
                return calendar.startOfDay(for: detectedDate)
            }
        }
        logger.warning("Failed to parse date string robustly: \\(dateString, privacy: .public)")
        return nil
    }

    private static func parseTimeFilterRobust(_ timeString: String) -> (start: DateComponents, end: DateComponents)? {
        let timeParts = timeString.components(separatedBy: "-")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() } 
            .filter { !$0.isEmpty }

        guard !timeParts.isEmpty else {
            logger.debug("Time string for parsing is empty.")
            return nil
        }

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        let formats = ["HH:mm:ss", "h:mm:ss a", "HH:mm", "h:mm a", "HH", "h a", "ha"] // Added "h" for just hour AM/PM

        func parseSingleTimeToComponents(_ str: String) -> DateComponents? {
            for format in formats {
                timeFormatter.dateFormat = format
                if let date = timeFormatter.date(from: str) {
                    return Calendar.current.dateComponents([.hour, .minute, .second], from: date)
                }
            }
            if let hour = Int(str.replacingOccurrences(of: " ", with: "")), (0...23).contains(hour) { // Handles "14" or " 2 "
                return DateComponents(hour: hour, minute: 0, second: 0)
            }
            logger.debug("Failed to parse single time string part: \\(str, privacy: .public)")
            return nil
        }

        guard var startComps = parseSingleTimeToComponents(timeParts[0]) else { return nil }

        if timeParts.count == 2 { 
            guard var endComps = parseSingleTimeToComponents(timeParts[1]) else { return nil }
            
            startComps.second = startComps.second ?? 0
            startComps.minute = startComps.minute ?? 0
            startComps.hour = startComps.hour ?? 0

            endComps.second = endComps.second ?? 59
            endComps.minute = endComps.minute ?? 59
            endComps.hour = endComps.hour ?? 23

            return (startComps, endComps)
        } else { 
            var endComps = startComps
            if startComps.minute == nil && startComps.second == nil { 
                startComps.minute = 0
                startComps.second = 0
                endComps.minute = 59
                endComps.second = 59
            } else if startComps.second == nil { 
                startComps.second = 0
                endComps.second = 59 
            }
            return (startComps, endComps)
        }
    }
}