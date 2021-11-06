// Copyright 2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import Combine

public class KeyPathBox<ObjectType : NSObject, ValueType : Equatable> : ObservableObject {

    public let object: ObjectType
    public let keyPath: ReferenceWritableKeyPath<ObjectType, ValueType>

    public let objectWillChange = ObservableObjectPublisher()

    private var observation: NSObjectProtocol!

    public init(object: ObjectType, keyPath: ReferenceWritableKeyPath<ObjectType, ValueType>) {
        self.object = object
        self.keyPath = keyPath

        self.observation = object.observe(keyPath, options: [.prior]) { [weak self] object, change in
            self?.handleChange(change)
        }
    }

    // Not marked @Published since we handle sending to objectWillChange via the KVO callback
    public var value: ValueType {
        get {
            object[keyPath: keyPath]
        }
        set {
            object[keyPath: keyPath] = newValue
        }
    }

    // MARK:- Private

    private func handleChange(_ change: NSKeyValueObservedChange<ValueType>) {
        // Even if we add .new/.old to the options, the prior notification doesn't have the new value. So, we can't filter out redundant changes and rely on callers to avoid doing them. If we end up caching the latest value here, we could only update our published value on a non-prior callback and avoid redundant calls. But then we'd have some risk of observers that accidentally look at both us and the underlying object somehow and getting out-of-date results.
        if change.isPrior {
            objectWillChange.loggingSend()
        }
    }

}

// It may be possible to merge these two with some generics magic, but hopefully not needed.

public class ReadOnlyKeyPathBox<ObjectType : NSObject, ValueType : Equatable> : ObservableObject {

    public let object: ObjectType
    public let keyPath: KeyPath<ObjectType, ValueType>

    public let objectWillChange = ObservableObjectPublisher()

    private var observation: NSObjectProtocol!

    public init(object: ObjectType, keyPath: KeyPath<ObjectType, ValueType>) {
        self.object = object
        self.keyPath = keyPath

        self.observation = object.observe(keyPath, options: [.prior]) { [weak self] object, change in
            self?.handleChange(change)
        }
    }

    // Not marked @Published since we handle sending to objectWillChange via the KVO callback
    public var value: ValueType {
        get {
            object[keyPath: keyPath]
        }
    }

    // MARK:- Private

    private func handleChange(_ change: NSKeyValueObservedChange<ValueType>) {
        // Even if we add .new/.old to the options, the prior notification doesn't have the new value. So, we can't filter out redundant changes and rely on callers to avoid doing them. If we end up caching the latest value here, we could only update our published value on a non-prior callback and avoid redundant calls. But then we'd have some risk of observers that accidentally look at both us and the underlying object somehow and getting out-of-date results.
        if change.isPrior {
            objectWillChange.loggingSend()
        }
    }

}

// As above, but erases the object type, and supports constant values

public class AnyReadOnlyKeyPathBox<ValueType : Equatable> : ObservableObject {

    private let getter: () -> ValueType
    public let objectWillChange = ObservableObjectPublisher()

    private var observation: NSObjectProtocol?

    public init<ObjectType: NSObject>(object: ObjectType, keyPath: KeyPath<ObjectType, ValueType>) {
        self.getter = {
            object[keyPath: keyPath]
        }

        self.observation = object.observe(keyPath, options: [.prior]) { [weak self] object, change in
            self?.handleChange(change)
        }
    }

    public init(value: ValueType) {
        self.getter = {
            value
        }
        self.observation = nil
    }

    // Not marked @Published since we handle sending to objectWillChange via the KVO callback
    public var value: ValueType {
        get {
            getter()
        }
    }

    // MARK:- Private

    private func handleChange(_ change: NSKeyValueObservedChange<ValueType>) {
        // Even if we add .new/.old to the options, the prior notification doesn't have the new value. So, we can't filter out redundant changes and rely on callers to avoid doing them. If we end up caching the latest value here, we could only update our published value on a non-prior callback and avoid redundant calls. But then we'd have some risk of observers that accidentally look at both us and the underlying object somehow and getting out-of-date results.
        if change.isPrior {
            objectWillChange.loggingSend()
        }
    }

}
