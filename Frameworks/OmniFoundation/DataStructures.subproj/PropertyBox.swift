// Copyright 2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import Combine

@available(OSX 10.15, *)
public class PropertyBox<ValueType> : ObservableObject {

    public let objectWillChange = ObservableObjectPublisher()

    // Since this is sometimes used to lift a property out of a parent object to make it individually observable, the owner can no longer use willSet/didSet on the property itself.
    private let willSet: ((PropertyBox, ValueType) -> Void)?
    private let didSet: ((PropertyBox, ValueType) -> Void)?

    @Published public var value: ValueType {
        willSet {
            objectWillChange.loggingSend()
            willSet?(self, newValue)
        }
        didSet {
            didSet?(self, oldValue)
        }
    }

    public init(value: ValueType, willSet: ((PropertyBox, ValueType) -> Void)? = nil, didSet: ((PropertyBox, ValueType) -> Void)? = nil) {
        self.value = value
        self.willSet = willSet
        self.didSet = didSet
    }

    @discardableResult
    public func update(_ newValue: ValueType) -> Bool where ValueType : Equatable {
        if value != newValue {
            value = newValue
            return true
        }
        return false
    }
}
