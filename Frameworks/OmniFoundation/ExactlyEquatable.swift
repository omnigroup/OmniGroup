// Copyright 2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation

// ExactlyEquatable allows extending `===` to non-class types. In particular, this is useful for enums with object-typed payloads.

// Declared so non-object types can be placed in Buckets.
public protocol ExactlyEquatable {
    func exactlyEquals(_ other: ExactlyEquatable) -> Bool
}

// We can't directly extend AnyObject, but we can extend the protocol with a default implementation so that Swift classes (that do not subclass NSObject) can pick it up by declaring conformance
extension ExactlyEquatable where Self : AnyObject {
    public func exactlyEquals(_ other: ExactlyEquatable) -> Bool {
        return self === (other as AnyObject)
    }
}

extension NSObject: ExactlyEquatable {}

