// Copyright 2013-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation


// Based on current usage, with an eye toward os.log (available 10.12, iOS10)
// NB setting user defaults to `1` will log all the things, `2` fewer things.

public enum OBLoggerLevel: UInt8 {
    case off = 0
    case info
    case debug
}

// os.log level also currently defines .error = 16, .fault = 17

/// Log just the given message, without any format arguments. (Useful for Swift compatibility.)
public func OBLogS(_ logger: OBLogger?, _ messageLevel: OBLoggerLevel, _ message: String) {
    OBLogSwiftVariadicCover(logger, Int(messageLevel.rawValue), message)
}

/// Does a one-time initialization of an OBLogger keyed to the given name.
///
/// For cross-platform convenience. Frameworks shouldn't have to know which platform they're on, and whether OBLogger likes to write to files on that platform.
public func OBLoggerInitializeLogLevel(_ name: String) -> OBLogger? {
    let platformTruncatesLogs: Bool
    #if os(OSX)
        platformTruncatesLogs = false
    #else
        platformTruncatesLogs = true
    #endif
    let result = OBLogger(name: name, shouldLogToFile:platformTruncatesLogs)
    return result
}

/// Observes the user default for `key`, invoking `updater` with an appropriate OBLogger instance immediately and whenever the preference changes.
///
/// Sample Swift-only use:
///
/// ```
/// private let coordinatorDebugLoggerPreferenceKey = "CoordinatorDebugLogger"
/// private var coordinatorDebugLogger: OBLogger? = nil
///
/// func coordinatorDebugLog(_ messageProvider: @autoclosure () -> String, level: OBLoggerLevel = .debug) {
///     guard let logger = coordinatorDebugLogger else {
///         return
///     }
///
///     let message = messageProvider()
///     OBLogS(logger, level, message)
/// }
///
/// class CoordinatorDebugLoggerConfigurator: NSObject {
///     static func configure() {
///         maintainLogLevelPreference(for: coordinatorDebugLoggerPreferenceKey) { logger in
///             coordinatorDebugLogger = logger
///         }
///     }
///
///     static var logger: OBLogger? { // Objective-C cover
///         return coordinatorDebugLogger
///     }
/// }
/// ```
///
/// Somewhere in the app initialization code, start maintaining the log level preference:
/// ```
/// CoordinatorDebugLoggerConfigurator.configure()
/// ```
///
/// Then to log messages:
/// ```
/// coordinatorDebugLog("Some debug message")
/// coordinatorDebugLog("Some info message", level: .info)
/// ```
///
/// If necessary, Objective-C code could use a cover macro:
/// ```
/// #define COORDINATOR_DEBUG_LOG(format, ...) do { \
///     OBLog(CoordinatorDebugLoggerConfigurator.logger, 1, format, ## __VA_ARGS__); \
/// } while (0)
/// ```
/// 
/// And call it like:
/// ```
/// COORDINATOR_DEBUG_LOG("Message: %@", parameter);
/// ```
///
/// - parameter key: the user defaults key to read and observe
/// - parameter updater: a block that is executed whenever a new OBLogger, or the absence thereof, is needed. N.B., this block is retained for the life of the program. You probably don't want it to capture anything.
public func maintainLogLevelPreference(for key: String, updater: ((OBLogger?) -> Void)?) {
    guard let updater = updater else {
        // unregister key
        logLevelMaintainers[key] = nil
        return
    }

    // add or replace maintainer
    logLevelMaintainers[key] = OBLogLevelMaintainer(key: key, updater: updater)
}

private var logLevelMaintainers: [String: OBLogLevelMaintainer] = [:]

private class OBLogLevelMaintainer: NSObject {
    private let key: String
    private let updater: (OBLogger?) -> Void
    private let observerContext = UnsafeMutableRawPointer.allocate(bytes: 4, alignedTo: 4)
    
    init(key: String, updater: @escaping (OBLogger?) -> Void) {
        self.key = key
        self.updater = updater
        
        super.init()
        
        UserDefaults.standard.register(defaults: [key: 0])
        UserDefaults.standard.addObserver(self, forKeyPath: key, options: [.new], context: observerContext)
    }
    
    deinit {
        UserDefaults.standard.removeObserver(self, forKeyPath: key)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if context == observerContext {
            update()
            return
        }
        
        super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }
    
    private func update() {
        updater(OBLoggerInitializeLogLevel(key))
    }
}

