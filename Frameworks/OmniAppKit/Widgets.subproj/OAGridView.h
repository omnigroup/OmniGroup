// Copyright 2000-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OAGridView.h 68913 2005-10-03 19:36:19Z kc $

#import <AppKit/NSView.h>

@class NSMutableArray;
@class NSColor;

@interface OAGridView : NSView
{
    float leftMargin;
    float rightMargin;
    float topMargin;
    float bottomMargin;
    float interColumnSpace;
    float interRowSpace;
    int rowCount;
    int columnCount;
    NSMutableArray *rows;
    NSColor *backgroundColor;
}

+ (void)initialize;

- initWithFrame:(NSRect)frameRect;
- (void)dealloc;

// Accessors
- (int)rowCount;
- (void)setRowCount:(int)newRowCount;

- (int)columnCount;
- (void)setColumnCount:(int)newColumnCount;

- (float)interColumnSpace;
- (void)setInterColumnSpace:(float)newInterColumnSpace;

- (float)interRowSpace;
- (void)setInterRowSpace:(float)newInterRowSpace;

- (float)leftMargin;
- (void)setLeftMargin:(float)newLeftMargin;

- (float)rightMargin;
- (void)setRightMargin:(float)newRightMargin;

- (float)topMargin;
- (void)setTopMargin:(float)newTopMargin;

- (float)bottomMargin;
- (void)setBottomMargin:(float)newBottomMargin;

- (NSView *)viewAtRow:(int)row column:(int)column;
- (void)setView:(NSView *)aView atRow:(int)row column:(int)column;
- (void)setView:(NSView *)aView relativeToView:(NSView *)referenceView atRow:(int)row column:(int)column;

- (void)removeAllViews;

- (NSColor *)backgroundColor;
- (void)setBackgroundColor:(NSColor *)newBackgroundColor;

// NSView methods
- (void)resizeSubviewsWithOldSize:(NSSize)oldFrameSize;
- (void)drawRect:(NSRect)rect;

- (void)tile;

@end
