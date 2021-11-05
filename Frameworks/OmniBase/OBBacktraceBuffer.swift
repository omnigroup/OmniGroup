// Copyright 1997-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation

extension String {

    /// This intentionally leaks a string, so that it's `utfString` can be passed to OBRecordBacktrace() in cases where the app is about to crash on a fatalError/preconditionFailure. This shouldn't be used for other backtrace buffers since it leaks, but this allows reporting dynamic strings in these cases.
    public var leakedCopy: NSString {
        let copy = self as NSString
        OBStrongRetain(copy)
        return copy
    }
}

public func OBRecordBacktraceS(_ message: StaticString, _ optype: OBBacktraceBufferType) {
    _OBRecordBacktraceU8(message.utf8Start, optype)
}
public func OBRecordBacktraceWithContextS(_ message: StaticString, _ optype: OBBacktraceBufferType, _ context: AnyObject?) {
    _OBRecordBacktraceWithContextU8(message.utf8Start, optype, context)
}
public func OBRecordBacktraceWithIntContextS(_ message: StaticString, _ optype: OBBacktraceBufferType, _ context: UInt) {
    _OBRecordBacktraceWithIntContextU8(message.utf8Start, optype, context)
}
public func OBRecordBacktraceWithObjectS(_ object: AnyObject, _ optype: OBBacktraceBufferType) {
    let className = String(describing: type(of: object))
    _OBRecordBacktraceWithContextI8(className.leakedCopy.utf8String, optype, object)
}
