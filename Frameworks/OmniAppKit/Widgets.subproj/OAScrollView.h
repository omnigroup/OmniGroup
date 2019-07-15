// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSScrollView.h>
#import <AppKit/NSCell.h> // For NSControlSize

@class NSButton, NSMenuItem, NSPopUpButton, NSTextField;

typedef enum { YES_SCROLL, NO_SCROLL, VERTICAL_SCROLL, AUTO_SCROLL, MANUAL_SCROLL } ScrollingBehavior;

#import <Foundation/NSString.h> // For unichar

@interface OAScrollView : NSScrollView
{
    NSView *horizontalWidgetsBox;
    NSView *verticalWidget;
    NSPopUpButton *scalePopUpButton;
    NSButton *pageUpButton;
    NSButton *pageDownButton;
    NSTextField *pagePromptTextField;
    NSTextField *pageNumberTextField;
    NSTextField *pagesCountTextField;
    CGFloat zoomFactor;
    ScrollingBehavior scrollBehavior;
    id nonretained_delegate;
    struct {
        unsigned int tiling:1;
        unsigned int smoothScrollDisabled:1;
        unsigned int delegateIsPageSelectable:1;
    } flags;
}

- (NSSize)contentSizeForFrameSize:(NSSize)frameSize hasHorizontalScroller:(BOOL)hasHorizontalScroller hasVerticalScroller:(BOOL)hasVerticalScroller;
- (NSSize)contentSizeForFrameSize:(NSSize)fSize;
- (NSSize)contentSizeForHorizontalScroller:(BOOL)hasHorizontalScroller verticalScroller:(BOOL)hasVerticalScroller;

- (void)zoomToScale:(CGFloat)newZoomFactor;
- (void)zoomFromSender:(NSMenuItem *)sender;
- (CGFloat)zoomFactor;
- (void)setDelegate:(id)newNonretainedDelegate;
- (ScrollingBehavior)scrollBehavior;
- (void)setScrollBehavior:(ScrollingBehavior)behavior;
- (void)showingPageNumber:(int)pageNumber of:(unsigned int)pagesCount;
- (void)gotoPage:(id)sender;
- (BOOL)processKeyDownCharacter:(unichar)character modifierFlags:(NSUInteger)modifierFlags;

- (void)setSmoothScrollEnabled:(BOOL)smoothScrollEnabled;
- (BOOL)smoothScrollEnabled;

- (void)setVerticalWidget:(NSView *)newVerticalWidget;
- (NSView *)verticalWidget;

- (void)setControlSize:(NSControlSize)newControlSize;
// Creating a scrollView and then calling setControlSize: on its scrollers will normally result in a void being created between the contentView and the scroller. (This isn't noticeable unless your documentView has a background other than white.) Use this method instead -- it'll size the scrollers and resize the content view to match.

@end

@interface NSView (OAScrollViewDocumentViewOptionalMethods)
- (void)scrollViewDidChangeScrollers;
@end
