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
            isSettingValue = true
            
            if wantsObjectWillChangeSendOnValueSet {
                OFPublisherDebugLog("\(type(of: self)).value set to \(value) \((#file as NSString).lastPathComponent):\(#line)")
                objectWillChange.send()
            }
            
            willSetValue(newValue: newValue)            
        }
        didSet {
            didSetValue(value: value)
            isSettingValue = false
        }
    }
    
    fileprivate static var keyPathForValueBinding: ReferenceWritableKeyPath<AnyObservableValue<Value>, Value> { return \AnyObservableValue<Value>.value }
    
    public var valuePublisher: Published<Value>.Publisher { return $value }
    
    var wantsObjectWillChangeSendOnValueSet: Bool { return true }
    var acceptsReentrantValueSets: Bool { return false }
    func willSetValue(newValue: Value) {}
    func didSetValue(value: Value) {}
    
    private var reentrantValueToSet: Value? = nil
    private var isSettingValue = false {
        didSet {
            if let reentrantValueToSet = reentrantValueToSet {
                self.reentrantValueToSet = nil
                value = reentrantValueToSet
            }
        }
    }
    
    init(objectWillChange: ObservableObjectPublisher = ObservableObjectPublisher(), initialValue: Value) {
        self.objectWillChange = objectWillChange
        self.value = initialValue
    }
    
    @discardableResult
    public func update(_ newValue: Value) -> Bool where Value : Equatable {
        guard !isSettingValue else {
            if acceptsReentrantValueSets {
                assert(reentrantValueToSet == nil, "Attempted multiple reentrant value sets- intermediate update to \(String(describing: reentrantValueToSet)) will be dropped on the floor in favor of new value \(newValue).")
                reentrantValueToSet = newValue
                return true
            } else {
                assertionFailure("Attempted reentrant value set- update to \(newValue) will be dropped on the floor.")
                return false
            }
        }
        
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
    
    public func ternary<Output: Equatable>(trueCase: AnyObservableValue<Output>, falseCase: AnyObservableValue<Output>, canSetValue: Bool = false) -> AnyObservableValue<Output> {
        if let constant = self as? ConstantObservableValue<Bool> {
            return constant.value ? trueCase : falseCase
        } else {
            if canSetValue {
                return ObservablePropertyCollator(source1: self, source2: trueCase, source3: falseCase, collation: { condition, trueCase, falseCase in
                    return condition ? trueCase : falseCase
                }) { output in
                    if output == trueCase.value {
                        assert(falseCase.value != output)
                        self.update(true)
                    } else if output == falseCase.value {
                        self.update(false)
                    } else {
                        assertionFailure("Unclear update value")
                    }
                }
            } else {
                return ObservablePropertyCollator(source1: self, source2: trueCase, source3: falseCase, collation: { condition, trueCase, falseCase in
                    return condition ? trueCase : falseCase
                })
            }
        }
    }
}

extension AnyObservableValue {
    static public func constant(_ value: Value) -> ConstantObservableValue<Value> {
        return ConstantObservableValue(value: value)
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

