// Copyright 2002-2016 Omni Development, Inc. All rights reserved.
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

@class NSWindow, NSView;
@class OIInspectorHeaderView, OIInspectorGroup, OIInspectorRegistry, OIInspectorWindow;

#import <Foundation/NSGeometry.h> // for NSSize, NSPoint

#define OIInspectorSpaceBetweenButtons (0.0f)

#define OIInspectorColumnSpacing (1.0f)

extern NSString * const OIInspectorControllerDidChangeExpandednessNotification;

@interface OIInspectorController : NSObject <OIInspectorWindowDelegate>

// API

- (id)initWithInspector:(OIInspector <OIConcreteInspector> *)anInspector inspectorRegistry:(OIInspectorRegistry *)inspectorRegistry;

@property (nonatomic, assign) OIInspectorInterfaceType interfaceType;
@property (nonatomic, readonly, weak) OIInspectorRegistry *inspectorRegistry;

@property(nonatomic,weak) OIInspectorGroup *group;

@property(nonatomic,readonly) OIInspector <OIConcreteInspector> *inspector;

@property(nonatomic,readonly) OIInspectorWindow *buildWindow; // Subclasses can make their own window

/// This is the window directly managed by the controller for floating inspectors; it is not necessarily the same as the containerView's window. Notably, for embedded inspectors, -window will return nil, and calling -window on the -containerView will return the window in which the inspector view is embedded.
@property(nonatomic,readonly) NSWindow *window;
/**
 An inspector controller's container view depends on its interface type. For floating inspectors, this is the same as its window's contentView; for embedded inspectors, it is a custom view.
 
 For embedded inspectors, you should access this view and install it in your app's view hierarchy in the appropriate place. You may inspect the view hierarchy of an inspector starting at this view, regardless of interface type; however, you should never attempt to modify this view's subviews.
 */
@property(nonatomic,readonly) NSView *containerView;
@property(nonatomic,readonly) OIInspectorHeaderView *headingButton;

@property(nonatomic,readonly) BOOL isExpanded;
@property(nonatomic,readonly) BOOL isSettingExpansion;
- (void)setExpanded:(BOOL)newState withNewTopLeftPoint:(NSPoint)topLeftPoint;

@property(nonatomic,readonly) NSString *inspectorIdentifier;

@property(nonatomic,readonly) CGFloat headingHeight;
@property(nonatomic,readonly) CGFloat desiredHeightWhenExpanded;

- (void)prepareWindowForDisplay;
- (void)displayWindow;
- (void)toggleDisplay;
- (void)showInspector;
- (void)updateTitle;
@property(nonatomic,readonly,getter=isVisible) BOOL visible;

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

#import <OmniBase/macros.h>

NSComparisonResult OISortByDefaultDisplayOrderInGroup(OIInspectorController *a, OIInspectorController *b) OB_HIDDEN;

