// Copyright 1997-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation

public func OBRecordBacktraceS(_ message: StaticString, _ optype: OBBacktraceBufferType) {
    _OBRecordBacktraceU8(message.utf8Start, optype)
}
public func OBRecordBacktraceWithContextS(_ message: StaticString, _ optype: OBBacktraceBufferType, _ context: AnyObject?) {
    _OBRecordBacktraceWithContextU8(message.utf8Start, optype, context)
}
public func OBRecordBacktraceWithIntContextS(_ message: StaticString, _ optype: OBBacktraceBufferType, _ context: UInt) {
    _OBRecordBacktraceWithIntContextU8(message.utf8Start, optype, context)
}
