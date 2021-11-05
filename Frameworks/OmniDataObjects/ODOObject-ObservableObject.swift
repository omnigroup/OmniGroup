// Copyright 2020-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Combine

@available(OSX 10.15, *)
extension ODOObject {

    public var objectDidChange: ObservableObjectPublisher {
        if let existing = objectDidChangeStorage {
            return existing as! ObservableObjectPublisher
        }
        let updated = ObservableObjectPublisher()
        objectDidChangeStorage = updated
        return updated
    }

    @objc final public func sendDidChange() {
        guard let existing = objectDidChangeStorage else {
            return // No one is listening
        }
        (existing as! ObservableObjectPublisher).loggingSend()
    }

}
