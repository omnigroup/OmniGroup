// Copyright 2017-2021 Omni Development. Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation

public func OBStopInDebugger(_ message: @autoclosure () -> String, file: String = #file, line: UInt32 = #line, function: String = #function) {
    _OBStopInDebugger(file, line, function, message())
}

#if DEBUG
private let LogAsyncOperations = false

public func OBMainAsync(execute operation: @escaping () -> Void, function: String = #function, file: String = #file, line: Int = #line) {
    if LogAsyncOperations {
        print("🟪🕕 \(function) at \(file):\(line)")
    }
    DispatchQueue.main.async {
        if LogAsyncOperations {
            print("🟪⏰ \(function) at \(file):\(line)")
        }
        operation()
    }
}

public func OBMainAsyncAfter(deadline: DispatchTime, execute operation: @escaping () -> Void, function: String = #function, file: String = #file, line: Int = #line) {
    if LogAsyncOperations {
        print("🟪🕕 \(function) at \(file):\(line)")
    }
    DispatchQueue.main.asyncAfter(deadline: deadline) {
        if LogAsyncOperations {
            print("🟪⏰ \(function) at \(file):\(line)")
        }
        operation()
    }
}
#else
@inlinable
public func OBMainAsync(execute operation: @escaping () -> Void, function: String = #function, file: String = #file, line: Int = #line) {
    DispatchQueue.main.async(execute: operation)
}
@inlinable
public func OBMainAsyncAfter(deadline: DispatchTime, execute operation: @escaping () -> Void, function: String = #function, file: String = #file, line: Int = #line) {
    DispatchQueue.main.asyncAfter(deadline: deadline, execute: operation)
}
#endif
