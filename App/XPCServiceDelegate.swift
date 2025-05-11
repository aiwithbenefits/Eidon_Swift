import Foundation
import os.log

// This class acts as the delegate for the NSXPCListener in the main application (AppDelegate).
// It's responsible for vending instances of your service provider (EidonCaptureServiceProvider)
// when new connections are made from clients like the Quick Action Extension.
class XPCServiceDelegate: NSObject, NSXPCListenerDelegate {
    
    // Use the main app's bundle identifier for logging from this delegate.
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.eidon.EidonApp.XPCDelegate", category: "AppXPCServiceDelegate")

    /// Called by the `NSXPCListener` (managed by `AppDelegate`) when a new
    /// connection from a client (e.g., the Quick Action Extension) is received.
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        logger.info("Main App XPC Listener: Attempting to accept new connection for capture service.")
        
        // 1. Configure the interface that the service exports.
        //    This tells the connection what methods the client (Quick Action) can call.
        //    It must match the protocol defined in `EidonCaptureServiceProtocol.swift`.
        newConnection.exportedInterface = NSXPCInterface(with: EidonCaptureServiceProtocol.self)
        
        // 2. Create an instance of the object that will handle the client's requests.
        //    This object must conform to `EidonCaptureServiceProtocol`.
        //    `EidonCaptureServiceProvider` should be part of the main app target or a module it includes.
        //    Ensure EidonCaptureServiceProvider.swift is correctly placed and targeted for the main app.
        let exportedObject = EidonCaptureServiceProvider() 
        newConnection.exportedObject = exportedObject
        
        // 3. Resume the connection.
        //    This allows the system to start delivering messages from the client to the exportedObject.
        newConnection.resume()
        
        logger.info("Main App XPC Listener: Successfully accepted and configured new connection for capture service.")
        // Return true to accept the connection.
        return true
    }
}