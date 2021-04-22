// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIExportProgressViewController.h"

RCS_ID("$Id$")

@implementation OUIExportProgressViewController
{
    BOOL _translucentBackground;
    UIActivityIndicatorView *_activityIndicator;
}

- initWithTranslucentBackground:(BOOL)translucentBackground;
{
    self = [super initWithNibName:nil bundle:nil];

    _translucentBackground = translucentBackground;

    return self;
}

- (void)loadView;
{
    UIView *view = [[UIView alloc] init];

    UIColor *backgroundColor = [UIColor systemBackgroundColor];
    if (_translucentBackground) {
        backgroundColor = [backgroundColor colorWithAlphaComponent:0.75];
    }
    view.backgroundColor = backgroundColor;
    self.view = view;

    _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];

    [view addSubview:_activityIndicator];
    [_activityIndicator startAnimating];
}

- (void)viewDidLayoutSubviews;
{
    [super viewDidLayoutSubviews];

    // Figure out center of overlay view.
    CGPoint overlayCenter = self.view.center;
//    CGPoint actualCenterForActivityIndicator = (CGPoint){
//        .x = overlayCenter.x - view.frame.origin.x,
//        .y = overlayCenter.y - view.frame.origin.y
//    };

    _activityIndicator.center = overlayCenter;
}

@end
