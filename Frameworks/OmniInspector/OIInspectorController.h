// Copyright 2002-2008, 2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

#import <OmniInspector/OIInspectorWindow.h>
#import <OmniInspector/OIInspector.h> // for OIInspectorInterfaceType

@class NSArray;
@class NSWindow, NSView, NSMenuItem;
@class OIInspectorHeaderView, OIInspectorResizer, OIInspectorGroup, OIInspectorHeaderBackground, OIInspectorRegistry;

#import <Foundation/NSGeometry.h> // for NSSize, NSPoint

#define OIInspectorStartingHeaderButtonWidth (256.0f)
#define OIInspectorStartingHeaderButtonHeight (16.0f)
#define OIInspectorSpaceBetweenButtons (0.0f)

#define OIInspectorColumnSpacing (1.0f)

extern NSString * const OIInspectorControllerDidChangeExpandednessNotification;

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

- (id)initWithInspector:(OIInspector *)anInspector;

@property (nonatomic, readonly) OIInspectorInterfaceType interfaceType;
@property (nonatomic, unsafe_unretained) OIInspectorRegistry *nonretained_inspectorRegistry;

- (void)setGroup:(OIInspectorGroup *)aGroup;
- (OIInspector *)inspector;
/// This is the window directly managed by the controller for floating inspectors; it is not necessarily the same as the containerView's window. Notably, for embedded inspectors, -window will return nil, and calling -window on the -containerView will return the window in which the inspector view is embedded.
- (NSWindow *)window;
/**
 An inspector controller's container view depends on its interface type. For floating inspectors, this is the same as its window's contentView; for embedded inspectors, it is a custom view.
 
 For embedded inspectors, you should access this view and install it in your app's view hierarchy in the appropriate place. You may inspect the view hierarchy of an inspector starting at this view, regardless of interface type; however, you should never attempt to modify this view's subviews.
 */
- (NSView *)containerView;
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

NSComparisonResult sortByDefaultDisplayOrderInGroup(OIInspectorController *a, OIInspectorController *b, void *context) OB_HIDDEN;

