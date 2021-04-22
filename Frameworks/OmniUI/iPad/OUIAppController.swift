// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation

extension OUIAppController {
    
    // Here "eligible" means connected, and of the type specified by the closure argument
    public func performOnEligibleSceneDelegates<T>(_ block: (T) -> Void) {
        let allSceneCoordinatorsOfType = allConnectedScenes.compactMap({ $0.delegate as? T })
        allSceneCoordinatorsOfType.forEach({ block($0) })
    }
}
