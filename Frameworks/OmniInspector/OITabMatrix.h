// Copyright 2005-2007 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniInspector/OITabMatrix.h 91417 2007-09-18 03:38:28Z andrew $

#import <AppKit/NSMatrix.h>

@interface OITabMatrix : NSMatrix 
{
    NSArray *oldSelection;
    
    enum OITabMatrixHighlightStyle {
        OITabMatrixCellsHighlightStyle,
        OITabMatrixDepressionHighlightStyle
    } highlightStyle;
}

- (void)setTabMatrixHighlightStyle:(enum OITabMatrixHighlightStyle)highlightStyle;
- (enum OITabMatrixHighlightStyle)tabMatrixHighlightStyle;

- (NSArray *)pinnedCells;

@end
