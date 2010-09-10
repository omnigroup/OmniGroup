// Copyright 2002-2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

#import <OmniInspector/OIInspectorWindow.h>

@class NSArray;
@class NSWindow, NSView, NSMenuItem;
@class OIInspector, OIInspectorWindow, OIInspectorHeaderView, OIInspectorResizer, OIInspectorGroup, OIInspectorHeaderBackground;

#import <Foundation/NSGeometry.h> // for NSSize, NSPoint

#define OIInspectorStartingHeaderButtonWidth (256.0f)
#define OIInspectorStartingHeaderButtonHeight (16.0f)
#define OIInspectorSpaceBetweenButtons (0.0f)

#define OIInspectorColumnSpacing (1.0f)

@interface OIInspectorController : NSObject <OIInspectorWindowDelegate>
{
    NSArray *currentlyInspectedObjects;
    OIInspector *inspector;
    OIInspectorGroup *group;
    OIInspectorWindow *window;
    OIInspectorHeaderView *headingButton;
    OIInspectorHeaderBackground *headingBackground;
    OIInspectorResizer *resizerView;
    NSView *controlsView;
    BOOL loadedInspectorView, isExpanded, isSettingExpansion, isBottommostInGroup, collapseOnTakeNewPosition, heightSizable, forceResizeWidget, needsToggleBeforeDisplay;
    CGFloat _minimumHeight;
    NSPoint newPosition;
}

// API

- initWithInspector:(OIInspector *)anInspector;

- (void)setGroup:(OIInspectorGroup *)aGroup;
- (OIInspector *)inspector;
- (NSWindow *)window;
- (OIInspectorHeaderView *)headingButton;

- (BOOL)isExpanded;
- (void)setExpanded:(BOOL)newState withNewTopLeftPoint:(NSPoint)topLeftPoint;
- (NSString *)identifier;
- (CGFloat)headingHeight;
- (CGFloat)desiredHeightWhenExpanded;

- (void)prepareWindowForDisplay;
- (void)displayWindow;
- (void)toggleDisplay;
- (void)showInspector;
- (void)updateTitle;
- (BOOL)isVisible;

- (void)setBottommostInGroup:(BOOL)isBottom;

- (void)toggleExpandednessWithNewTopLeftPoint:(NSPoint)topLeftPoint animate:(BOOL)animate;
- (void)updateExpandedness:(BOOL)allowAnimation; // call when the inspector sets its size internally by itself

- (void)setNewPosition:(NSPoint)aPosition;
- (void)setCollapseOnTakeNewPosition:(BOOL)yn;
- (CGFloat)heightAfterTakeNewPosition;
- (void)takeNewPositionWithWidth:(CGFloat)aWidth;

- (void)loadInterface;
- (void)updateInspector;
- (void)inspectNothing;

// Inspectors should call this on their controller if they programmatically change their size, so that the controller can notify the root inspector. This allows the root inspector to react to the change and in turn notify any child inspectors. This is necessary because there is often a hierarchy of inspectors (tabbed inspector containing multiple individual inspectors, etc), but individual inspectors are not aware of their parent inspectors.
- (void)inspectorDidResize:(OIInspector *)resizedInspector;

@end

__private_extern__ NSComparisonResult sortByDefaultDisplayOrderInGroup(OIInspectorController *a, OIInspectorController *b, void *context);

