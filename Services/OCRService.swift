import Foundation
import Vision
import CoreGraphics // For CGImage
#if canImport(AppKit)
import AppKit // For NSImage
#endif

class OCRService {

    // MARK: - Errors
    enum OCRError: Error, LocalizedError {
        case imageConversionError(String)
        case visionRequestFailed(Error?)
        case noTextDetected

        var errorDescription: String? {
            switch self {
            case .imageConversionError(let message):
                return "OCR Image Conversion Error: \(message)"
            case .visionRequestFailed(let underlyingError):
                if let error = underlyingError {
                    return "OCR Vision Request Failed: \(error.localizedDescription)"
                }
                return "OCR Vision Request Failed: Unknown error."
            case .noTextDetected:
                return "OCR Error: No text detected in the image."
            }
        }
    }

    // MARK: - Public OCR Function
    
    #if os(macOS)
    /// Performs OCR on an image to extract text using Apple's Vision framework.
    /// - Parameter image: An `NSImage` or `CGImage` to perform OCR on.
    /// - Parameter recognitionLanguages: Array of language codes (e.g., ["en-US", "fr-FR"]). Defaults to ["en-US"].
    /// - Parameter recognitionLevel: The level of recognition accuracy (`.accurate` or `.fast`). Defaults to `.accurate`.
    /// - Parameter customWords: An array of custom words to supplement the recognizer's vocabulary.
    /// - Returns: A `Result` containing the extracted text as a single string (lines separated by newlines) or an `OCRError`.
    public func extractText(
        from image: Any,
        recognitionLanguages: [String] = ["en-US"],
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
        customWords: [String]? = nil
    ) -> Result<String, OCRError> {

        guard let cgImage = convertToCGImage(image) else {
            #if DEBUG
            print("OCRService: Failed to convert input of type \(type(of: image)) to CGImage.")
            #endif
            return .failure(.imageConversionError("Failed to convert input to CGImage."))
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = recognitionLanguages
        request.recognitionLevel = recognitionLevel
        if let customWords = customWords, !customWords.isEmpty {
            request.customWords = customWords
        }
        // request.usesLanguageCorrection = true // Default is true. Set to false for performance if needed.

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            #if DEBUG
            print("OCRService: Vision handler.perform failed: \(error.localizedDescription)")
            #endif
            return .failure(.visionRequestFailed(error))
        }

        guard let observations = request.results, !observations.isEmpty else {
            #if DEBUG
            print("OCRService: No observations returned from Vision request.")
            #endif
            return .failure(.noTextDetected)
        }

        let extractedLines = observations.compactMap { observation in
            observation.topCandidates(1).first?.string
        }

        if extractedLines.isEmpty {
            #if DEBUG
            print("OCRService: Observations were present, but no text strings extracted from top candidates.")
            #endif
            return .failure(.noTextDetected) // Or a more specific error if needed
        }
        
        return .success(extractedLines.joined(separator: "\n"))
    }

    // MARK: - Image Conversion Helper
    
    private func convertToCGImage(_ image: Any) -> CGImage? {
        if let cgImage = image as? CGImage {
            return cgImage
        }
        #if canImport(AppKit) // Ensure AppKit is available (macOS)
        if let nsImage = image as? NSImage {
            var imageRect = CGRect(x: 0, y: 0, width: nsImage.size.width, height: nsImage.size.height)
            return nsImage.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
        }
        #endif
        return nil
    }
    #else
    // Fallback for non-macOS platforms
    public func extractText(
        from image: Any,
        recognitionLanguages: [String] = ["en-US"],
        recognitionLevel: Any = 0, // Placeholder for VNRequestTextRecognitionLevel
        customWords: [String]? = nil
    ) -> Result<String, OCRError> {
        print("OCRService: OCR is only supported on macOS via Vision framework.")
        return .failure(.imageConversionError("OCR not supported on this platform."))
    }
    #endif
}
