// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIMenuController.h>

#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIMenuOption.h>

#import <UIKit/UIPopoverController.h>

#import "OUIMenuOptionsController.h"
#import "OUIParameters.h"

RCS_ID("$Id$");

@interface OUIMenuController (/*Private*/) <UINavigationControllerDelegate, UIPopoverPresentationControllerDelegate>
@end

@implementation OUIMenuController
{
    UINavigationController *_menuNavigationController;
    BOOL _isShowingAsPopover;
}

- (instancetype)init;
{
    if (!(self = [super init]))
        return nil;
    
    _showsDividersBetweenOptions = YES;
    self.modalPresentationStyle = UIModalPresentationPopover;
    
    return self;
}

- (void)dealloc;
{
    _menuNavigationController.popoverPresentationController.delegate = nil;
    _menuNavigationController.delegate = nil;
}

- (void)setTintColor:(UIColor *)tintColor;
{
    if (OFISEQUAL(_tintColor, tintColor))
        return;
    
    _tintColor = [tintColor copy];
    
    if (self.isViewLoaded)
        self.view.tintColor = _tintColor;
}

- (void)viewDidLoad;
{
    self.view.tintColor = _tintColor;
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated;
{
    if (!_menuNavigationController) {
        _menuNavigationController = [[UINavigationController alloc] init];
        _menuNavigationController.delegate = self;
        _menuNavigationController.modalPresentationStyle = UIModalPresentationPopover;
        self.wrappedViewController = _menuNavigationController;
    }
    
    [_menuNavigationController setViewControllers:@[[self _makeTopMenu]] animated:NO];

    [super viewWillAppear:animated];
}

- (OUIMenuOptionsController *)_makeTopMenu;
{
    OUIMenuOptionsController *topMenu = [[OUIMenuOptionsController alloc] initWithController:self options:_topOptions];
    topMenu.tintColor = _tintColor;
    topMenu.sizesToOptionWidth = _sizesToOptionWidth;
    topMenu.textAlignment = _textAlignment;
    topMenu.showsDividersBetweenOptions = _showsDividersBetweenOptions;
    topMenu.title = self.title;
    
    UINavigationItem *navItem = topMenu.navigationItem;
    navItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(cancelButton:)];
    navItem.title = self.title;
    
    [topMenu view]; // So we can ask it its preferred content size
    
    return topMenu;
}

- (UIPopoverPresentationController *)popoverPresentationController;
{
    UIPopoverPresentationController *controller = [super popoverPresentationController];
    
    // Set up a default delegate that has the correct behavior, but only do it once per unique popover presentation controller in case a client of this class wants to change it.
    static char *delegateKey = "com.omnigroup.OUIMenuController.DefaultPopoverPresentationControllerDelegate";
    if (objc_getAssociatedObject(controller, delegateKey) == nil) {
        objc_setAssociatedObject(controller, delegateKey, self, OBJC_ASSOCIATION_ASSIGN);
        controller.delegate = self;
    }
    
    return controller;
}

// Called by OUIMenuOptionsController
- (void)dismissAndInvokeOption:(OUIMenuOption *)option;
{
    {
        if (_optionInvocationAction == OUIMenuControllerOptionInvocationActionDismiss) {
            [_menuNavigationController dismissViewControllerAnimated:YES completion:^{if (option.action != nil) option.action();}];
        } else if (_optionInvocationAction == OUIMenuControllerOptionInvocationActionReload) {
            if ((option.action != nil) && option.isEnabled) {
                option.action();
            }
            
            _menuNavigationController.viewControllers = @[[self _makeTopMenu]];
        }
    }
}

#pragma mark - UINavigationControllerDelegate

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated;
{
    OBPRECONDITION(navigationController == _menuNavigationController);
    
    if (!_isShowingAsPopover)
        return;
    
    NSArray *viewControllers = navigationController.viewControllers;
    BOOL atTopLevel = viewControllers.count > 0 && viewController == viewControllers[0];
    navigationController.navigationBarHidden = atTopLevel;
    
    navigationController.preferredContentSize = viewController.preferredContentSize;
    self.preferredContentSize = navigationController.preferredContentSize;
}

#pragma mark - UIPopoverPresentationControllerDelegate

- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller;
{
    return UIModalPresentationFullScreen;
}

- (UIViewController *)presentationController:(UIPresentationController *)controller viewControllerForAdaptivePresentationStyle:(UIModalPresentationStyle)style;
{
    OBPRECONDITION(controller.presentedViewController == _menuNavigationController);
    OBPRECONDITION(_isShowingAsPopover, "At some point we transitioned to an adaptive presentation without getting notified");
    
    _isShowingAsPopover = NO;
    _menuNavigationController.navigationBarHidden = NO;
    return self;
}

- (void)prepareForPopoverPresentation:(UIPopoverPresentationController *)popoverPresentationController;
{
    OBPRECONDITION(popoverPresentationController.presentedViewController == _menuNavigationController);
    OBPRECONDITION(!_isShowingAsPopover, "At some point we transitioned to being a popover without getting notified");
    
    _isShowingAsPopover = YES;
    BOOL atTopLevel = _menuNavigationController.viewControllers.count < 2;
    _menuNavigationController.navigationBarHidden = atTopLevel;
    
    self.preferredContentSize = _menuNavigationController.preferredContentSize;
}

- (void)popoverPresentationControllerDidDismissPopover:(UIPopoverPresentationController *)popoverPresentationController;
{
    [self _discardMenu];

    // Don't keep the popover controller alive needlessly.
    [[OUIAppController controller] forgetPossiblyVisiblePopoverIfAlreadyHidden];
    
    [self _didFinish];
}

- (void)cancelButton:(id)sender;
{
    [_menuNavigationController dismissViewControllerAnimated:YES completion:^{
        [self _discardMenu];
        [self _didFinish];
    }];
}

#pragma mark - Private

- (void)_discardMenu;
{
    _menuNavigationController.popoverPresentationController.delegate = nil;
    _menuNavigationController = nil;
    _topOptions = nil;
}

- (void)_didFinish;
{
    if (_didFinish) {
        typeof(_didFinish) didFinish = _didFinish;
        _didFinish = nil;
        didFinish();
    }
}

@end
