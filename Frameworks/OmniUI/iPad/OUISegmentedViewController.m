// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUISegmentedViewController.h>

RCS_ID("$Id$")

@interface OUISegmentedViewController () <UIToolbarDelegate>

@property (nonatomic, strong) UIToolbar *toolbar;
@property (nonatomic, strong) UISegmentedControl *segmentedControl;

@end

@implementation OUISegmentedViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)awakeFromNib;
{
    [super awakeFromNib];
    
    [self _setupSegmentedControl];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    self.view.backgroundColor = [UIColor whiteColor];
    
    self.toolbar = [[UIToolbar alloc] init];
    self.toolbar.translatesAutoresizingMaskIntoConstraints = NO;
    self.toolbar.delegate = self;
    [self.view addSubview:self.toolbar];
    
    NSDictionary *views = NSDictionaryOfVariableBindings(_toolbar);
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_toolbar]|" options:0 metrics:nil views:views]];
    
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.toolbar attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.topLayoutGuide attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0.0]];
}

#pragma mark - Public API
- (void)setViewControllers:(NSArray *)viewControllers;
{
    OBPRECONDITION(viewControllers && [viewControllers count] > 0);
    
    if (_viewControllers == viewControllers) {
        return;
    }
    
    _viewControllers = [viewControllers copy];
    self.selectedViewController = [_viewControllers firstObject];
    
    [self _setupSegmentedControl];
}

- (void)setSelectedViewController:(UIViewController *)selectedViewController;
{
    OBPRECONDITION([_viewControllers containsObject:selectedViewController]);
    
    if (_selectedViewController == selectedViewController) {
        return;
    }
    
    // Remove currently selected view controller.
    if (_selectedViewController) {
        [_selectedViewController willMoveToParentViewController:nil];
        [_selectedViewController.view removeFromSuperview];
        [_selectedViewController removeFromParentViewController];
        _selectedViewController = nil;
    }
    
    _selectedViewController = selectedViewController;
    _selectedViewController.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Move in new view controller/view.
    [_selectedViewController willMoveToParentViewController:self];
    [self addChildViewController:_selectedViewController];

    [self.view addSubview:_selectedViewController.view];
    
    // Add constraints
    NSDictionary *views = @{ @"toolbar" : _toolbar, @"childView" : _selectedViewController.view };
    
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[childView]|"
                                                                      options:0
                                                                      metrics:nil
                                                                        views:views]];

    if ([_selectedViewController isKindOfClass:[UINavigationController class]]) {
        [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[toolbar][childView]|"
                                                                          options:0
                                                                          metrics:nil
                                                                            views:views]];
    }
    else {
        [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[childView]|"
                                                                          options:0
                                                                          metrics:nil
                                                                            views:views]];
    }
    
    [_selectedViewController didMoveToParentViewController:self];
    
    // Ensure that the segmented control is showing the correctly selected segment.
    NSUInteger selectedVCIndex = [self.viewControllers indexOfObject:_selectedViewController];
    self.segmentedControl.selectedSegmentIndex = selectedVCIndex;
    [self.view bringSubviewToFront:self.toolbar];
}

- (void)setSelectedIndex:(NSUInteger)selectedIndex;
{
    if (_selectedIndex == selectedIndex) {
        return;
    }
    
    _selectedIndex = selectedIndex;
    
    UIViewController *viewControllerToSelect = self.viewControllers[selectedIndex];
    self.selectedViewController = viewControllerToSelect;
}

#pragma mark - Private API
- (void)_setupSegmentedControl;
{
    NSMutableArray *segmentTitles = [NSMutableArray array];
    for (UIViewController *vc in self.viewControllers) {
        NSString *title = vc.title;
        OBASSERT(title);
        
        [segmentTitles addObject:title];
    }
    
    
    self.segmentedControl = [[UISegmentedControl alloc] initWithItems:segmentTitles];
    [self.segmentedControl setSelectedSegmentIndex:0];
    [self.segmentedControl addTarget:self action:@selector(_segmentValueChanged:) forControlEvents:UIControlEventValueChanged];
    
    UIBarButtonItem *leftFlexItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    UIBarButtonItem *segmentedControlItem = [[UIBarButtonItem alloc] initWithCustomView:self.segmentedControl];
    UIBarButtonItem *rightFlexItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    
    self.toolbar.items = @[leftFlexItem, segmentedControlItem, rightFlexItem];
//    self.navigationItem.titleView = self.segmentedControl;
}

- (void)_segmentValueChanged:(id)sender;
{
    OBPRECONDITION([sender isKindOfClass:[UISegmentedControl class]]);
    
    UISegmentedControl *segmentedControl = (UISegmentedControl *)sender;
    NSInteger selectedIndex = segmentedControl.selectedSegmentIndex;
    
    [self setSelectedIndex:selectedIndex];
}

#pragma mark - UIToolbarDelegate
- (UIBarPosition)positionForBar:(id <UIBarPositioning>)bar;
{
    if (bar == self.toolbar) {
        return UIBarPositionTopAttached;
    }

    return UIBarPositionAny;
}


@end
