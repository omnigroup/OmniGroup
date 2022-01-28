// Copyright 2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import Combine

extension AnyObservableValue {
    // ObservableValueTransform is a one-way, readonly mapping.
    public func mapValue<T: Equatable>(_ transform: @escaping (Value)->T) -> ObservableValueTransform<T> {
        return ObservableValueTransform(source: self, transform: transform)
    }
    
    // ObservablePropertyCollator has support for setting the value of its source object, so we can use it to create a two-way mapping where setting the value of the object returned by this method updates the value of the object this method is called on.
    public func mapValue<T: Equatable>(_ getTransform: @escaping (Value)->T, setTransform: @escaping (T)->Value) -> AnyObservableValue<T> where Value: Equatable {
        return ObservablePropertyCollator(source: self, getTransform: getTransform, setTransform: setTransform)
    }
}

@available(OSX 10.15, *)
public final class ObservableValueTransform<Output> : AnyObservableValue<Output> {
    
    override var wantsObjectWillChangeSendOnValueSet: Bool { return false }
    
    private var cancellableSet: Set<AnyCancellable> = []
    private var strongSourceReference: Any
    
    fileprivate init<Value>(source: AnyObservableValue<Value>, transform: @escaping (Value)->Output) where Output: Equatable {
        strongSourceReference = source
        
        super.init(objectWillChange: source.objectWillChange, initialValue: transform(source.value))
        
        source.valuePublisher.dropFirst().sink(receiveValue: { [weak self] newSourceValue in
            guard let self = self else { return }
            let newValue = transform(newSourceValue)
            self.update(newValue)
        }).store(in: &cancellableSet)
    }
}
