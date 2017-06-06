// Copyright 2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation

public extension Collection {
    /// Returns `true` if `matcher` returns `true` for any element in the collection.
    ///
    /// - parameter matcher: executed O(n) times, where n is the size of the collection
    func any(where matcher: (Iterator.Element) throws -> Bool) rethrows -> Bool {
        return try index(where: matcher) != nil
    }
    
    /// Returns `true` if `matcher` returns `true` for every element in the collection.
    ///
    /// - parameter matcher: executed O(n) times, where n is the size of the collection
    func all(where matcher: (Iterator.Element) throws -> Bool) rethrows -> Bool {
        return try index(where: { try !matcher($0) }) == nil
    }

    /// Returns the item at index `position` in the collection, or `nil` if `position` is out of bounds.
    subscript(safe position: Index) -> Iterator.Element? {
        guard position >= startIndex && position < endIndex else { return nil }
        return self[position]
    }
}

public extension Collection where Iterator.Element: NSObjectProtocol {
    func sorted(using descriptors: [NSSortDescriptor]) -> [Iterator.Element] {
        return self.sorted { (element1, element2) in
            for descriptor in descriptors {
                let compareResult = descriptor.compare(element1, to: element2)
                switch compareResult {
                case .orderedSame: continue
                case .orderedAscending: return true
                case .orderedDescending: return false
                }
            }
            return false
        }
    }
}

