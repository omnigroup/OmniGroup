// Copyright 2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

import Foundation
import OmniFoundation

@objc(OUIApplicationResourceBookmarks) open class ApplicationResourceBookmarks : ResourceBookmarks {

    private static var sharedBookmarks: ApplicationResourceBookmarks = ApplicationResourceBookmarks(preferenceKey: "linkedApplicationResourceBookmarks", resourceTypes: [:], updateHandler: nil)

    private var updateLocationHandlers: [() -> ()] = []

    @objc public class func shared() -> ApplicationResourceBookmarks {
        return sharedBookmarks
    }

    @objc private init(preferenceKey: String, resourceTypes: [String : ResourceTypePredicate], updateHandler: (() -> ())?) {
        if let updateHandler = updateHandler {
            updateLocationHandlers.append(updateHandler)
        }
        super.init(preferenceKey: preferenceKey, resourceTypes: resourceTypes)
    }

    @objc public func addUpdateHandler(_ handler: @escaping () -> ())
    {
        updateLocationHandlers.append(handler)
    }

    // MARK:- ResourceLocationDelegate
    override public func resourceLocationDidUpdateResourceURLs(_ location: ResourceLocation) {
        super.resourceLocationDidUpdateResourceURLs(location)
        for handler in updateLocationHandlers {
            handler()
        }
    }

    override public func resourceLocationDidMove(_ location: ResourceLocation) {
        super.resourceLocationDidMove(location)
        for handler in updateLocationHandlers {
            handler()
        }
    }
}
