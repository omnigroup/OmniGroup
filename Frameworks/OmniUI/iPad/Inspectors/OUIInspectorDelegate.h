// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
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

@required
- (NSArray *)objectsToInspectForInspector:(OUIInspector *)inspector;

@optional

// If this is not implemented or returns nil, and the inspector pane doesn't already have a title, an assertion will fire it will be given a title of "Inspector".
// Thus, you either need to implement this or the manually give titles to the panes.
- (NSString *)inspector:(OUIInspector *)inspector titleForPane:(OUIInspectorPane *)pane;

// If this is not implemented or returns nil, and the stacked inspector pane doesn't already have slices, an assertion will fire and the inspector dismissed.
// Thus, you either need to implement this or the manually give slices to the stacked slice panes. If you make slices this way, you must return all the possible slices and have the slices themselves decide whether they are appropriate for the inspected object set.
- (NSArray *)inspector:(OUIInspector *)inspector makeAvailableSlicesForStackedSlicesPane:(OUIStackedSlicesInspectorPane *)pane;

// gives the delegate an opportunity to configure the inspectors on reopen. Return NO to let OUIInspector pop to root view controller.
- (BOOL)inspectorShouldMaintainStateWhileReopening:(OUIInspector *)inspector;

@end
