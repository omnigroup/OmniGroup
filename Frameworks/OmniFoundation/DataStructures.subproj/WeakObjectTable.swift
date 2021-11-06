// Copyright 2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation

// Extending NSMapTable is hindered by ObjC generics not being available at runtime.

/// A table of strong keys to weak object references..
public class WeakObjectTable<KeyType : Hashable, ValueType : AnyObject> {

    private struct Item {
        weak var value: ValueType?
    }

    private var map = [KeyType : Item]()

#if DEBUG
    public var debugHeading: String? = nil
#endif
    fileprivate func debugLog(_ message: @autoclosure () -> String) {
#if DEBUG
        if let debugHeading = debugHeading {
            print(debugHeading + " " + message())
        }
#endif
    }

    public init() {}

    /// Copy the keys in the table with non-nil object values. As a side-effect, any entries where the object value has been deallocated will be removed.
    public func keys() -> [KeyType] {
        var result = [KeyType]()
        var remove = [KeyType]()

        map.forEach { k, v in
            if v.value != nil {
                result.append(k)
            } else {
                remove.append(k)
            }
        }

        remove.forEach { k in
            debugLog("Removing value for \(k)")
            map.removeValue(forKey: k)
        }

        return result
    }

    /// Look up the value for a given key and return it if present.
    public func fetch(key: KeyType) -> ValueType? {
        if let existing = map[key] {
            if let value = existing.value {
                return value
            } else {
                debugLog("Removing value for \(key)")
                map.removeValue(forKey: key)
            }
        }
        return nil
    }

    /// Look up the value for a given key. If absent, it will be created with the given block.
    public func fetch(key: KeyType, transform: (KeyType) -> ValueType) -> ValueType {
        if let existing = map[key] {
            if let value = existing.value {
                return value
            } else {
                debugLog("Removing value for \(key)")
                map.removeValue(forKey: key)
            }
        }
        let value = transform(key)
        debugLog("Adding value \(value) for \(key)")
        map[key] = Item(value: value)
        return value
    }

    /// Iterate the table performing and apply an action on each pair.
    public func apply(action: (KeyType, ValueType) -> Void) {
        for k in keys() {
            guard let item = map[k], let value = item.value else { assertionFailure(); continue } // We just prune the table in keys()
            action(k, value)
        }
    }
}

@available(OSX 10.15, *)
extension WeakObjectTable {

    /// Update the value on each PropertyBox, taking care to not trigger the published `value` unless the new value is not equal to the old.
    public func update<BoxValue: Equatable>(transform: (KeyType) -> BoxValue) where ValueType : PropertyBox<BoxValue> {
        for k in keys() {
            guard let item = map[k], let box = item.value else { assertionFailure(); continue } // We just prune the table in keys()

            let newValue = transform(k)
            
            if box.update(newValue) {
                debugLog("Updating value to \(newValue) for \(k)")
            }
        }
    }

}
