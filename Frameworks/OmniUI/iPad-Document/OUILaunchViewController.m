// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUILaunchViewController.h"

RCS_ID("$Id$")

@interface OUILaunchViewController ()

@property (nonatomic, strong) UIActivityIndicatorView *activityIndicatorView;

@end

@implementation OUILaunchViewController
{
    BOOL _permanentConstraintsAdded;
}

- (id)initWithActivityIndicatorStyle:(UIActivityIndicatorViewStyle)style color:(UIColor *)color;
{
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        // Custom initialization
        _activityIndicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:style];
        [_activityIndicatorView setTranslatesAutoresizingMaskIntoConstraints:NO];
        _activityIndicatorView.color = color;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:_activityIndicatorView];
    [_activityIndicatorView startAnimating];
    
    self.view.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"OUIDocumentPickerBackgroundTile.png"]];
    
    [self.view setNeedsUpdateConstraints];
}

- (void)updateViewConstraints;
{
    if (!_permanentConstraintsAdded) {
        [self.view addConstraint:[NSLayoutConstraint constraintWithItem:_activityIndicatorView attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeCenterX multiplier:1 constant:0]];
        [self.view addConstraint:[NSLayoutConstraint constraintWithItem:_activityIndicatorView attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeCenterY multiplier:1 constant:0]];
        
        _permanentConstraintsAdded = YES;
    }

    [super updateViewConstraints];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
