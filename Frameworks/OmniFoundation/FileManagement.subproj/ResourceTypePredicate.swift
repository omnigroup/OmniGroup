// Copyright 2016-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation

// This protocol allows test bundles to declare their own conforming types (test bundles can't declare UTIs).
@objc(OFResourceTypePredicate) public protocol ResourceTypePredicate {
    func matchesFileType(_ fileType: String) -> Bool
}

// A predicate that uses UTI conformance
@objc(OFUTIResourceTypePredicate) public class UTIResourceTypePredicate : NSObject, ResourceTypePredicate {

    let fileTypes: [UTI]

    public init(fileTypes: [UTI]) {
        self.fileTypes = fileTypes
    }

    @objc public init(fileTypes: [String]) {
        self.fileTypes = fileTypes.map { return UTI($0) }
    }

    override public var description: String {
        let typeNames = fileTypes.map { $0.rawFileType }
        return "<UTI in [\(typeNames.joined(separator: ", "))]>"
    }

    public func matchesFileType(_ fileType: String) -> Bool {
        return UTI(fileType).conformsToAny(fileTypes)
    }
}
