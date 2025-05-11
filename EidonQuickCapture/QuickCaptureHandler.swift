import Cocoa
import os.log

class QuickCaptureHandler: NSObject {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.eidon.EidonQuickCapture", category: "QuickCaptureHandler")

    @objc func performQuickCapture(_ pboard: NSPasteboard?, userData: String?, error: NSErrorPointer) {
        logger.info("Quick Action: performQuickCapture invoked.")

        let connection = NSXPCConnection(serviceName: EidonXPCConstants.captureServiceName)
        connection.remoteObjectInterface = NSXPCInterface(with: EidonCaptureServiceProtocol.self)
        connection.resume()

        guard let serviceProxy = connection.remoteObjectProxyWithErrorHandler({ [weak self] rpcError in
            self?.logger.error("Quick Action: XPC remote proxy error: \(rpcError.localizedDescription, privacy: .public)")
            if error != nil {
                 error.pointee = rpcError as NSError
            }
            // Invalidate connection on error to allow for a fresh one next time.
            connection.invalidate()
        }) as? EidonCaptureServiceProtocol else {
            logger.error("Quick Action: Failed to get XPC service proxy.")
            if error != nil {
                let err = NSError(domain: "EidonQuickCaptureErrorDomain", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Failed to connect to Eidon helper service."])
                error.pointee = err
            }
            connection.invalidate()
            return
        }

        logger.info("Quick Action: Calling performAdHocCapture on XPC service proxy.")
        serviceProxy.performAdHocCapture { [weak self] (success, statusMessage) in
            if success {
                self?.logger.info("Quick Action: XPC service reported capture success. Message: \(statusMessage ?? "None")")
                // Optionally, show a *local* notification from the extension on success
                // self?.showSuccessNotification()
            } else {
                self?.logger.error("Quick Action: XPC service reported capture failure. Message: \(statusMessage ?? "Unknown error")")
                // Optionally, show a *local* notification from the extension on failure
                // self?.showFailureNotification(message: statusMessage)
            }
            
            connection.invalidate() // Invalidate after one-shot use
            
            // The extension should terminate after its work.
            // If the Quick Action was UI-based (via NSExtensionPrincipalViewControllerClassIdentifier),
            // it would manage its own dismissal. For non-UI, it exits.
        }
    }
    
    // Optional: Helper for local notifications from the extension (requires UserNotifications framework)
    /*
    private func showSuccessNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Eidon Capture"
        content.body = "Screenshot captured successfully!"
        // content.sound = .default // If desired
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("Quick Action: Failed to show success notification: \(error.localizedDescription)")
            }
        }
    }

    private func showFailureNotification(message: String?) {
        let content = UNMutableNotificationContent()
        content.title = "Eidon Capture Failed"
        content.body = message ?? "Could not capture screenshot via Eidon."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                self.logger.error("Quick Action: Failed to show failure notification: \(error.localizedDescription)")
            }
        }
    }
    */
    
    deinit {
        logger.info("QuickCaptureHandler deinitialized.")
    }
}