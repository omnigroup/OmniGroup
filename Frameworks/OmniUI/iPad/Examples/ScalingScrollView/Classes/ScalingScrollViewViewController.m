// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "ScalingScrollViewViewController.h"

#import "ScalingView.h"

RCS_ID("$Id$")

@implementation ScalingScrollViewViewController

- (void)dealloc;
{
    [_scalingView release];
    [super dealloc];
}

@synthesize scalingView = _scalingView;


#pragma mark -
#pragma mark UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView;
{
    return _scalingView;
}


#pragma mark -
#pragma mark OUIScalingViewController subclass

- (CGSize)unscaledContentSize;
{
    return CGSizeMake(400, 300);
}

#pragma mark -
#pragma mark UIViewController subclass

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
{
    return YES;
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    [self sizeInitialViewSizeFromUnscaledContentSize];
}

- (void)viewDidUnload;
{
    [_scalingView release];
    _scalingView = nil;
    
    [super viewDidUnload];
}

@end
