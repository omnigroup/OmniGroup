// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

typedef NS_ENUM(NSUInteger, OUIInspectorUpdateReason) {
    OUIInspectorUpdateReasonDefault,
    OUIInspectorUpdateReasonObjectsEdited, // Due to -[OUIInspector didEndChangingInspectedObjects]. Most commonly we want to check this to avoid reloading a table view when code following -didEndChangingInspectedObjects will fix the table view.
    OUIInspectorUpdateReasonNeedsReload // Used when changing to a non-nil set of inspected objects. This should perform a full reload of everything in your inspector. Expect calling updateInterfaceFromInspectedObjects: with this reason to be expensive.
};
