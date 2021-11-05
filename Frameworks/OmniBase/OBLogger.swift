// Copyright 2013-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

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

/// Backwards compatible cover for initilizer offering access to the given key within the shared defaults object.
public func OBLoggerInitializeLogLevel(_ name: String) -> OBLogger? {
    return OBLoggerInitializeLogLevel(key: name)
}

/// Does a one-time initialization of an OBLogger keyed to the given `key` in the `suiteName` specified database or the shared defaults if not provided.
///
/// For cross-platform convenience. Frameworks shouldn't have to know which platform they're on, and whether OBLogger likes to write to files on that platform.
public func OBLoggerInitializeLogLevel(suiteName: String? = nil, key: String) -> OBLogger? {
    let platformTruncatesLogs: Bool
    #if os(OSX)
        platformTruncatesLogs = false
    #else
        platformTruncatesLogs = true
    #endif
    let result = OBLogger(suiteName: suiteName, key: key, shouldLogToFile: platformTruncatesLogs)
    return result
}

/// Backwards compatible cover for `maintainLogLevelPreference(suiteName:key:updater:)` passing `nil` for `suiteName`.
public func maintainLogLevelPreference(for key: String, updater: ((OBLogger?) -> Void)?) {
    maintainLogLevelPreference(suiteName: nil, key: key, updater: updater)
}

/// Observes the user default for `key` in the `suiteName` specified defaults database or shared defaults, invoking `updater` with an appropriate OBLogger instance immediately and whenever the preference changes.
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
///         maintainLogLevelPreference(suiteName: nil, key: coordinatorDebugLoggerPreferenceKey) { logger in
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
/// - parameter suiteName: specified defaults database or the shared defaults if not provided
/// - parameter key: the user defaults key to read and observe
/// - parameter updater: a block that is executed whenever a new OBLogger, or the absence thereof, is needed. N.B., this block is retained for the life of the program. You probably don't want it to capture anything.
public func maintainLogLevelPreference(suiteName: String?, key: String, updater: ((OBLogger?) -> Void)?) {
    let suiteNameKey = [suiteName, key].compactMap { $0 }.joined(separator: ".")
    guard let updater = updater else {
        // unregister key
        logLevelMaintainers[suiteNameKey] = nil
        return
    }

    // add or replace maintainer
    logLevelMaintainers[suiteNameKey] = OBLogLevelMaintainer(suiteName: suiteName, key: key, updater: updater)
}

private var logLevelMaintainers: [String: OBLogLevelMaintainer] = [:]
#if swift(>=4.1)
private let observerContext = UnsafeMutableRawPointer.allocate(byteCount: 4, alignment: 4)
#else
private let observerContext = UnsafeMutableRawPointer.allocate(bytes: 4, alignedTo: 4)
#endif

private class OBLogLevelMaintainer: NSObject {
    private let suiteName: String?
    private let key: String
    private let updater: (OBLogger?) -> Void
    private lazy var userDefaults: UserDefaults = {
        if let suiteName = suiteName, let suiteNameDefaults = UserDefaults(suiteName: suiteName) {
            return suiteNameDefaults
        }
        
        return UserDefaults.standard
    }()

    init(suiteName: String?, key: String, updater: @escaping (OBLogger?) -> Void) {
        self.suiteName = suiteName
        self.key = key
        self.updater = updater
        
        super.init()
        
        // Only register 0 for the log level if a value wasn't already registered; we don't want to stomp on an existing registration.
        let registrationDomain = userDefaults.volatileDomain(forName: UserDefaults.registrationDomain)
        let registeredValue = registrationDomain[key]
        if registeredValue == nil {
            userDefaults.register(defaults: [key: 0])
        }

        userDefaults.addObserver(self, forKeyPath: key, options: [.new], context: observerContext)
    }
    
    deinit {
        userDefaults.removeObserver(self, forKeyPath: key, context: observerContext)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if context == observerContext {
            update()
            return
        }
        
        super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
    }
    
    private func update() {
        updater(OBLoggerInitializeLogLevel(suiteName: suiteName, key: key))
    }
}

