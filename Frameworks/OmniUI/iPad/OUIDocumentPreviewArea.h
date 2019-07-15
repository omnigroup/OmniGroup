// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


// Not used in OmniUI, but lifted up so that OUIDocumentPreview and OAAppearance (OmniUIInternal) can use it.
typedef NS_ENUM(NSUInteger, OUIDocumentPreviewArea) {
    OUIDocumentPreviewAreaLarge, // Fill item, when in a scope
    OUIDocumentPreviewAreaMedium, // Full item, currently only used in the OmniOutliner theme picker.
    OUIDocumentPreviewAreaSmall, // Inner folder item, when in a scope
};
