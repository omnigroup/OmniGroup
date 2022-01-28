// Copyright 2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import Combine

@available(OSX 10.15, *)
public class PropertyBox<ValueType> : AnyObservableValue<ValueType> {

    // Since this is sometimes used to lift a property out of a parent object to make it individually observable, the owner can no longer use willSet/didSet on the property itself.
    private let willSet: ((PropertyBox, ValueType) -> Void)?
    private let didSet: ((PropertyBox, ValueType) -> Void)?
    private let _acceptsReentrantValueSets: Bool

    override var acceptsReentrantValueSets: Bool { return _acceptsReentrantValueSets }
    
    override func willSetValue(newValue: ValueType) {
        willSet?(self, newValue)
    }
    
    override func didSetValue(value: ValueType) {
        didSet?(self, value)
    }
    
    public required init(value: ValueType, acceptsReentrantValueSets: Bool = false, willSet: ((PropertyBox, ValueType) -> Void)? = nil, didSet: ((PropertyBox, ValueType) -> Void)? = nil) {
        self.willSet = willSet
        self.didSet = didSet
        self._acceptsReentrantValueSets = acceptsReentrantValueSets
        
        super.init(initialValue: value)        
    }
}
