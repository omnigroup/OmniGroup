// Copyright 2008-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniUI/OUIAppearance.h>

@interface OmniUIDocumentAppearance : OUIAppearance
@property (readonly) CGFloat documentPickerLocationRowHeight;
@property (readonly) CGFloat documentPickerAddAccountRowHeight;

@property (readonly) CGFloat documentPickerHomeScreenAnimationDuration;
@property (readonly) CGFloat documentPickerHomeScreenAnimationBounceFactor;
@property (readonly) NSString *documentPickerHomeScreenItemCountSeparator;

@property (readonly) UIColor *documentPickerTintColorAgainstBackground;

@property (readonly) CGFloat documentOpeningAnimationDuration;
@property (readonly) CGFloat documentClosingAnimationDuration;

@end
