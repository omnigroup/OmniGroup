//
//  OUITemplateResourceBookmarks.swift
//  OmniUIDocument-iOS
//
//  Created by Rachael Worthington on 2/7/20.
//  Copyright © 2020 The Omni Group. All rights reserved.
//

import Foundation
import OmniFoundation

@objc(OUITemplateResourceBookmarks) open class TemplateResourceBookmarks : ResourceBookmarks {

    private var updateLocationHandler: () -> ()

    public init(preferenceKey: String, resourceTypes: [String : ResourceTypePredicate], updateHandler: @escaping () -> ()) {
        updateLocationHandler = updateHandler
        super.init(preferenceKey: preferenceKey, resourceTypes: resourceTypes)
    }
    // MARK:- ResourceLocationDelegate
    override public func resourceLocationDidUpdateResourceURLs(_ location: ResourceLocation) {
        super.resourceLocationDidUpdateResourceURLs(location)
        updateLocationHandler()
    }
    override public func resourceLocationDidMove(_ location: ResourceLocation) {
        super.resourceLocationDidMove(location)
        updateLocationHandler()
    }

}
