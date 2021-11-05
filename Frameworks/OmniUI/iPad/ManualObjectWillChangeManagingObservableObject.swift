// Copyright 2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Combine
import SwiftUI

/*
 Normally `@Published` properties broadcast change notifications automatically. But, if you declare a `objectWillChange` publisher locally in order to avoid the cost incurred by the global object-to-publisher table, the `@Published` property wrapper will not use your local `objectWillChange` publisher and no updates will happen.
 */

public protocol ManualObjectWillChangeManagingObservableObject: ObservableObject where Self.ObjectWillChangePublisher == ObservableObjectPublisher {
    var cancellableSet: Set<AnyCancellable> { get set }
}

// Necessary to type erase the generic Combine.Published.Value attribute out so we can as? cast in the linkPublishedPropertiesToObjectWillChange
public protocol PublishedProjectedValueLinking {
    func linkProjectedValue<T: ManualObjectWillChangeManagingObservableObject>(to observableObject: T)
}

extension Combine.Published.Publisher: PublishedProjectedValueLinking {
    public func linkProjectedValue<T: ManualObjectWillChangeManagingObservableObject>(to observableObject: T) {
        sink(receiveValue: { [weak observableObject] _ in
            dispatchPrecondition(condition: .onQueue(.main))
            observableObject?.objectWillChange.send()
        }).store(in: &observableObject.cancellableSet)
    }
}

///If `Mirror` ever gets the capability to modify the object it's reflecting, the code below will search a class for its `@Published` properties and automatically send out `objectWillChange` when any of those properties are set, instead of the burden of setting up that linking laying on each class' implementation. It doesn't compile right now because `Combine.Published.projectedValue` has a mutating getter, because that publisher is lazily initialized. 
/*
extension Combine.Published: PublishedProjectedValueLinking {
    public mutating func linkProjectedValue<T: ManualObjectWillChangeManagingObservableObject>(to observableObject: T) {
        projectedValue.linkProjectedValue(to: observableObject)
    }
}

extension ManualObjectWillChangeManagingObservableObject {
    func linkPublishedPropertiesToObjectWillChange() {
        var mirror: Mirror? = Mirror(reflecting: self)
        while let loopMirror = mirror {
            for (_, value) in loopMirror.children {
                /// Looking for properties that are `Combine.Published`, aka the `_editMode` property related to an `@Published var editMode`
                if value is PublishedProjectedValueLinking {
                    /// Call linkProjectedValue on the relevant property on `self`
                }
            }
            mirror = loopMirror.superclassMirror
        }
    }
}
 
 */
