// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUINavigationController.h>

#import <OmniUI/OUISegmentedViewController.h>
#import <OmniUI/OUIThemedAppearance.h>

RCS_ID("$Id$")

@interface OUINavigationController ()

@property (nonatomic, strong) NSArray *permanentConstraints;
@property (nonatomic, strong) NSArray *topAndBottomConstraints;

@end

@implementation OUINavigationController

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#define BOTTOM_SPACING_BELOW_ACCESSORY 7.0

- (void)_constrainAccessoryAndBackgroundView
{
    self.accessoryAndBackgroundBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.accessoryAndBackgroundBar.trailingAnchor constraintEqualToAnchor:self.navigationBar.trailingAnchor].active = YES;
    [self.accessoryAndBackgroundBar.leadingAnchor constraintEqualToAnchor:self.navigationBar.leadingAnchor].active = YES;
    [self.accessoryAndBackgroundBar.topAnchor constraintEqualToAnchor:self.navigationBar.bottomAnchor].active = YES;
}

- (void)_constrainNewAccessoryView:(UIView *)newAccessory
{
    [newAccessory.centerXAnchor constraintEqualToAnchor:self.accessoryAndBackgroundBar.centerXAnchor].active = YES;
    NSLayoutConstraint *topConstraint = [newAccessory.topAnchor constraintEqualToAnchor:self.accessoryAndBackgroundBar.topAnchor constant:BOTTOM_SPACING_BELOW_ACCESSORY];
    NSLayoutConstraint *bottomConstraint = [newAccessory.bottomAnchor constraintEqualToAnchor:self.accessoryAndBackgroundBar.bottomAnchor constant:-BOTTOM_SPACING_BELOW_ACCESSORY];
    [NSLayoutConstraint deactivateConstraints:self.topAndBottomConstraints];
    self.topAndBottomConstraints = @[topConstraint, bottomConstraint];
    [NSLayoutConstraint activateConstraints:self.topAndBottomConstraints];
}

- (void)_addNewAccessoryView:(UIView *)newAccessory animated:(BOOL)animated
{
    if (self.accessory != newAccessory) {
        if (newAccessory) {
            newAccessory.translatesAutoresizingMaskIntoConstraints = NO;
            
            [self.accessoryAndBackgroundBar addSubview:newAccessory];
            [self _constrainNewAccessoryView:newAccessory];
            
            [self.accessoryAndBackgroundBar layoutIfNeeded];
        } else {
            [self.accessory removeFromSuperview];
            self.accessoryAndBackgroundBar.hidden = YES;
        }
        
        UIView *oldAccessory = self.accessory;
        self.accessory = newAccessory;
        
        if (animated) {
            [self _animateSwitchFromOldAccessory:oldAccessory toNewAccessory:newAccessory];
        } else {
            [oldAccessory removeFromSuperview];
        }
    }
}

- (void)_animateSwitchFromOldAccessory:(UIView *)oldOne toNewAccessory:(UIView *)newOne {
    newOne.alpha = 0.0;
    [[self transitionCoordinator] animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  __nonnull context) {
        [self.accessoryAndBackgroundBar layoutIfNeeded];
        newOne.alpha = 1.0;
        oldOne.alpha = 0.0;
    } completion:^(id<UIViewControllerTransitionCoordinatorContext>  __nonnull context) {
        [oldOne removeFromSuperview];
    }];
}

- (void)_updateAccessory:(UIViewController *)viewController operation:(UINavigationControllerOperation)operation animated:(BOOL)animated;
{
    // For now, this is where all constraints get set (it's where we used to calculate and set frames).  Seems to be working fine.
    if ([viewController wantsHiddenNavigationBar]) {
        [self.accessory removeFromSuperview];
        self.accessoryAndBackgroundBar.hidden = YES;
        return;
    }
 
    if (![viewController respondsToSelector:@selector(navigationBarAccessoryView)]) {
        [self.accessory removeFromSuperview];
        self.accessory = nil;
        self.accessoryAndBackgroundBar.hidden = YES;
    } else {
        if (!self.navigationBar.superview)
            return;
        
        UIView *newAccessory = [viewController navigationBarAccessoryView];
        
        if (!_accessoryAndBackgroundBar) {
            self.accessoryAndBackgroundBar = [[UINavigationBar alloc] initWithFrame:self.navigationBar.frame];
            [self.navigationBar.superview addSubview:_accessoryAndBackgroundBar];
            [self _constrainAccessoryAndBackgroundView];
        } else {
            self.accessoryAndBackgroundBar.hidden = NO;
        }
        
        [self _addNewAccessoryView:newAccessory animated:animated];
    }
}

- (CGFloat)heightOfAccessoryBar {
    if (self.accessory) {
        return self.accessoryAndBackgroundBar.frame.size.height;
    }
    return 0.0f;
}

- (void)setNavigationBarHidden:(BOOL)hidden animated:(BOOL)animated;
{
    [super setNavigationBarHidden:hidden animated:animated];
    [self _updateAccessory:self.topViewController operation:UINavigationControllerOperationPush animated:animated];
}

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated;
{
    [super pushViewController:viewController animated:animated];
    [self _updateAccessory:viewController operation:UINavigationControllerOperationPush animated:animated];
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated;
{
    UIViewController *result = [super popViewControllerAnimated:animated];
    [self _updateAccessory:[self.viewControllers lastObject] operation:UINavigationControllerOperationPop animated:animated];
    return result;
}

- (NSArray *)popToViewController:(UIViewController *)viewController animated:(BOOL)animated;
{
    NSArray *result = [super popToViewController:viewController animated:animated];
    [self _updateAccessory:viewController operation:UINavigationControllerOperationPop animated:animated];
    return result;
}

- (NSArray *)popToRootViewControllerAnimated:(BOOL)animated;
{
    if (self.viewControllers.count == 1)
        return [NSArray array];
    
    NSArray *result = [super popToRootViewControllerAnimated:animated];
    [self _updateAccessory:[self.viewControllers objectAtIndex:0] operation:UINavigationControllerOperationPop animated:animated];
    return result;
}

- (void)setViewControllers:(NSArray *)viewControllers;
{
    [super setViewControllers:viewControllers];
    [self _updateAccessory:[viewControllers lastObject] operation:UINavigationControllerOperationPush animated:NO];
}

#pragma mark - OUIThemedAppearanceClient

- (NSArray <id<OUIThemedAppearanceClient>> *)themedAppearanceChildClients;
{
    NSArray <id<OUIThemedAppearanceClient>> *clients = [super themedAppearanceChildClients];
    clients = [clients arrayByAddingObjectsFromArray:self.viewControllers];
    return clients;
}

@end
