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
public class ObservablePropertyCollator<Value1, Value2, Value3, Value4, OutputType: Equatable>: AnyObservableValue<OutputType> {
        
    private var cancellableSet: Set<AnyCancellable> = []
    private var strongSourceReferences: [Any]

    public init(source1: AnyObservableValue<Value1>, source2: AnyObservableValue<Value2>, source3: AnyObservableValue<Value3>, source4: AnyObservableValue<Value4>, collation: @escaping (Value1, Value2, Value3, Value4)->OutputType) {
        strongSourceReferences = [source1, source2, source3, source4]
        
        super.init(initialValue: collation(source1.value, source2.value, source3.value, source4.value))
        
        source1.valuePublisher.combineLatest(source2.valuePublisher, source3.valuePublisher, source4.valuePublisher, { v1, v2, v3, v4 in
            return collation(v1, v2, v3, v4)
        }).sink(receiveValue: {[weak self] newValue in
            guard let self = self else { return }
            self.update(newValue)
        }).store(in: &cancellableSet)
    }
}

private let emptyValuePublisher = ConstantObservableValue<EmptyValue>(value: EmptyValue())

extension ObservablePropertyCollator where Value4 == EmptyValue {
    public convenience init(source1: AnyObservableValue<Value1>, source2: AnyObservableValue<Value2>, source3: AnyObservableValue<Value3>, collation: @escaping (Value1, Value2, Value3)->OutputType) {
        self.init(source1: source1, source2: source2, source3: source3, source4: emptyValuePublisher, collation: { value1, value2, value3, _ in
            return collation(value1, value2, value3)
        })
    }
}

extension ObservablePropertyCollator where Value3 == EmptyValue, Value4 == EmptyValue {
    public convenience init(source1: AnyObservableValue<Value1>, source2: AnyObservableValue<Value2>, collation: @escaping (Value1, Value2)->OutputType) {
        self.init(source1: source1, source2: source2, source3: emptyValuePublisher, source4: emptyValuePublisher, collation: { value1, value2, _, _ in
            return collation(value1, value2)
        })
    }
}
