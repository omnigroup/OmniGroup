// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UICollectionViewLayout.h>

NS_ASSUME_NONNULL_BEGIN

// assumptions:
// 1. all the icons are the same size.
// 2. exterior spacing to the left and right of the outside icons should exist. Lets space these icons evenly in the space we have, like so: |<one>|--|<two>|--|<three>. Padding to the top, left, and right comes from the safe area insets.
// 3. incomplete rows should have icons aligned in columns still, with trailing space at the end.

@interface OUIExportOptionsCollectionViewLayout : UICollectionViewLayout

@property(nonatomic) CGFloat minimumInterItemSpacing;

@end

NS_ASSUME_NONNULL_END
