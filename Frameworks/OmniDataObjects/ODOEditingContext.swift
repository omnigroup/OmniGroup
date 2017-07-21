// Copyright 2017 Omni Development, Inc. All rights reserved.
//
// $Id$

public extension ODOEditingContext {
    public func fetchObject<T: ODOObject>(with objectID: ODOObjectID) throws -> T {
	precondition(objectID.entity.instanceClass.isSubclass(of: T.self))
        let result = try __fetchObject(with: objectID)
        return result as! T
    }
}
