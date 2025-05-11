import Foundation

// The @objc attribute is necessary for XPC communication.
// The name provided in @objc is the one that will be used to look up the protocol.
@objc(EidonCaptureServiceProtocol)
public protocol EidonCaptureServiceProtocol {
    
    /// Tells the main Eidon application to perform an ad-hoc screenshot capture.
    /// - Parameter reply: A reply block that the service will call upon completion.
    ///                    - success: True if the capture (and initial processing steps) was deemed successful by the service, false otherwise.
    ///                    - statusMessage: An optional string containing a status or error message.
    func performAdHocCapture(with reply: @escaping (_ success: Bool, _ statusMessage: String?) -> Void)
}

// It's good practice to define your XPC service name as a constant.
// Ensure this matches the `Bundle Name` of your XPC Service target, typically reverse-DNS.
// Example: If your app's bundle ID is com.example.Eidon, and your XPC service target is EidonCaptureService,
// then the XPC service name would be com.example.Eidon.EidonCaptureService.
// This constant should be accessible by both the main app (XPC listener) and the extension (XPC caller).
public enum EidonXPCConstants {
   public static let captureServiceName = "REPLACE_WITH_YOUR_APP_BUNDLE_ID.EidonCaptureService"
}