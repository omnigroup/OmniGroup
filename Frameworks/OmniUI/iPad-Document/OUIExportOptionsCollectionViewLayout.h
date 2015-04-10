// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UICollectionViewLayout.h>

// assumptions:
// 1. all the icons are the same size.
// 2. exterior spacing to the left and right of the outside icons should exist. Lets space these icons evenly in the space we have, like so: |--|<one>|--|<two>|--|<three>|--|. Padding should result in extra space on the sides, and icons should not be snugged up to the edges of the collection view.
// 3. incomplete rows should have icons aligned in columns still, with trailing space at the end.

@interface OUIExportOptionsCollectionViewLayout : UICollectionViewLayout

@property(nonatomic) CGFloat minimumInterItemSpacing;

@end
