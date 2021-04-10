// Copyright 2008-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAAppearance.h>

@interface OmniUIDocumentAppearance : OAAppearance

@property (readonly) CGFloat serverAccountRowHeight;
@property (readonly) CGFloat serverAccountAddRowHeight;

@property (readonly) UIColor *documentPickerTintColorAgainstBackground;

@property (readonly) CGFloat documentOpeningAnimationDuration;
@property (readonly) CGFloat documentClosingAnimationDuration;

@property(nonatomic,readonly) NSTimeInterval documentSyncMinimumVisiblityFromActivityStartTimeInterval;
@property(nonatomic,readonly) NSTimeInterval documentSyncMinimumVisiblityFromLastActivityTimeInterval;

@end
