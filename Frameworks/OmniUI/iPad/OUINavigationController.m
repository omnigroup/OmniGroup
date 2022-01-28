// Copyright 2010-2021 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUINavigationController.h>

#import <OmniUI/OUISegmentedViewController.h>

@interface OUINavigationController ()

@property (strong, nonatomic) UIVisualEffectView *accessoryAndBackgroundBar;
@property (strong, nonatomic) UIView *accessory;

@property (nonatomic, strong) NSLayoutConstraint *accessoryAndBackgroundBarTopConstraint;
@property (nonatomic, strong) NSArray *topAndBottomConstraints;

@end

@implementation OUINavigationController

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad;
{
    [super viewDidLoad];
    
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
    self.accessoryAndBackgroundBar = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    self.accessoryAndBackgroundBar.translatesAutoresizingMaskIntoConstraints = NO;

    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] initWithBarAppearance:self.navigationBar.standardAppearance];
    appearance.backgroundEffect = blurEffect;
    self.navigationBar.scrollEdgeAppearance = appearance;

    [self.view addSubview:_accessoryAndBackgroundBar];
    [self _constrainAccessoryAndBackgroundView];
    self.accessoryAndBackgroundBar.hidden = YES;
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    if (self.navigationBar.superview == self.view && !self.isNavigationBarHidden)
        self.accessoryAndBackgroundBarTopConstraint.constant = CGRectGetMaxY(self.navigationBar.frame);
    else
        self.accessoryAndBackgroundBarTopConstraint.constant = 0;
}

#define BOTTOM_SPACING_BELOW_ACCESSORY 7.0

- (void)_constrainAccessoryAndBackgroundView
{
    self.accessoryAndBackgroundBarTopConstraint = [self.accessoryAndBackgroundBar.topAnchor constraintEqualToAnchor:self.view.topAnchor];

    NSArray *constraints = @[
         [self.accessoryAndBackgroundBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
         [self.accessoryAndBackgroundBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
         self.accessoryAndBackgroundBarTopConstraint,
     ];
    
    [NSLayoutConstraint activateConstraints:constraints];
}

- (void)_constrainNewAccessoryView:(UIView *)newAccessory
{
    [newAccessory.trailingAnchor constraintEqualToAnchor:self.accessoryAndBackgroundBar.safeAreaLayoutGuide.trailingAnchor].active = YES;
    [newAccessory.leadingAnchor constraintEqualToAnchor:self.accessoryAndBackgroundBar.safeAreaLayoutGuide.leadingAnchor].active = YES;
    
    NSLayoutConstraint *topConstraint = [newAccessory.topAnchor constraintEqualToAnchor:self.accessoryAndBackgroundBar.topAnchor constant:BOTTOM_SPACING_BELOW_ACCESSORY];
    NSLayoutConstraint *bottomConstraint = [newAccessory.bottomAnchor constraintEqualToAnchor:self.accessoryAndBackgroundBar.bottomAnchor constant:-BOTTOM_SPACING_BELOW_ACCESSORY];
    [NSLayoutConstraint deactivateConstraints:self.topAndBottomConstraints];
    self.topAndBottomConstraints = @[topConstraint, bottomConstraint];
    [NSLayoutConstraint activateConstraints:self.topAndBottomConstraints];
}

- (void)_animateSwitchFromOldAccessory:(UIView *)oldOne toNewAccessory:(UIView *)newOne {
    newOne.alpha = 0.0;
    [self.accessoryAndBackgroundBar layoutIfNeeded];
    [[self transitionCoordinator] animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  __nonnull context) {
        newOne.alpha = 1.0;
        oldOne.alpha = 0.0;
    } completion:^(id<UIViewControllerTransitionCoordinatorContext>  __nonnull context) {
        [oldOne removeFromSuperview];
    }];
}

#ifdef DEBUG_tom
- (void)setAdditionalSafeAreaInsets:(UIEdgeInsets)insets;
{
    NSLog(@"edgeInsets: %@", NSStringFromUIEdgeInsets(insets));
    [super setAdditionalSafeAreaInsets:insets];
}
#endif
    
- (void)_updateAccessory:(UIViewController *)viewController animated:(BOOL)animated;
{
    UIView *newAccessory = nil;
    if ([viewController respondsToSelector:@selector(navigationBarAccessoryView)]) {
        newAccessory = [viewController navigationBarAccessoryView];
    }
    
    if (self.accessory == newAccessory) {
        UIEdgeInsets insets = UIEdgeInsetsZero;
        if (newAccessory) {
            CGFloat height = [self.accessoryAndBackgroundBar systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
            insets.top += height + 3;
        }
        
        self.additionalSafeAreaInsets = insets;
        return;
    }
    
    UIEdgeInsets insets = UIEdgeInsetsZero;
    if (newAccessory) {
        newAccessory.translatesAutoresizingMaskIntoConstraints = NO;
        
        [self.accessoryAndBackgroundBar.contentView addSubview:newAccessory];
        [self _constrainNewAccessoryView:newAccessory];
        self.accessoryAndBackgroundBar.hidden = NO;

        CGFloat height = [self.accessoryAndBackgroundBar systemLayoutSizeFittingSize:UILayoutFittingCompressedSize].height;
        insets.top += height + 3;
    } else {
        self.accessoryAndBackgroundBar.hidden = YES;
    }
    
    UIView *oldAccessory = self.accessory;

    self.accessory = newAccessory;
    
    if (animated) {
        [self _animateSwitchFromOldAccessory:oldAccessory toNewAccessory:newAccessory];
    } else if (oldAccessory) {
        [oldAccessory removeFromSuperview];
    }

    viewController.additionalSafeAreaInsets = insets;
}

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated;
{
#ifdef DEBUG_tom
    NSLog(@"-[%@ pushViewController]", OBShortObjectDescription(self));
#endif
    [super pushViewController:viewController animated:animated];
    [self _updateAccessory:viewController animated:animated];
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated;
{
    UIViewController *result = [super popViewControllerAnimated:animated];
    [self _updateAccessory:[self.viewControllers lastObject] animated:animated];
    return result;
}

- (NSArray *)popToViewController:(UIViewController *)viewController animated:(BOOL)animated;
{
    NSArray *result = [super popToViewController:viewController animated:animated];
    [self _updateAccessory:viewController animated:animated];
    return result;
}

- (NSArray *)popToRootViewControllerAnimated:(BOOL)animated;
{
    if (self.viewControllers.count == 1)
        return [NSArray array];
    
    NSArray *result = [super popToRootViewControllerAnimated:animated];
    [self _updateAccessory:[self.viewControllers objectAtIndex:0] animated:animated];
    return result;
}

- (void)setViewControllers:(NSArray *)viewControllers;
{
    [super setViewControllers:viewControllers];
    [self _updateAccessory:[viewControllers lastObject]  animated:NO];
}

@end
