// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUINavigationController.h>

#import <OmniUI/OUINavigationBar.h>

RCS_ID("$Id$")

@interface OUINavigationController ()

@property (nonatomic, strong) NSArray *permanentConstraints;
@property (nonatomic, strong) NSArray *constraintsWithAccessoryView;
@property (nonatomic, strong) NSArray *constraintsWithNoAccessoryView;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraintOnAccessoryAndBackgroundView;
@property (nonatomic, strong) UIView *accessoryViewConstrainedWith;

@end

@implementation OUINavigationController

- (id)initWithRootViewController:(UIViewController *)rootViewController;
{
    self = [super initWithNavigationBarClass:[OUINavigationBar class] toolbarClass:nil];
    [self setViewControllers:[NSArray arrayWithObject:rootViewController]];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(navigationBarChangedHeight:) name:OUINavigationBarHeightChangedNotification object:self.navigationBar];
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews{
    // The accessoryAndBackgroundBar is an instance of UINavigationController which provides a place to put the (optional) accessory view provided by the displaying view controller and provides the appearance of a taller navigation bar.  The OUINavigationBar serves as our true navigation bar and is responsible for hiding its own background view.
    
    if (!_accessoryAndBackgroundBar) {
        [self _updateAccessory:self.topViewController operation:UINavigationControllerOperationNone animated:NO];
    }
    
#define UNDO_SUPERCLASS_MUNGING 44.0
    
    UIScrollView *content = (UIScrollView *)self.topViewController.view;
    if ([content isKindOfClass:[UIScrollView class]] && [self.topViewController automaticallyAdjustsScrollViewInsets]) {
        UIEdgeInsets insets = content.contentInset;
        
        if (!insets.top && self.accessory) {
            insets.top = CGRectGetHeight(_accessoryAndBackgroundBar.frame) - UNDO_SUPERCLASS_MUNGING;
            content.contentInset = insets;
        } else {
            // Further initial layout hackage for iOS 9
            CGRect rect = _accessoryAndBackgroundBar.frame;
            rect.size.height = insets.top;
            _accessoryAndBackgroundBar.frame = rect;
        }
    }

    [super viewDidLayoutSubviews];
}

#define BOTTOM_SPACING_BELOW_ACCESSORY 7.0

- (void)_updateAccessory:(UIViewController *)viewController operation:(UINavigationControllerOperation)operation animated:(BOOL)animated;
{
    // For now, this is where all constraints get set (it's where we used to calculate and set frames).  Seems to be working fine.
    
    UIView *newAccessory = nil;
 
    if ([viewController respondsToSelector:@selector(navigationBarAccessoryView)])
        newAccessory = [viewController navigationBarAccessoryView];
    
    
    CGRect newAccessoryFrame = newAccessory.frame;
    if (!_accessoryAndBackgroundBar) {
        CGRect barFrame = self.navigationBar.frame;
        CGFloat accessoryY = CGRectGetMaxY(barFrame);
        CGFloat barOriginY = CGRectGetMinY(barFrame);
        
        newAccessoryFrame.origin.y  = accessoryY;
        
        if (barOriginY) {
            barFrame.size.height += barOriginY;
            barFrame.origin.y = 0;
        }
        
        if (newAccessory)
            barFrame.size.height += CGRectGetHeight(newAccessoryFrame) + BOTTOM_SPACING_BELOW_ACCESSORY;
        
        _accessoryAndBackgroundBar = [[UINavigationBar alloc] initWithFrame:barFrame];
        _accessoryAndBackgroundBar.translatesAutoresizingMaskIntoConstraints = NO;
        [self.view addSubview:_accessoryAndBackgroundBar];
    }
    
    // set up constraints
    if (!self.permanentConstraints) {
        self.permanentConstraints = [self createPermanentConstraints];
        [NSLayoutConstraint activateConstraints:self.permanentConstraints];
    }
    if (!self.heightConstraintOnAccessoryAndBackgroundView) {
        self.heightConstraintOnAccessoryAndBackgroundView = [NSLayoutConstraint constraintWithItem:_accessoryAndBackgroundBar
                                                                                         attribute:NSLayoutAttributeHeight
                                                                                         relatedBy:NSLayoutRelationEqual
                                                                                            toItem:nil
                                                                                         attribute:NSLayoutAttributeNotAnAttribute
                                                                                        multiplier:1.0f
                                                                                          constant:self.navigationBar.frame.size.height];
        [NSLayoutConstraint activateConstraints:@[self.heightConstraintOnAccessoryAndBackgroundView]];
    }
    if (newAccessory) {
        newAccessory.translatesAutoresizingMaskIntoConstraints = NO;
        if (newAccessory != self.accessoryViewConstrainedWith) {
            self.constraintsWithAccessoryView = [self createConstraintsWithAccessoryView:newAccessory];
            self.accessoryViewConstrainedWith = newAccessory;
        }
        [_accessoryAndBackgroundBar addSubview:newAccessory];
        [NSLayoutConstraint activateConstraints:self.constraintsWithAccessoryView];
        [NSLayoutConstraint deactivateConstraints:self.constraintsWithNoAccessoryView];
        [self.accessoryAndBackgroundBar layoutIfNeeded];
        self.heightConstraintOnAccessoryAndBackgroundView.constant = CGRectGetMaxY(self.navigationBar.frame) + newAccessory.frame.size.height + BOTTOM_SPACING_BELOW_ACCESSORY;
    } else {
        self.accessoryViewConstrainedWith = nil;
        [NSLayoutConstraint activateConstraints:self.constraintsWithNoAccessoryView];
        self.heightConstraintOnAccessoryAndBackgroundView.constant = CGRectGetMaxY(self.navigationBar.frame);
    }
    
    if (_accessory != newAccessory) {
        if (animated) {
            [[self transitionCoordinator] animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>  __nonnull context) {
                [self.accessoryAndBackgroundBar layoutIfNeeded];
                newAccessory.alpha = 1.0;
                _accessory.alpha = 0.0;
            } completion:^(id<UIViewControllerTransitionCoordinatorContext>  __nonnull context) {
               [_accessory removeFromSuperview];
                self.accessory = newAccessory;
            }];
        } else {
            newAccessory.alpha = 1.0f;
            [_accessory removeFromSuperview];
            self.accessory = newAccessory;
        }
    }
    
    [self.navigationBar.superview bringSubviewToFront:_accessoryAndBackgroundBar];
    [self.navigationBar.superview bringSubviewToFront:self.navigationBar];
}

- (NSArray*)createPermanentConstraints{
    return @[ [NSLayoutConstraint constraintWithItem:_accessoryAndBackgroundBar
                                           attribute:NSLayoutAttributeLeft
                                           relatedBy:NSLayoutRelationEqual
                                              toItem:self.view
                                           attribute:NSLayoutAttributeLeft
                                          multiplier:1.0f
                                            constant:0.0f],
              
              [NSLayoutConstraint constraintWithItem:_accessoryAndBackgroundBar
                                           attribute:NSLayoutAttributeRight
                                           relatedBy:NSLayoutRelationEqual
                                              toItem:self.view
                                           attribute:NSLayoutAttributeRight
                                          multiplier:1.0f
                                            constant:0.0f],
              
              [NSLayoutConstraint constraintWithItem:_accessoryAndBackgroundBar
                                           attribute:NSLayoutAttributeTop
                                           relatedBy:NSLayoutRelationEqual
                                              toItem:self.view
                                           attribute:NSLayoutAttributeTop
                                          multiplier:1.0f
                                            constant:0.0f]
              ];
}

- (NSArray*)createConstraintsWithAccessoryView:(UIView*)accessoryView{
    return @[ [NSLayoutConstraint constraintWithItem:_accessoryAndBackgroundBar
                                           attribute:NSLayoutAttributeBottom
                                           relatedBy:NSLayoutRelationEqual
                                              toItem:accessoryView
                                           attribute:NSLayoutAttributeBottom
                                          multiplier:1.0f
                                            constant:BOTTOM_SPACING_BELOW_ACCESSORY],
              [NSLayoutConstraint constraintWithItem:accessoryView
                                           attribute:NSLayoutAttributeCenterX
                                           relatedBy:NSLayoutRelationEqual
                                              toItem:_accessoryAndBackgroundBar
                                           attribute:NSLayoutAttributeCenterX
                                          multiplier:1.0f
                                            constant:0.0f]
              ];
}

- (void)navigationBarChangedHeight:(NSNotification *)notification;
{
    if (self.accessoryViewConstrainedWith) {
        self.heightConstraintOnAccessoryAndBackgroundView.constant = CGRectGetMaxY(self.navigationBar.frame) + self.accessoryViewConstrainedWith.frame.size.height + BOTTOM_SPACING_BELOW_ACCESSORY;
    } else {
        self.heightConstraintOnAccessoryAndBackgroundView.constant = CGRectGetMaxY(self.navigationBar.frame);
    }
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

@end
