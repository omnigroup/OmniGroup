// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIInspectorDetailSlice.h>
#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIInspector.h>
#import <UIKit/UIPopoverController.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@implementation OUIInspectorDetailSlice

- (OUIInspector *)inspector;
{
    OBPRECONDITION(_nonretained_slice);
    return _nonretained_slice.inspector;
}

- (void)setSlice:(OUIInspectorSlice *)aSlice
{
    _nonretained_slice = aSlice;
    
    OUIInspector *inspector = aSlice.inspector;
    if (inspector && inspector.hasDismissButton) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:inspector action:@selector(dismiss)];
    } else {
        self.navigationItem.rightBarButtonItem = nil;
    }
}
@synthesize slice = _nonretained_slice;

- (void)updateInterfaceFromInspectedObjects;
{
    
}

- (void)wasPushed;
{
    // for subclasses
}

#pragma mark UIViewController

static void _setup(OUIInspectorDetailSlice *self)
{
    UIView *view = self.view;
    // We edit with a black background so we can see stuff in IB, but need to turn that off here to look right in the popover.
    view.opaque = NO;
    view.backgroundColor = nil;
    
    if (view) {
        // Keep our original size in the popover.
        self.contentSizeForViewInPopover = view.frame.size;
        
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

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation;
{
    return YES;
}

@end
