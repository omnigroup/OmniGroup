// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUINavigationController.h>

#import <OmniUI/OUINavigationBar.h>

RCS_ID("$Id$")

@implementation OUINavigationController

- (id)initWithRootViewController:(UIViewController *)rootViewController;
{
    self = [super initWithNavigationBarClass:[OUINavigationBar class] toolbarClass:nil];
    [self setViewControllers:[NSArray arrayWithObject:rootViewController] animated:NO];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(navigationBarChangedHeight:) name:OUINavigationBarHeightChangedNotification object:self.navigationBar];
    return self;
}

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#define BOTTOM_SPACING_BELOW_ACCESSORY 7.0

- (void)_updateAccessory:(UIViewController *)viewController operation:(UINavigationControllerOperation)operation animated:(BOOL)animated;
{    
    UIView *newAccessory = nil;
 
    if ([viewController respondsToSelector:@selector(navigationBarAccessoryView)])
        newAccessory = [viewController navigationBarAccessoryView];

    CGRect newAccessoryFrame = newAccessory.frame;
    CGRect barFrame = self.navigationBar.frame;
    CGFloat accessoryY = CGRectGetMaxY(barFrame);
    CGFloat barOriginY = CGRectGetMinY(barFrame);
    
    if (barOriginY) {
        barFrame.size.height += barOriginY;
        barFrame.origin.y = 0;
    }
    
    if (newAccessory)
        barFrame.size.height += CGRectGetHeight(newAccessoryFrame) + BOTTOM_SPACING_BELOW_ACCESSORY;

    if (!_accessoryBar) {
        _accessoryBar = [[UINavigationBar alloc] initWithFrame:barFrame];
        _accessoryBar.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleWidth;
        _accessoryBar.autoresizesSubviews = YES;
        [self.view addSubview:_accessoryBar];
    }
    
#define UNDO_SUPERCLASS_MUNGING 44.0

    UIScrollView *content = (UIScrollView *)viewController.view;
    if ([content isKindOfClass:[UIScrollView class]] && [viewController automaticallyAdjustsScrollViewInsets]) {
        UIEdgeInsets insets = content.contentInset;
        
        if (!insets.top && newAccessory) {
            insets.top = CGRectGetHeight(barFrame) - UNDO_SUPERCLASS_MUNGING;
            content.contentInset = insets;
        }
    }

    if (_accessory != nil && _accessory == newAccessory)
        return;
    
    if (newAccessory) {
        if ((newAccessory.autoresizingMask & UIViewAutoresizingFlexibleWidth) != 0) {
            newAccessoryFrame.origin.x = 0.0;
            newAccessoryFrame.size.width = _accessoryBar.frame.size.width;
            newAccessory.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
        } else {
            newAccessoryFrame.origin.x = floor((CGRectGetWidth(barFrame) - CGRectGetWidth(newAccessoryFrame)) / 2.0);
            newAccessory.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
        }
        newAccessoryFrame.origin.y = accessoryY;
        newAccessory.alpha = 0.1f;
        
        CGRect newStartFrame = newAccessoryFrame;
        newStartFrame.origin.y -= CGRectGetHeight(newAccessoryFrame);
        newAccessory.frame = newStartFrame;
        [_accessoryBar addSubview:newAccessory];
    }

    if (animated) {
        [UIView animateWithDuration:0.25 animations:^{
            _accessoryBar.frame = barFrame;
            newAccessory.frame = newAccessoryFrame;
            newAccessory.alpha = 1.0;

            CGRect oldOutFrame = _accessory.frame;
            oldOutFrame.origin.y -= CGRectGetHeight(oldOutFrame);
            _accessory.frame = oldOutFrame;
            _accessory.alpha = 0.0;
        } completion:^(BOOL finished) {
            [_accessory removeFromSuperview];
            self.accessory = newAccessory;
        }];
    } else {
        _accessoryBar.frame = barFrame;
        newAccessory.frame = newAccessoryFrame;
        newAccessory.alpha = 1.0f;
        [_accessory removeFromSuperview];
        self.accessory = newAccessory;
    }
    [self.navigationBar.superview bringSubviewToFront:_accessoryBar];
    [self.navigationBar.superview bringSubviewToFront:self.navigationBar];
}

- (void)navigationBarChangedHeight:(NSNotification *)notification;
{
    [_accessory removeFromSuperview];
    self.accessory = nil;
    [self _updateAccessory:[self.viewControllers lastObject] operation:UINavigationControllerOperationNone animated:NO];
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
