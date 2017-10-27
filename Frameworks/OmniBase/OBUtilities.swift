// Copyright 2017 Omni Development. Inc. All rights reserved.
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
