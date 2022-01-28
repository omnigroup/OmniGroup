// Copyright 2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import Combine

public struct EmptyValue {}

@available(OSX 10.15, *)
public class ObservablePropertyCollator<Value1, Value2, Value3, Value4, Value5, Value6, OutputType: Equatable>: AnyObservableValue<OutputType> {
        
    private var cancellableSet: Set<AnyCancellable> = []
    private var strongSourceReferences: [Any]
    
    private let setValue: ((OutputType)->Void)?

    public init(source1: AnyObservableValue<Value1>, source2: AnyObservableValue<Value2>, source3: AnyObservableValue<Value3>, source4: AnyObservableValue<Value4>, source5: AnyObservableValue<Value5>, source6: AnyObservableValue<Value6>, collation: @escaping (Value1, Value2, Value3, Value4, Value5, Value6)->OutputType, setValue: ((OutputType)->Void)? = nil) {
        strongSourceReferences = [source1, source2, source3, source4, source5, source6]
        self.setValue = setValue
        
        super.init(initialValue: collation(source1.value, source2.value, source3.value, source4.value, source5.value, source6.value))
        
        source1.valuePublisher.combineLatest(source2.valuePublisher.combineLatest(source3.valuePublisher, source4.valuePublisher, source5.valuePublisher), source6.valuePublisher) { v1, tuple, v6 -> OutputType in
            let (v2, v3, v4, v5) = tuple
            return collation(v1, v2, v3, v4, v5, v6)
        }.sink(receiveValue: { [weak self] newValue in
            guard let self = self else { return }
            guard !self.isPerformingBindingRequestedValueSet else { return }
            self.isPerformingObservationTriggeredValueSet = true
            self.forceUpdate(to: newValue)
            self.isPerformingObservationTriggeredValueSet = false
        }).store(in: &cancellableSet)
    }
    
    private var isPerformingManuallyRequestedValueSet = false
    private var isPerformingObservationTriggeredValueSet = false
    private var isPerformingBindingRequestedValueSet = false
    
    
    @discardableResult
    override public func update(_ newValue: OutputType) -> Bool where OutputType : Equatable {
        guard let setValue = setValue else { assertionFailure("Attempted update to a collation with no set-value closure."); return false }
        
        isPerformingManuallyRequestedValueSet = true
        setValue(newValue)
        isPerformingManuallyRequestedValueSet = false
        
        return true
    }
    
    override func didSetValue(value: OutputType) {
        guard !isPerformingManuallyRequestedValueSet && !isPerformingObservationTriggeredValueSet else { return }
        
        // If our value was not set by a programmatic request or observation-triggered update, then it was updated by a binding. We should update our source object for the new value.
        guard let setValue = setValue else {
            return
        }
        isPerformingBindingRequestedValueSet = true
        setValue(value)
        isPerformingBindingRequestedValueSet = false
    }
    
    private func forceUpdate(to value: OutputType) {
        super.update(value)
    }
}

private let emptyValuePublisher = ConstantObservableValue<EmptyValue>(value: EmptyValue())

extension ObservablePropertyCollator where Value6 == EmptyValue {
    public convenience init(source1: AnyObservableValue<Value1>, source2: AnyObservableValue<Value2>, source3: AnyObservableValue<Value3>, source4: AnyObservableValue<Value4>, source5: AnyObservableValue<Value5>, collation: @escaping (Value1, Value2, Value3, Value4, Value5)->OutputType, setValue: ((OutputType)->Void)? = nil) {
        self.init(source1: source1, source2: source2, source3: source3, source4: source4, source5: source5, source6: emptyValuePublisher, collation: { value1, value2, value3, value4, value5, _ in
            return collation(value1, value2, value3, value4, value5)
        }, setValue: setValue)
    }
}

extension ObservablePropertyCollator where Value5 == EmptyValue, Value6 == EmptyValue {
    public convenience init(source1: AnyObservableValue<Value1>, source2: AnyObservableValue<Value2>, source3: AnyObservableValue<Value3>, source4: AnyObservableValue<Value4>, collation: @escaping (Value1, Value2, Value3, Value4)->OutputType, setValue: ((OutputType)->Void)? = nil) {
        self.init(source1: source1, source2: source2, source3: source3, source4: source4, source5: emptyValuePublisher, source6: emptyValuePublisher, collation: { value1, value2, value3, value4, _, _ in
            return collation(value1, value2, value3, value4)
        }, setValue: setValue)
    }
}

extension ObservablePropertyCollator where Value4 == EmptyValue, Value5 == EmptyValue, Value6 == EmptyValue {
    public convenience init(source1: AnyObservableValue<Value1>, source2: AnyObservableValue<Value2>, source3: AnyObservableValue<Value3>, collation: @escaping (Value1, Value2, Value3)->OutputType, setValue: ((OutputType)->Void)? = nil) {
        self.init(source1: source1, source2: source2, source3: source3, source4: emptyValuePublisher, source5: emptyValuePublisher, source6: emptyValuePublisher, collation: { value1, value2, value3, _, _, _ in
            return collation(value1, value2, value3)
        }, setValue: setValue)
    }
}

extension ObservablePropertyCollator where Value3 == EmptyValue, Value4 == EmptyValue, Value5 == EmptyValue, Value6 == EmptyValue {
    public convenience init(source1: AnyObservableValue<Value1>, source2: AnyObservableValue<Value2>, collation: @escaping (Value1, Value2)->OutputType, setValue: ((OutputType)->Void)? = nil) {
        self.init(source1: source1, source2: source2, source3: emptyValuePublisher, source4: emptyValuePublisher, source5: emptyValuePublisher, source6: emptyValuePublisher, collation: { value1, value2, _, _, _, _ in
            return collation(value1, value2)
        }, setValue: setValue)
    }
}

extension ObservablePropertyCollator where Value2 == EmptyValue, Value3 == EmptyValue, Value4 == EmptyValue, Value5 == EmptyValue, Value6 == EmptyValue {
    convenience init(source: AnyObservableValue<Value1>, getTransform: @escaping (Value1)->OutputType, setTransform: @escaping ((OutputType)->Value1)) where Value1: Equatable {
        self.init(source1: source, source2: emptyValuePublisher, source3: emptyValuePublisher, source4: emptyValuePublisher, source5: emptyValuePublisher, source6: emptyValuePublisher, collation: { value1, _, _, _, _, _ in
            return getTransform(value1)
        }, setValue: { newValue in
            // We already capture strong source references, so it's ok to capture source again here.
            source.update(setTransform(newValue))
        })
    }
}
