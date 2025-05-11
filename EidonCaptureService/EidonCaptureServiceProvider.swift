import Foundation
import os.log

// This class implements the protocol which we have defined. It provides the actual behavior for the service.
// It will be instantiated by the XPC system when a connection is made.
// This class needs to be part of the XPC Service target.
class EidonCaptureServiceProvider: NSObject, EidonCaptureServiceProtocol {
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? EidonXPCConstants.captureServiceName, category: "EidonCaptureServiceProvider")

    override init() {
        super.init()
        // Note: If this XPC service runs in the main app's process, ensure any shared resource
        // access (like ScreenshotService.shared) is thread-safe if accessed from multiple XPC connections.
        // For simple, infrequent calls, it's often fine.
        logger.info("EidonCaptureServiceProvider instance created.")
    }

    // This is the method called by the Quick Action Extension.
    @objc func performAdHocCapture(with reply: @escaping (Bool, String?) -> Void) {
        logger.info("XPC Service: Received performAdHocCapture request from extension.")
        
        // IMPORTANT: This XPC service will run in the main application's process space
        // if vended by a listener in the AppDelegate. This allows direct calls to main app singletons.
        // If it were a separate launchd XPC process, this direct call would not work.
        ScreenshotService.shared.captureAndProcessSingleFrame { success in
            if success {
                self.logger.info("XPC Service: Ad-hoc capture reported success to extension.")
                reply(true, "Capture initiated successfully.")
            } else {
                self.logger.error("XPC Service: Ad-hoc capture reported failure to extension.")
                reply(false, "Capture failed or no screens were processed.")
            }
        }
    }
    
    deinit {
        // This might not be called frequently if the system keeps one instance per connection
        // or if the service is long-lived.
        logger.info("EidonCaptureServiceProvider instance deinitialized.")
    }
}