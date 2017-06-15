// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation

extension NSLocking {

    public func protect<T>(_ action: () throws -> T) rethrows -> T {
        lock()
        defer {
            unlock()
        }
        return try action()
    }
    
}
