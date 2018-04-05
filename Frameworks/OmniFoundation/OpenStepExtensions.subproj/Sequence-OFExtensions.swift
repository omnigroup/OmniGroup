// Copyright 2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation

// Hopefully short-lived hack to allow building in Xcode 9.2 and 9.3. Once we require 9.3, this should go away.
extension Sequence {
    #if swift(>=4.1)
    // Already has compactMap
    #else
    public func compactMap<Result>(_ transform: (Element) throws -> Result?) rethrows -> [Result] {
        return try flatMap(transform)
    }
    #endif
}


