// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSView.h>
#import <AppKit/NSNibDeclarations.h>

@class NSImage, NSFont, NSPasteboard;
@class NSString;

#define MAXIMUM_INDICATOR_COUNT 2 // easy to increase, but all I need for now

@interface OAMultiColumnListView : NSView 
{
    IBOutlet id dataSource;
    IBOutlet id delegate;
    
    NSFont *font;

    NSSize indicatorSize;
    unsigned indicatorCount;
    NSImage *indicatorImages[MAXIMUM_INDICATOR_COUNT][2][3];
    BOOL indicatorSelectable[MAXIMUM_INDICATOR_COUNT];
    
    float itemHeight, headerHeight;
    unsigned columnCount, rowCount;
    unsigned itemCount;
    float widestItem;
    unsigned selectedItem;
    unsigned mouseItem, mouseIndicator;
    BOOL mouseDown;
}

- (void)setFont:(NSFont *)aFont;

- (void)removeIndicators;
- (void)addSelectableIndicatorOn:(NSImage *)on off:(NSImage *)off downOn:(NSImage *)downOn downOff:(NSImage *)downOff overOn:(NSImage *)overOn overOff:(NSImage *)overOff;
- (void)addDraggableIndicator:(NSImage *)image;

- (unsigned)selectedItemIndex;

- (void)reloadData;

@end

@interface NSObject (OAMultiColumnListViewDataSource)
- (unsigned)countOfItemsInListView:(OAMultiColumnListView *)listView;
- (NSString *)titleOfItemAtIndex:(unsigned)index inListView:(OAMultiColumnListView *)listView;
- (BOOL)indicatorState:(unsigned)indicator forItemAtIndex:(unsigned)index inListView:(OAMultiColumnListView *)listView;
- (BOOL)writeItemAtIndex:(unsigned)index toPasteboard:(NSPasteboard *)pboard inListView:(OAMultiColumnListView *)listView;
@end

@interface NSObject (OAMultiColumnListViewDelegate)
- (void)listView:(OAMultiColumnListView *)listView didToggleIndicator:(unsigned)indicator forItemAtIndex:(unsigned)index;
- (void)listViewDidChangeSelection:(OAMultiColumnListView *)listView;
@end
