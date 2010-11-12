// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIInspectorStack.h"

#import <OmniUI/OUIInspectorSlice.h>
#import <OmniUI/OUIInspector.h>
#import <OmniBase/OmniBase.h>

#import <UIKit/UIPopoverController.h>

RCS_ID("$Id$");

@implementation OUIInspectorStack

- (void)dealloc;
{
    [_slices release];
    [super dealloc];
}

- (void)setInspector:(OUIInspector *)newInspector
{
    _nonretained_inspector = newInspector;
    if (newInspector.hasDismissButton) {
        self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:newInspector action:@selector(dismiss)];
    } else {
        self.navigationItem.rightBarButtonItem = nil;
    }
}
@synthesize inspector = _nonretained_inspector;

@synthesize slices = _slices;
- (void)setSlices:(NSArray *)slices;
{
    OBPRECONDITION(_nonretained_inspector);
    
    // TODO: Might want an 'animate' variant later.
    for (OUIInspectorSlice *slice in _slices) {
        if ([slice isViewLoaded])
            [slice.view removeFromSuperview];
        slice.inspector = nil;
    }
    [_slices release];
    
    _slices = [[NSArray alloc] initWithArray:slices];
    [self layoutSlices];
}

- (void)layoutSlices;
{
    // TODO: Don't provoke view loading?
    UIView *view = self.view;
    
    CGRect bounds = view.bounds;
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat yOffset = CGRectGetMinY(bounds);
    
    BOOL firstSlice = YES;
    const CGFloat kSliceSpacing = 5; // minimum space; each slice may have more space built into its xib based on its layout.
    
    for (OUIInspectorSlice *slice in _slices) {
        if (!firstSlice)
            yOffset += kSliceSpacing;
        else
            firstSlice = NO;
        
        slice.inspector = _nonretained_inspector;
        UIView *sliceView = slice.view;
        CGFloat sliceHeight = CGRectGetHeight(sliceView.frame);
        sliceView.frame = CGRectMake(CGRectGetMinX(bounds), yOffset, width, sliceHeight);
        yOffset += sliceHeight;
        [view addSubview:sliceView];
    }
    
    bounds.size.height = yOffset - CGRectGetMinY(bounds);
    
    self.contentSizeForViewInPopover = bounds.size;
}

- (void)updateInterfaceFromInspectedObjects;
{
    [_slices makeObjectsPerformSelector:_cmd];
}

#pragma mark UIViewController

- (void)loadView;
{
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, OUIInspectorContentWidth, 16)];
    self.view = view;
    [view release];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation;
{
    return YES;
}

@end
