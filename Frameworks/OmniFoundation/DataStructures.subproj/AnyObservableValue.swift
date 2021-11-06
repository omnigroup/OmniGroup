// Copyright 2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import Combine
import SwiftUI

@available(OSX 10.15, *)
public final class ConstantObservableValue<Output> : AnyObservableValue<Output> {    
    override func willSetValue(newValue: Output) {
        preconditionFailure("Attempted to set new value for constant observable")
    }
    
    required public init(value: Output) {
        super.init(initialValue: value)
    }
    
    @discardableResult
    override public func update(_ newValue: Output) -> Bool where Output : Equatable { assertionFailure("Attempted to set new value for constant observable"); return false }
}

@available(OSX 10.15, *)
public class AnyObservableValue<Value>: ObservableObject {
    public let objectWillChange: ObservableObjectPublisher
    @Published final public private(set) var value: Value {
        willSet {
            if wantsObjectWillChangeSendOnValueSet {
                objectWillChange.loggingSend()
            }
            
            willSetValue(newValue: newValue)
        }
        didSet {
            didSetValue(value: value)
        }
    }
    
    fileprivate static var keyPathForValueBinding: ReferenceWritableKeyPath<AnyObservableValue<Value>, Value> { return \AnyObservableValue<Value>.value }
    
    public var valuePublisher: Published<Value>.Publisher { return $value }
    
    var wantsObjectWillChangeSendOnValueSet: Bool { return true }
    func willSetValue(newValue: Value) {}
    func didSetValue(value: Value) {}
    
    init(objectWillChange: ObservableObjectPublisher = ObservableObjectPublisher(), initialValue: Value) {
        self.objectWillChange = objectWillChange
        self.value = initialValue
    }
    
    @discardableResult
    public func update(_ newValue: Value) -> Bool where Value : Equatable {
        if value != newValue {
            value = newValue
            return true
        }
        return false
    }
}

extension AnyObservableValue where Value == Bool {
    public func toggle() {
        update(!value)
    }
}

extension ObservedObject.Wrapper {
    public func bindingForObservableValue<Value>() -> Binding<Value> where ObjectType == AnyObservableValue<Value> {
        return self[dynamicMember: ObjectType.keyPathForValueBinding]
    }
}

@available(OSX 10.15, *)
public final class PublishedPropertyWrapper<Value>: AnyObservableValue<Value> {
    private var cancellableSet: Set<AnyCancellable> = []
    
    public required init(publishedProperty: Published<Value>.Publisher) where Value: Equatable {
        var initialValue: Value! = nil
        let _ = publishedProperty.sink(receiveValue: { value in
            initialValue = value
        })
        
        super.init(initialValue: initialValue)
        
        publishedProperty.dropFirst().sink(receiveValue: { [weak self] newValue in
            guard let self = self else { return }
            self.update(newValue)
        }).store(in: &cancellableSet)
    }
}

