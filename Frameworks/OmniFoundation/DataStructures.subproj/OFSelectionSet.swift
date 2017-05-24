// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// RCS_ID("$Id$");

import Foundation

extension OFSelectionSet {
    public func insertOrderSortedObjects<Class : NSObject>(ofClass cls: Class.Type) -> [Class] {
        // TODO: The guts of this method could be cleaner once the rest of the class is more type-safe.
        let predicateResults = copyObjectsSatisfyingPredicateBlock { $0 is Class }
        let instances:[Class] = predicateResults as! [Class]
        return objectsSorted(byInsertionOrder: instances) as! [Class]
    }
}
