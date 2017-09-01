// Copyright 2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

public extension ODOEditingContext {
    public func fetchObject<T: ODOObject>(with objectID: ODOObjectID) throws -> T {
	precondition(objectID.entity.instanceClass.isSubclass(of: T.self))
        let result = try __fetchObject(with: objectID)
        return result as! T
    }
}
