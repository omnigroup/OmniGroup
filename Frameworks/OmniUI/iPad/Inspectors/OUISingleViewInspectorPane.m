// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUISingleViewInspectorPane.h>

#import <OmniBase/OmniBase.h>
#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIInspectorBackgroundView.h>
#import <OmniUI/UITableView-OUIExtensions.h>

RCS_ID("$Id$");

@implementation OUISingleViewInspectorPane

#pragma mark UIViewController

static void _setup(OUISingleViewInspectorPane *self)
{
    UIView *view = self.view;
    
    if (view) {
        // Keep our original size in the popover.
        self.contentSizeForViewInPopover = view.frame.size;
        
        // For single view inspectors, the nib needs to be set up with this as the main view, OR it needs to be some other opaque view (like a table view that covers the whole area).
        OBASSERT([view isKindOfClass:[OUIInspectorBackgroundView class]] || view.opaque);
        
        // Don't allow vertical resizing
        view.autoresizingMask = UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleBottomMargin;
    }
}

- (void)setView:(UIView *)view;
{
    [super setView:view];

    if (![self nibName]) {
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

- (BOOL)adjustSizeToExactlyFitTableView:(UITableView *)tableView;
{
    return [self adjustSizeToExactlyFitTableView:tableView maximumHeight:420];
}

- (BOOL)adjustSizeToExactlyFitTableView:(UITableView *)tableView maximumHeight:(CGFloat)maximumHeight;
{
    BOOL fits = OUITableViewAdjustContainingViewToExactlyFitContents(tableView, maximumHeight);
    
    // The superclass will have done this for the old size.
    self.contentSizeForViewInPopover = self.view.frame.size;

#if 0
    tableView.backgroundColor = nil;
    tableView.opaque = NO;
    
    [OUIInspectorBackgroundView configureTableViewBackground:tableView];
#endif
    
    return fits;
}

@end
