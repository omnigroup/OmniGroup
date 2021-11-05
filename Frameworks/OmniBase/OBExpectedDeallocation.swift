// Copyright 2015-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation

// We can't use the ObjC macro wrapper, so replicate it here with an @autoclosure block here to avoid evaluating the object if we aren't going to use it.
public func ExpectDeallocation(of object: @autoclosure () -> AnyObject?) {
    if OBExpectedDeallocationsIsEnabled(), let object = object() {
        _OBExpectDeallocation(object)
    }
}
