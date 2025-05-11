import Foundation
import NaturalLanguage
import Accelerate // For potential use in cosine similarity

class NLPService {

    // MARK: - Errors
    enum NLPError: Error, LocalizedError {
        case embeddingNotAvailable(String)
        case embeddingFailed(String)
        case tokenizationFailed(String)
        case dimensionMismatch
        case invalidVectorInput

        var errorDescription: String? {
            switch self {
            case .embeddingNotAvailable(let lang):
                return "NLP Error: Sentence embedding model is not available for language '\(lang)'."
            case .embeddingFailed(let message):
                return "NLP Error: Failed to generate embedding. \(message)"
            case .tokenizationFailed(let message):
                return "NLP Error: Tokenization failed. \(message)"
            case .dimensionMismatch:
                return "NLP Error: Vectors have different dimensions for cosine similarity."
            case .invalidVectorInput:
                return "NLP Error: One or both vectors are invalid (e.g., zero magnitude) for cosine similarity."
            }
        }
    }

    // MARK: - Properties
    static let shared = NLPService() // Singleton for convenience

    private var activeEmbedder: NLEmbedding?
    private var embeddingDimension: Int = 0
    private let defaultLanguage: NLLanguage = .english

    // LRU Caches (simple dictionary-based for this example)
    private var embeddingCache = [String: [Float32]]()
    private let embeddingCacheLimit = 1024
    private var embeddingCacheUsageOrder = [String]()

    private var tokenCache = [String: Set<String>]()
    private let tokenCacheLimit = 2048
    private var tokenCacheUsageOrder = [String]()


    private init() {
        // Attempt to load the embedder during initialization
        if let embedder = NLEmbedding.sentenceEmbedding(for: defaultLanguage) {
            self.activeEmbedder = embedder
            self.embeddingDimension = embedder.dimension
            #if DEBUG
            print("NLPService: Successfully loaded \(defaultLanguage.rawValue) sentence embedder. Dimension: \(self.embeddingDimension)")
            #endif
        } else {
            #if DEBUG
            print("NLPService: Warning - \(defaultLanguage.rawValue) sentence embedder not available at init. Will attempt to load on first use.")
            #endif
        }
    }

    // MARK: - Text Embedding

    public func getSentenceEmbedding(for text: String) -> Result<[Float32], NLPError> {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            // Return a zero vector of the expected dimension if text is empty,
            // but ensure embeddingDimension is initialized if embedder hasn't loaded yet.
            if self.embeddingDimension == 0 && self.activeEmbedder == nil {
                 if let embedder = NLEmbedding.sentenceEmbedding(for: defaultLanguage) {
                    self.activeEmbedder = embedder
                    self.embeddingDimension = embedder.dimension
                } else {
                    // If embedder truly unavailable, we can't know the dimension. Return empty or error.
                    // For now, let's return an empty array, or an error if preferred.
                    #if DEBUG
                    print("NLPService: Embedder unavailable, returning empty vector for empty text.")
                    #endif
                    return .success([]) 
                }
            }
            return .success(Array(repeating: 0.0, count: self.embeddingDimension))
        }
        
        if let cachedEmbedding = embeddingCache[trimmedText] {
            updateUsageOrder(for: trimmedText, in: &embeddingCacheUsageOrder)
            return .success(cachedEmbedding)
        }

        guard let embedder = self.activeEmbedder ?? NLEmbedding.sentenceEmbedding(for: defaultLanguage) else {
            return .failure(.embeddingNotAvailable(defaultLanguage.rawValue))
        }
        if self.activeEmbedder == nil { // Update if it was just loaded
             self.activeEmbedder = embedder
             self.embeddingDimension = embedder.dimension
        }
        
        let sentences = trimmedText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        
        if sentences.isEmpty {
            return .success(Array(repeating: 0.0, count: self.embeddingDimension))
        }

        var sentenceVectors: [[Float32]] = []
        for sentence in sentences {
            if let vectorNSNumbers = embedder.vector(for: sentence) { // vector is [NSNumber]?
                 sentenceVectors.append(vectorNSNumbers.map { Float32($0.doubleValue) })
            } else {
                #if DEBUG
                print("NLPService: Nil vector for sentence: \"\(sentence.prefix(50))...\"")
                #endif
            }
        }

        guard !sentenceVectors.isEmpty, let firstVector = sentenceVectors.first, firstVector.count == self.embeddingDimension else {
            #if DEBUG
            if sentenceVectors.isEmpty {
                print("NLPService: No valid sentence vectors generated for text: \"\(trimmedText.prefix(50))...\"")
            } else if let fv = sentenceVectors.first, fv.count != self.embeddingDimension {
                print("NLPService: Dimension mismatch in generated sentence vectors. Expected \(self.embeddingDimension), got \(fv.count)")
            }
            #endif
            return .success(Array(repeating: 0.0, count: self.embeddingDimension))
        }

        let vectorSum = sentenceVectors.reduce(Array(repeating: Float32(0), count: self.embeddingDimension)) { result, vector in
            // Ensure inner vectors also match expected dimension before adding
            guard vector.count == self.embeddingDimension else {
                #if DEBUG
                print("NLPService: Inner vector dimension mismatch during sum. Expected \(self.embeddingDimension), got \(vector.count). Skipping.")
                #endif
                return result
            }
            var mutableResult = result // Create a mutable copy to pass to vDSP
            vDSP_vadd(vector, 1, result, 1, &mutableResult, vDSP_Length(self.embeddingDimension))
            return mutableResult
        }
        
        var meanVector = Array(repeating: Float32(0), count: self.embeddingDimension)
        var countFloat = Float32(sentenceVectors.count)
        vDSP_vsdiv(vectorSum, 1, &countFloat, &meanVector, 1, vDSP_Length(self.embeddingDimension))
        
        updateCache(with: meanVector, forKey: trimmedText, cache: &embeddingCache, usageOrder: &embeddingCacheUsageOrder, limit: embeddingCacheLimit)
        
        return .success(meanVector)
    }
    
    public func getEmbeddingDimension() -> Int {
        if self.activeEmbedder == nil, embeddingDimension == 0 {
            if let embedder = NLEmbedding.sentenceEmbedding(for: defaultLanguage) {
                self.activeEmbedder = embedder
                self.embeddingDimension = embedder.dimension
            } else {
                #if DEBUG
                print("NLPService: getEmbeddingDimension - Embedder could not be loaded. Returning 0.")
                #endif
            }
        }
        return self.embeddingDimension
    }

    // MARK: - Text Tokenization
    public func tokenize(text: String) -> Result<Set<String>, NLPError> {
        let normalizedText = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            return .success([])
        }

        if let cachedTokens = tokenCache[normalizedText] {
            updateUsageOrder(for: normalizedText, in: &tokenCacheUsageOrder)
            return .success(cachedTokens)
        }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = normalizedText
        
        var tokens = Set<String>()
        tokenizer.enumerateTokens(in: normalizedText.startIndex..<normalizedText.endIndex) { tokenRange, _ in
            tokens.insert(String(normalizedText[tokenRange]))
            return true
        }
        
        updateCache(with: tokens, forKey: normalizedText, cache: &tokenCache, usageOrder: &tokenCacheUsageOrder, limit: tokenCacheLimit)

        return .success(tokens)
    }

    // MARK: - Cosine Similarity
    public func cosineSimilarity(between vectorA: [Float32], and vectorB: [Float32]) -> Result<Float32, NLPError> {
        guard !vectorA.isEmpty, !vectorB.isEmpty else {
            return .success(0.0) // Or .failure(.invalidVectorInput)
        }
        guard vectorA.count == vectorB.count else {
            return .failure(.dimensionMismatch)
        }

        var dotProduct: Float32 = 0
        vDSP_dotpr(vectorA, 1, vectorB, 1, &dotProduct, vDSP_Length(vectorA.count))

        var magnitudeA: Float32 = 0
        var sumOfSquaresA: Float32 = 0
        vDSP_measqv(vectorA, 1, &sumOfSquaresA, vDSP_Length(vectorA.count))
        magnitudeA = sqrt(sumOfSquaresA)

        var magnitudeB: Float32 = 0
        var sumOfSquaresB: Float32 = 0
        vDSP_measqv(vectorB, 1, &sumOfSquaresB, vDSP_Length(vectorB.count))
        magnitudeB = sqrt(sumOfSquaresB)

        guard magnitudeA > 0 && magnitudeB > 0 else {
            if magnitudeA == 0 && magnitudeB == 0 { return .success(1.0) }
            return .success(0.0)
        }
        
        let similarity = dotProduct / (magnitudeA * magnitudeB)
        
        return .success(max(-1.0, min(1.0, similarity)))
    }
    
    // MARK: - Cache Helpers
    private func updateUsageOrder<T>(for key: String, in usageOrder: inout [T]) where T == String {
        if let index = usageOrder.firstIndex(of: key) {
            usageOrder.remove(at: index)
        }
        usageOrder.append(key)
    }

    private func updateCache<K, V>(with value: V, forKey key: K, cache: inout [K: V], usageOrder: inout [K], limit: Int) where K == String {
         if cache.count >= limit, let keyToRemove = usageOrder.first {
            cache.removeValue(forKey: keyToRemove)
            usageOrder.removeFirst()
        }
        cache[key] = value
        updateUsageOrder(for: key, in: &usageOrder)
    }
}