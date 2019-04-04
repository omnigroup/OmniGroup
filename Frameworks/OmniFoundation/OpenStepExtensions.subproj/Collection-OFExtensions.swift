// Copyright 2017-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import Foundation

public extension Collection {
    /// Returns the item at index `position` in the collection, or `nil` if `position` is out of bounds.
    subscript(safe position: Index) -> Iterator.Element? {
        guard position >= startIndex && position < endIndex else { return nil }
        return self[position]
    }
}

private func _comparator(for sortDescriptors: [NSSortDescriptor]) -> ((Any, Any) -> Bool) {
    return { (element1, element2) -> Bool in
        for descriptor in sortDescriptors {
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

public extension Collection where Iterator.Element: NSObjectProtocol {
    func sorted(using sortDescriptors: [NSSortDescriptor]) -> [Iterator.Element] {
        return sorted(by: _comparator(for: sortDescriptors))
    }
}

public extension Array where Iterator.Element: NSObjectProtocol {
    mutating func sort(using sortDescriptors: [NSSortDescriptor]) {
        sort(by: _comparator(for: sortDescriptors))
    }
}

// Until Swift has a standard binary search, <https://stackoverflow.com/questions/31904396/swift-binary-search-for-standard-array#33674192>
public extension Collection {
    /// Finds such index N that predicate is true for all elements up to
    /// but not including the index N, and is false for all elements
    /// starting with index N.
    /// Behavior is undefined if there is no such N.
    func binarySearch(predicate: (Iterator.Element) -> Bool) -> Index {
        var low = startIndex
        var high = endIndex
        while low != high {
            let mid = index(low, offsetBy: distance(from: low, to: high)/2)
            if predicate(self[mid]) {
                low = index(after: mid)
            } else {
                high = mid
            }
        }
        return low
    }
}
