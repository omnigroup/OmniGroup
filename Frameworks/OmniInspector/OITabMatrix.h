// Copyright 2005-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSMatrix.h>

typedef NS_ENUM(NSUInteger, OITabMatrixHighlightStyle) {
    OITabMatrixCellsHighlightStyle,
    OITabMatrixYosemiteHighlightStyle,
    OITabMatrixNoHighlightStyle
};

@interface OITabMatrix : NSMatrix

- (void)setTabMatrixHighlightStyle:(enum OITabMatrixHighlightStyle)highlightStyle;
- (enum OITabMatrixHighlightStyle)tabMatrixHighlightStyle;

@property (nonatomic) BOOL allowPinning;

- (NSArray *)pinnedCells;

@end
