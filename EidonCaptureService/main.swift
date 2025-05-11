import Foundation
import os.log

// Logger for the XPC service's main entry point.
// The Bundle.main.bundleIdentifier for an XPC service will be its own identifier.
private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? EidonXPCConstants.captureServiceName, category: "XPCMain")

/// The `NSXPCListenerDelegate` for the XPC service.
/// This delegate is responsible for accepting new incoming connections from clients (like the Quick Action Extension)
/// and configuring them with the exported object and interface.
class XPCServiceDelegate: NSObject, NSXPCListenerDelegate {
    
    /// Called by the `NSXPCListener` when a new connection from a client is received.
    ///
    /// - Parameters:
    ///   - listener: The listener that accepted the new connection.
    ///   - newConnection: The new connection from the client.
    /// - Returns: `true` to accept the new connection and configure it, or `false` to reject it.
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        logger.info("XPC Listener: Attempting to accept new connection.")
        
        // 1. Configure the interface that the service exports.
        //    This tells the connection what methods the client can call.
        //    It must match the protocol defined in `EidonCaptureServiceProtocol.swift`.
        newConnection.exportedInterface = NSXPCInterface(with: EidonCaptureServiceProtocol.self)
        
        // 2. Create an instance of the object that will handle the client's requests.
        //    This object must conform to `EidonCaptureServiceProtocol`.
        let exportedObject = EidonCaptureServiceProvider()
        newConnection.exportedObject = exportedObject
        
        // 3. Resume the connection.
        //    This allows the system to start delivering messages from the client to the exported object.
        //    The connection will be kept alive as long as either end holds a reference to it
        //    or until it's explicitly invalidated.
        newConnection.resume()
        
        logger.info("XPC Listener: Successfully accepted and configured new connection.")
        return true
    }
}

// --- XPC Service Entry Point ---

// 1. Create an instance of the service delegate.
let delegate = XPCServiceDelegate()

// 2. Get the shared `NSXPCListener` instance for this XPC service.
//    `.service()` is used for XPC services that are bundled within an application.
//    The system (launchd via the main app) manages the lifecycle of this listener.
let listener = NSXPCListener.service()
listener.delegate = delegate

// 3. Resume the listener to start accepting incoming connections.
//    The listener will now run on its own queue, managed by the system.
logger.info("EidonCaptureService XPC listener starting...")
listener.resume()

// For an XPC service bundled with an app and managed via `NSXPCListener.service()`,
// you typically do not need to manually run a RunLoop here. The service's lifecycle
// is tied to the main application that vends it or to active connections.
// `dispatchMain()` or `RunLoop.current.run()` would be more common for standalone daemons/agents
// or XPC services managed directly by launchd via their own .plist file in /Library/LaunchAgents etc.
// Since this is an app-embedded XPC service, this setup should be sufficient.
// The service will stay alive as long as the listener is valid or there are active connections.
logger.info("EidonCaptureService setup complete. Listener resumed and waiting for connections.")

// To ensure the XPC service process doesn't exit immediately if launched independently (though not typical for .service())
// and to handle signals gracefully if it were a standalone daemon, you might add:
// dispatchMain() // This would effectively run a main run loop.
// However, for an XPC service vended by an app, this is usually not necessary.