// Copyright 2002-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSControl.h>

#define OIInspectorStartingHeaderButtonWidth (256.0f)
#define OIInspectorStartingHeaderButtonHeight (16.0f)

@protocol OIInspectorHeaderViewDelegateProtocol;

@interface OIInspectorHeaderView : NSView

@property(nonatomic,copy) NSString *title;
@property(nonatomic,strong) NSImage *image;
@property(nonatomic,copy) NSString *keyEquivalent;
@property(nonatomic) BOOL expanded;

@property(nonatomic,weak) NSObject <OIInspectorHeaderViewDelegateProtocol> *delegate;

- (void)drawBackgroundImageForBounds:(NSRect)backgroundBounds inRect:(NSRect)dirtyRect;

@property (nonatomic) CGFloat titleContentHeight;
@property (nonatomic,readonly) CGFloat heightNeededWhenExpanded;
@property (nonatomic,strong) NSView *accessoryView;

@end

@class NSScreen;

@protocol OIInspectorHeaderViewDelegateProtocol

- (BOOL)headerViewShouldDisplayCloseButton:(OIInspectorHeaderView *)view;
- (void)headerViewDidClose:(OIInspectorHeaderView *)view;

- (BOOL)headerViewShouldAllowDragging:(OIInspectorHeaderView *)view;
- (CGFloat)headerViewDraggingHeight:(OIInspectorHeaderView *)view;
- (void)headerViewDidBeginDragging:(OIInspectorHeaderView *)view;
- (NSRect)headerView:(OIInspectorHeaderView *)view willDragWindowToFrame:(NSRect)aFrame onScreen:(NSScreen *)aScreen;
- (void)headerViewDidEndDragging:(OIInspectorHeaderView *)view toFrame:(NSRect)aFrame;

- (BOOL)headerViewShouldDisplayExpandButton:(OIInspectorHeaderView *)view;
- (void)headerViewDidToggleExpandedness:(OIInspectorHeaderView *)view;

@end
