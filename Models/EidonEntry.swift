import Foundation
import CoreGraphics // For CGFloat, or just use Double for embedding

// Swift struct representing an Eidon entry.
struct EidonEntry: Identifiable, Codable { // Added Codable for potential persistence
    let id: UUID
    var app: String?
    var title: String?
    var text: String?
    var timestamp: Date // Store as Date in Swift
    var embedding: Data? // Store as raw Data, equivalent to np.ndarray.tobytes()
    var filename: String?
    var pageURL: URL? // Store as URL for type safety

    enum CodingKeys: String, CodingKey {
        case id
        case app
        case title
        case text
        case timestamp
        case embedding
        case filename
        case pageURL = "page_url" // Matches Python's page_url
    }

    // Initializer for creating new entries
    init(id: UUID = UUID(),
         app: String? = nil,
         title: String? = nil,
         text: String? = nil,
         timestamp: Date = Date(), // Default to now
         embedding: Data? = nil,
         filename: String? = nil,
         pageURL: URL? = nil) {
        self.id = id
        self.app = app
        self.title = title
        self.text = text
        self.timestamp = timestamp
        self.embedding = embedding
        self.filename = filename
        self.pageURL = pageURL
    }

    // Initializer from Unix timestamp (Double or Int)
    init(id: UUID = UUID(),
         app: String? = nil,
         title: String? = nil,
         text: String? = nil,
         unixTimestamp: TimeInterval, // TimeInterval is Double
         embedding: Data? = nil,
         filename: String? = nil,
         pageURLString: String? = nil) {
        self.init(id: id,
                  app: app,
                  title: title,
                  text: text,
                  timestamp: Date(timeIntervalSince1970: unixTimestamp),
                  embedding: embedding,
                  filename: filename,
                  pageURL: pageURLString != nil ? URL(string: pageURLString!) : nil)
    }
    
    // Helper to get embedding as [Float32]
    // Assumes embedding Data stores an array of Float32
    func getEmbeddingVector() -> [Float32]? {
        guard let data = embedding else { return nil }
        // Ensure the data count is a multiple of Float32 size
        guard data.count % MemoryLayout<Float32>.stride == 0 else {
            #if DEBUG
            print("Error: EidonEntry.getEmbeddingVector - Embedding data size (\(data.count)) is not a multiple of Float32 stride (\(MemoryLayout<Float32>.stride)).")
            #endif
            return nil
        }
        let floatCount = data.count / MemoryLayout<Float32>.stride
        var vector = [Float32](repeating: 0, count: floatCount)
        _ = data.copyBytes(to: UnsafeMutableBufferPointer(start: &vector, count: floatCount))
        return vector
    }

    // Helper to set embedding from [Float32]
    mutating func setEmbeddingVector(_ vector: [Float32]?) {
        guard let vector = vector, !vector.isEmpty else {
            self.embedding = nil
            return
        }
        // Create Data from the [Float32] array.
        // This correctly handles the memory layout of the Float32 array.
        self.embedding = vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
