// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUISingleViewInspectorPane.h>

#import <OmniBase/OmniBase.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/UITableView-OUIExtensions.h>

#import "OUIInspectorBackgroundView.h"

RCS_ID("$Id$");

@implementation OUISingleViewInspectorPane

#pragma mark UIViewController

static void _setup(OUISingleViewInspectorPane *self)
{
    UIView *view = self.view;
    
    if (view) {
        // For single view inspectors, the nib needs to be set up with this as the main view, OR it needs to be some other opaque view (like a table view that covers the whole area).
        OBASSERT([view isKindOfClass:[OUIInspectorBackgroundView class]] || view.opaque);
        
        // Don't allow vertical resizing
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleBottomMargin;
    }
}

- (void)setView:(UIView *)view;
{
    [super setView:view];

    if (view && ![self nibName]) {
        // We often get loaded as part of a larger xib. Do our setup here instead of in -viewDidLoad (which won't get called since we don't load a xib!)        
        _setup(self);
    } 
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    if ([self nibName])
        _setup(self);
}

- (void)configureTableViewBackground:(UITableView *)tableView;
{
    // Here we expect the table view to be our view controller's view, so we give it the gradient background.
    OUIInspectorBackgroundView *backgroundView = [[OUIInspectorBackgroundView alloc] init];
    tableView.backgroundView = backgroundView;
}

@end
