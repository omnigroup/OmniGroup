// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

@class NSArray, NSString;
@class OUIInspector, OUIInspectorPane, OUIStackedSlicesInspectorPane;

@protocol OUIInspectorDelegate <NSObject>

#if 0
// This is the architecture that we would like to move forward with when we have time to worry about iPhone. On iPad, we always present the inspector in a Popover, but on iPhone we'd like to present it modally. To present things modally, we have to have a view controller to present them from. We’re getting rid of -[OUIAppController topViewController] because it becomes ambiguous in a view controller containment world. We’ll need something like the following to figure out which view controller should present the inspector.
@required
- (UIViewController *)inspectorViewControllerToPresentFrom:(OUIInspector *)inpspector;
#endif

@optional

// If this is not implemented or returns nil, and the inspector pane doesn't already have a title, an assertion will fire it will be given a title of "Inspector".
// Thus, you either need to implement this or the manually give titles to the panes.
- (NSString *)inspector:(OUIInspector *)inspector titleForPane:(OUIInspectorPane *)pane;

// If this is not implemented or returns nil, and the stacked inspector pane doesn't already have slices, an assertion will fire and the inspector dismissed.
// Thus, you either need to implement this or the manually give slices to the stacked slice panes. If you make slices this way, you must return all the possible slices and have the slices themselves decide whether they are appropriate for the inspected object set.
- (NSArray *)inspector:(OUIInspector *)inspector makeAvailableSlicesForStackedSlicesPane:(OUIStackedSlicesInspectorPane *)pane;

- (void)inspectorWillDismiss:(OUIInspector *)inspector;
// Delegates should normally implement this method to restore the first responder.
- (void)inspectorDidDismiss:(OUIInspector *)inspector;

// gives the delegate an opportunity to configure the inspectors on reopen. Return NO to let OUIInspector pop to root view controller.
- (BOOL)inspectorShouldMaintainStateWhileReopening:(OUIInspector *)inspector;

@end
