import Foundation
import CoreData
import Compression // For Apple's native compression algorithms

class ArchiverService {

    static let shared = ArchiverService()
    private let persistenceController = PersistenceController.shared
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.example.Eidon.Archiver", category: "ArchiverService")

    // Configuration (mirroring parts of Python config.py)
    // COLD_DAYS: Files older than this (in days from now) are candidates for archiving.
    // This will now be read from AppSettings.shared.archiveColdDays
    private let compressionAlgorithm: compression_algorithm = .lzfse // Apple's recommended general-purpose algorithm

    private var isArchiving: Bool = false
    private var archiveTimer: Timer?


    private var screenshotsPathURL: URL? {
        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            logger.error("Could not find Application Support directory.")
            return nil
        }
        let eidonDir = appSupportDir.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.example.Eidon")
        return eidonDir.appendingPathComponent("screenshots")
    }

    private var archiveBaseURL: URL? {
        guard let appSupportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            logger.error("Could not find Application Support directory for archive.")
            return nil
        }
        let eidonDir = appSupportDir.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.example.Eidon")
        let archiveDir = eidonDir.appendingPathComponent("archive")

        if !fileManager.fileExists(atPath: archiveDir.path) {
            do {
                try fileManager.createDirectory(at: archiveDir, withIntermediateDirectories: true, attributes: nil)
                logger.info("Archive base directory created at: \(archiveDir.path)")
            } catch {
                logger.error("Failed to create archive base directory \(archiveDir.path): \(error.localizedDescription)")
                return nil
            }
        }
        return archiveDir
    }

    private init() {}

    // MARK: - Public Archiver Control
    public func startPeriodicArchiving(interval: TimeInterval = 24 * 60 * 60) { // Default parameter, but settings will override
        let currentArchiveIntervalHours = AppSettings.shared.archiveIntervalHours
        let effectiveInterval = TimeInterval(currentArchiveIntervalHours * 60 * 60)

        guard archiveTimer == nil else {
            logger.info("Periodic archiving is already scheduled.")
            return
        }
        logger.info("Scheduling periodic archiving with interval: \(effectiveInterval) seconds (from settings: \(currentArchiveIntervalHours) hours).")
        // Run once on start, then schedule
        DispatchQueue.global(qos: .background).async {
            self.runArchiver()
        }
        
        archiveTimer = Timer.scheduledTimer(withTimeInterval: effectiveInterval, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .background).async {
                self?.runArchiver()
            }
        }
        // Keep the run loop alive if this timer is on a dedicated thread.
        // If using global dispatch queue, this might not be strictly necessary for Timer.
    }

    public func stopPeriodicArchiving() {
        archiveTimer?.invalidate()
        archiveTimer = nil
        logger.info("Periodic archiving stopped.")
    }

    public func runArchiver() {
        guard !isArchiving else {
            logger.info("Archiver is already running.")
            return
        }
        isArchiving = true
        let currentColdDaysThreshold = AppSettings.shared.archiveColdDays
        logger.info("Starting archiver run. Archiving files older than \(currentColdDaysThreshold) days (from settings).")

        guard let screenshotsDir = screenshotsPathURL, let archiveDirBase = archiveBaseURL else {
            logger.error("Screenshots path or archive path is not available. Aborting archive run.")
            isArchiving = false
            return
        }

        let context = persistenceController.newBackgroundContext()
        context.performAndWait { // Perform synchronously on the background context's queue
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -currentColdDaysThreshold, to: Date()) ?? Date()
            
            let fetchRequest: NSFetchRequest<EidonEntryEntity> = EidonEntryEntity.fetchRequest()
            // Fetch entries that are older than the cutoffDate and not yet marked as archived (assuming an 'isArchived' attribute)
            // If no 'isArchived' attribute, you might need other ways to track, or re-archive (less efficient).
            // For now, let's assume we add an 'isArchived' Bool attribute to EidonEntryEntity, defaulting to false.
            // And an 'archivedFilename' String? attribute.
            fetchRequest.predicate = NSPredicate(format: "timestamp < %@ AND (isArchived == NO OR isArchived == nil)", cutoffDate as NSDate)
            // Optional: fetchLimit to process in batches
            // fetchRequest.fetchLimit = 100 

            var archivedCount = 0
            var errorCount = 0

            do {
                let entriesToArchive = try context.fetch(fetchRequest)
                logger.info("Found \(entriesToArchive.count) entries eligible for archiving.")

                for entry in entriesToArchive {
                    guard let originalFilename = entry.filename, !originalFilename.isEmpty else {
                        logger.warning("Entry with timestamp \(entry.timestamp?.description ?? "N/A") has no filename, skipping.")
                        continue
                    }

                    let originalFilePath = screenshotsDir.appendingPathComponent(originalFilename)
                    guard fileManager.fileExists(atPath: originalFilePath.path) else {
                        logger.warning("Original file \(originalFilename) not found at \(originalFilePath.path). Marking as archived if DB entry exists, or skipping.")
                        // Optionally mark as archived in DB if the file is gone but entry exists
                        // entry.isArchived = true 
                        // entry.archivedFilename = "MISSING_ORIGINAL"
                        continue
                    }

                    // Determine archive subdirectory (YYYY-MM-DD)
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateFormat = "yyyy-MM-dd"
                    let dateString = dateFormatter.string(from: entry.timestamp ?? Date())
                    let dayArchiveDir = archiveDirBase.appendingPathComponent(dateString)

                    if !fileManager.fileExists(atPath: dayArchiveDir.path) {
                        do {
                            try fileManager.createDirectory(at: dayArchiveDir, withIntermediateDirectories: true, attributes: nil)
                        } catch {
                            logger.error("Failed to create day archive directory \(dayArchiveDir.path): \(error.localizedDescription)")
                            errorCount += 1
                            continue
                        }
                    }
                    
                    let compressedFilename = originalFilename + ".compressed" // Using generic extension
                    let archivedFilePath = dayArchiveDir.appendingPathComponent(compressedFilename)

                    if fileManager.fileExists(atPath: archivedFilePath.path) {
                        logger.info("Archived file \(compressedFilename) already exists in \(dayArchiveDir.path). Removing original if present.")
                        do {
                            if fileManager.fileExists(atPath: originalFilePath.path) {
                                try fileManager.removeItem(at: originalFilePath)
                                logger.debug("Removed original file \(originalFilename) as archive already exists.")
                            }
                            entry.setValue(true, forKey: "isArchived") // Ensure 'isArchived' attribute exists in your Core Data model
                            entry.setValue(archivedFilePath.lastPathComponent, forKey: "archivedFilename") // Ensure 'archivedFilename' attribute exists
                        } catch {
                             logger.error("Error removing original or updating DB for already archived file \(originalFilename): \(error.localizedDescription)")
                             errorCount += 1
                        }
                        continue
                    }
                    
                    // Compress and move
                    do {
                        let sourceData = try Data(contentsOf: originalFilePath)
                        if let compressedData = compressData(sourceData) {
                            try compressedData.write(to: archivedFilePath)
                            try fileManager.removeItem(at: originalFilePath)
                            
                            entry.setValue(true, forKey: "isArchived")
                            entry.setValue(archivedFilePath.lastPathComponent, forKey: "archivedFilename") 
                            logger.info("Successfully archived \(originalFilename) to \(archivedFilePath.path)")
                            archivedCount += 1
                        } else {
                            logger.error("Compression failed for \(originalFilename).")
                            errorCount += 1
                        }
                    } catch {
                        logger.error("Error during archiving process for \(originalFilename): \(error.localizedDescription)")
                        errorCount += 1
                        // If archive file was partially created, clean it up
                        if fileManager.fileExists(atPath: archivedFilePath.path) {
                            try? fileManager.removeItem(at: archivedFilePath)
                        }
                    }
                } // End for entry in entriesToArchive

                if context.hasChanges {
                    try context.save()
                }
                logger.info("Archiver run finished. Archived: \(archivedCount) files. Errors: \(errorCount).")

            } catch {
                logger.error("Failed to fetch entries for archiving: \(error.localizedDescription)")
            }
        } // End context.performAndWait
        isArchiving = false
    }

    // MARK: - Compression / Decompression
    private func compressData(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        
        // Prepare source and destination buffers
        let sourceBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        data.copyBytes(to: sourceBuffer, count: data.count)
        defer { sourceBuffer.deallocate() }

        // Destination buffer: compression might make it larger in worst cases, but typically smaller.
        // Allocate same size as source for simplicity, Apple's compression usually fits.
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        defer { destinationBuffer.deallocate() }

        let compressedSize = compression_encode_buffer(destinationBuffer, data.count,
                                                       sourceBuffer, data.count,
                                                       nil, // No scratch buffer needed for basic encode
                                                       compressionAlgorithm)
        
        if compressedSize == 0 { // Compression failed or resulted in empty output
            logger.error("Compression failed (returned 0 bytes).")
            return nil
        }
        
        return Data(bytes: destinationBuffer, count: compressedSize)
    }

    public func getArchivedImageData(entry: EidonEntryEntity) -> Data? {
        guard entry.value(forKey: "isArchived") as? Bool == true,
              let archivedFilename = entry.value(forKey: "archivedFilename") as? String,
              !archivedFilename.isEmpty,
              let entryTimestamp = entry.timestamp,
              let archiveDirBase = archiveBaseURL else {
            logger.warning("Entry is not archived, has no archived filename, or paths are invalid.")
            return nil
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: entryTimestamp)
        let dayArchiveDir = archiveDirBase.appendingPathComponent(dateString)
        let archivedFilePath = dayArchiveDir.appendingPathComponent(archivedFilename)

        guard fileManager.fileExists(atPath: archivedFilePath.path) else {
            logger.error("Archived file not found at: \(archivedFilePath.path)")
            return nil
        }

        do {
            let compressedData = try Data(contentsOf: archivedFilePath)
            guard !compressedData.isEmpty else {
                logger.error("Archived file is empty: \(archivedFilePath.path)")
                return nil
            }

            // Decompression: Destination buffer size needs to be estimated or dynamically allocated.
            // A common practice is to store the original size or use a sufficiently large buffer.
            // For simplicity, assuming decompressed size won't exceed a certain multiple (e.g., 10x).
            // This is NOT robust for all cases. A better way is to store original size.
            let estimatedDecompressedSize = compressedData.count * 10 // Heuristic
            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: estimatedDecompressedSize)
            defer { destinationBuffer.deallocate() }
            
            let sourceBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: compressedData.count)
            compressedData.copyBytes(to: sourceBuffer, count: compressedData.count)
            defer { sourceBuffer.deallocate() }

            let decompressedSize = compression_decode_buffer(destinationBuffer, estimatedDecompressedSize,
                                                             sourceBuffer, compressedData.count,
                                                             nil, // No scratch buffer
                                                             compressionAlgorithm)
            
            if decompressedSize == 0 || decompressedSize > estimatedDecompressedSize { // Decompression failed or buffer too small
                logger.error("Decompression failed or buffer too small for \(archivedFilename). Decompressed size: \(decompressedSize)")
                return nil
            }
            logger.info("Successfully decompressed \(archivedFilename). Original size: \(decompressedSize) bytes.")
            return Data(bytes: destinationBuffer, count: decompressedSize)

        } catch {
            logger.error("Error reading or decompressing archived file \\(archivedFilePath.path): \\(error.localizedDescription)")
            return nil
        }
    }

    /// Public wrapper to decompress data.
    /// - Parameter compressedData: The data to decompress.
    /// - Returns: The decompressed data, or nil if decompression fails or input is empty.
    public func decompressDataPublic(_ compressedData: Data) -> Data? {
        guard !compressedData.isEmpty else {
            logger.warning("decompressDataPublic called with empty data.")
            return nil
        }
        
        // Estimate decompressed size (this is a common challenge without stored original size)
        // For many common data types, a multiple of 5-10x is a starting point, but can be insufficient or excessive.
        // Production systems often store original size metadata alongside compressed data.
        let estimatedDecompressedSize = compressedData.count * 10 // Heuristic, adjust as needed or store original size
        
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: estimatedDecompressedSize)
        defer { destinationBuffer.deallocate() }
        
        let sourceBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: compressedData.count)
        compressedData.copyBytes(to: sourceBuffer, count: compressedData.count)
        defer { sourceBuffer.deallocate() }

        let decompressedSize = compression_decode_buffer(destinationBuffer, estimatedDecompressedSize,
                                                         sourceBuffer, compressedData.count,
                                                         nil, // No scratch buffer
                                                         compressionAlgorithm)
        
        guard decompressedSize > 0 && decompressedSize <= estimatedDecompressedSize else {
            logger.error("Decompression failed or buffer too small. Decompressed size: \\(decompressedSize), Estimated: \\(estimatedDecompressedSize)")
            return nil
        }
        
        return Data(bytes: destinationBuffer, count: decompressedSize)
    }
}

// Important: You'll need to add `isArchived` (Bool) and `archivedFilename` (String, Optional)
// attributes to your `EidonEntryEntity` in the Core Data model (`.xcdatamodeld` file).
```