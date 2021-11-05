// Copyright 2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

@available(OSX 10.15, *)
extension ODOObject : ObservableObject {

    public var objectWillChange: ObjectWillChangePublisher {
        if let existing = objectWillChangeStorage {
            return existing as! ObjectWillChangePublisher
        }
        let updated = ObjectWillChangePublisher()
        objectWillChangeStorage = updated
        return updated
    }

    @objc final public func sendWillChange() {
        guard let existing = objectWillChangeStorage else {
            return // No one is listening
        }
        (existing as! ObjectWillChangePublisher).send()
    }
}
