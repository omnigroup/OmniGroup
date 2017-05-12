// Copyright 2013-2016 Omni Development, Inc. All rights reserved.
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

// For cross-platform convenience. Frameworks shouldn't have to know which platform they're on, and whether OBLogger likes to write to files on that platform.
public func OBLoggerInitializeLogLevel(_ name: String) -> OBLogger {
    let platformTruncatesLogs: Bool
    #if os(OSX)
        platformTruncatesLogs = false
    #else
        platformTruncatesLogs = true
    #endif
    let result = OBLogger(name: name, shouldLogToFile:platformTruncatesLogs)
    return result
}

