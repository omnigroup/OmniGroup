// Copyright 2002-2007, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSControl.h>

@protocol OIInspectorHeaderViewDelegateProtocol;

@interface OIInspectorHeaderView : NSView
{
    NSString *title;
    NSImage *image;
    NSString *keyEquivalent;
    NSObject <OIInspectorHeaderViewDelegateProtocol> *delegate;
    BOOL isExpanded, isClicking, isDragging, clickingClose, overClose;
}

- (void)setTitle:(NSString *)aTitle;
- (void)setImage:(NSImage *)anImage;
- (void)setKeyEquivalent:(NSString *)anEquivalent;
- (void)setExpanded:(BOOL)newState;
- (void)setDelegate:(NSObject <OIInspectorHeaderViewDelegateProtocol> *)aDelegate;

- (void)drawBackgroundImageForBounds:(NSRect)backgroundBounds inRect:(NSRect)dirtyRect;

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

- (void)headerViewDidToggleExpandedness:(OIInspectorHeaderView *)view;

@end
