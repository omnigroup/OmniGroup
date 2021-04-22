// Copyright 2017-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

import UIKit

open class DisclosableMultiSegmentInspectorPane : OUIMultiSegmentStackedSlicesInspectorPane {
    @objc /**REVIEW**/ public var allDisclosableSliceGroups = [DisclosableSliceGroup]()
    @objc /**REVIEW**/ public var excludedDisclosableSliceGroups = [DisclosableSliceGroup]()

    /// Backing preference for persistent disclosed slices. Callers should not access this directly; instead, use one of the conveniences later.
    private static var disclosedSlicesPreference = OFPreference(forKey: "OUIInspectorMultiSegmentDisclosedSlicesPreference", defaultValue: [:])

    @objc /**REVIEW**/ public func isGroupDisclosed(_ group: DisclosableSliceGroup) -> Bool {
        guard let dict = DisclosableMultiSegmentInspectorPane.disclosedSlicesPreference.dictionaryValue as? [String:Bool] else {
            return false
        }

        return dict[group.identifier] ?? false
    }

    fileprivate func setGroup(_ group: DisclosableSliceGroup, disclosed: Bool) {
        var dict: [String:Bool]
        if let stored = DisclosableMultiSegmentInspectorPane.disclosedSlicesPreference.dictionaryValue as? [String:Bool] {
            dict = stored
        }
        else {
            dict = DisclosableMultiSegmentInspectorPane.disclosedSlicesPreference.defaultObjectValue as! [String:Bool]
        }
        dict[group.identifier] = disclosed
        DisclosableMultiSegmentInspectorPane.disclosedSlicesPreference.dictionaryValue = dict
    }

    override open func appropriateSlicesForInspectedObjects() -> [OUIInspectorSlice]? {
        let slices = super.appropriateSlicesForInspectedObjects()

        let excludedSlices = excludedDisclosableSliceGroups.flatMap { (disclosableSliceGroup) -> [OUIInspectorSlice] in
            return disclosableSliceGroup.disclosableSlices
        }

        let filteredSlices = slices?.filter({ (slice) -> Bool in
            let isExcluded = excludedSlices.contains(slice)
            let shouldStayIn = !isExcluded
            return shouldStayIn
        })

        return filteredSlices
    }
}

extension DisclosableMultiSegmentInspectorPane : DisclosableSliceGroupDelegate {
    open func didTapSliceGroupButton(_ disclosableSliceGroup: DisclosableSliceGroup) {
        if let index = excludedDisclosableSliceGroups.firstIndex(of: disclosableSliceGroup) {
            excludedDisclosableSliceGroups.remove(at: index)
            setGroup(disclosableSliceGroup, disclosed: true)
        }
        else {
            excludedDisclosableSliceGroups.append(disclosableSliceGroup)
            setGroup(disclosableSliceGroup, disclosed: false)
        }

        updateSlices()
        updateInterface(fromInspectedObjects: .default)
    }

    open func sliceGroupIsUndisclosed(_ disclosableSliceGroup: DisclosableSliceGroup) -> Bool {
        return excludedDisclosableSliceGroups.contains(disclosableSliceGroup)
    }
}
