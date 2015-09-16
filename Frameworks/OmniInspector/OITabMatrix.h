// Copyright 2005-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSMatrix.h>

typedef NS_ENUM(NSUInteger, OITabMatrixHighlightStyle) {
    OITabMatrixCellsHighlightStyle,
    OITabMatrixYosemiteHighlightStyle
};

@interface OITabMatrix : NSMatrix

- (void)setTabMatrixHighlightStyle:(enum OITabMatrixHighlightStyle)highlightStyle;
- (enum OITabMatrixHighlightStyle)tabMatrixHighlightStyle;

- (NSArray *)pinnedCells;

@end
