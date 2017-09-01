// Copyright 2010-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIMenuController.h>

#import <OmniUI/OUIAppController.h>
#import <OmniUI/OUIMenuOption.h>

#import "OUIMenuOptionsController.h"
#import "OUIParameters.h"

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

@interface OUIMenuController (/*Private*/) <UINavigationControllerDelegate, UIPopoverPresentationControllerDelegate>
@end

@implementation OUIMenuController
{
    UINavigationController *_menuNavigationController;
    BOOL _isShowingAsPopover;

    UIColor *_presentingViewTintColor;
}

- (instancetype)init;
{
    if (!(self = [super init]))
        return nil;
    
    _navigationBarStyle = UIBarStyleDefault;
    _showsDividersBetweenOptions = YES;
    _alwaysShowsNavigationBar = NO;
    self.modalPresentationStyle = UIModalPresentationPopover;
    
    return self;
}

- (void)dealloc;
{
    // Do *NOT* call -popoverPresentationController here, since that will create one if it has already been cleared by the dismissal path, creating a retain cycle.
    //_menuNavigationController.popoverPresentationController.delegate = nil;

    _menuNavigationController.delegate = nil;
}

- (void)setTintColor:(UIColor *)tintColor;
{
    if (OFISEQUAL(_tintColor, tintColor))
        return;
    
    _tintColor = [tintColor copy];
    
    if (self.isViewLoaded)
        self.view.tintColor = [self _effectiveTintColor];
}

- (void)setMenuBackgroundColor:(UIColor *)menuBackgroundColor;
{
    if (OFISEQUAL(_menuBackgroundColor, menuBackgroundColor))
        return;
    
    _menuBackgroundColor = [menuBackgroundColor copy];
    
    if (self.isViewLoaded) {
        UIViewController *viewController = [_menuNavigationController.viewControllers firstObject];
        UITableView *tableView = OB_CHECKED_CAST(UITableView, viewController.view);
        tableView.backgroundColor = menuBackgroundColor;
    }
}

- (void)setMenuOptionBackgroundColor:(UIColor *)menuOptionBackgroundColor;
{
    if (OFISEQUAL(_menuOptionBackgroundColor, menuOptionBackgroundColor))
        return;
    
    _menuOptionBackgroundColor = [menuOptionBackgroundColor copy];
    
    if (self.isViewLoaded) {
        UIViewController *viewController = [_menuNavigationController.viewControllers firstObject];
        UITableView *tableView = OB_CHECKED_CAST(UITableView, viewController.view);
        [tableView reloadData];
    }
}

- (void)setMenuOptionSelectionColor:(UIColor *)menuOptionSelectionColor;
{
    if (OFISEQUAL(_menuOptionSelectionColor, menuOptionSelectionColor))
        return;
    
    _menuOptionSelectionColor = [menuOptionSelectionColor copy];
    
    if (self.isViewLoaded) {
        UIViewController *viewController = [_menuNavigationController.viewControllers firstObject];
        UITableView *tableView = OB_CHECKED_CAST(UITableView, viewController.view);
        [tableView reloadData];
    }
}

- (void)viewDidLoad;
{
    self.view.tintColor = [self _effectiveTintColor];
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

    _presentingViewTintColor = self.presentingViewController.view.tintColor;

    [_menuNavigationController setViewControllers:@[[self _makeTopMenu]] animated:NO];

    [super viewWillAppear:animated];
}

- (OUIMenuOptionsController *)_makeTopMenu;
{
    OUIMenuOptionsController *topMenu = [[OUIMenuOptionsController alloc] initWithController:self options:_topOptions];
    topMenu.tintColor = [self _effectiveTintColor];
    topMenu.sizesToOptionWidth = _sizesToOptionWidth;
    topMenu.textAlignment = _textAlignment;
    topMenu.showsDividersBetweenOptions = _showsDividersBetweenOptions;
    topMenu.title = self.title;
    
    UINavigationItem *navItem = topMenu.navigationItem;
    navItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(cancelButton:)];
    navItem.title = self.title;
    
    (void)[topMenu view]; // So we can ask it its preferred content size
    
    return topMenu;
}

- (nullable UIPopoverPresentationController *)popoverPresentationController;
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
    UIViewController *presentingViewController = _menuNavigationController.presentingViewController;

    if (_optionInvocationAction == OUIMenuControllerOptionInvocationActionDismiss) {
        // If the menu option wants to present something of its own, it will likely want to know where the menu was presented from.
        OBASSERT_NOTNULL(presentingViewController);

        [_menuNavigationController dismissViewControllerAnimated:YES completion:^{
            if (option.action != nil) {
                option.action(option, presentingViewController);
            }
        }];
    } else if (_optionInvocationAction == OUIMenuControllerOptionInvocationActionReload) {
        if ((option.action != nil) && option.isEnabled) {
            option.action(option, presentingViewController);
        }
        
        _menuNavigationController.viewControllers = @[[self _makeTopMenu]];
    }
}

#pragma mark - UINavigationControllerDelegate

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated;
{
    OBPRECONDITION(navigationController == _menuNavigationController);
    
    UINavigationBar *navigationBar = navigationController.navigationBar;
    if (self.navigationBarBackgroundColor)
        navigationBar.backgroundColor = self.navigationBarBackgroundColor;
    navigationBar.barStyle = self.navigationBarStyle;

    if (!_isShowingAsPopover)
        return;
    
    if (self.alwaysShowsNavigationBar) {
        navigationController.navigationBarHidden = NO;
    } else {
        NSArray *viewControllers = navigationController.viewControllers;
        BOOL atTopLevel = viewControllers.count > 0 && viewController == viewControllers[0];
        navigationController.navigationBarHidden = atTopLevel;
    }
    
    navigationController.preferredContentSize = viewController.preferredContentSize;
    self.preferredContentSize = navigationController.preferredContentSize;
}

#pragma mark - UIPopoverPresentationControllerDelegate

- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller;
{
    return UIModalPresentationFullScreen;
}

- (nullable UIViewController *)presentationController:(UIPresentationController *)controller viewControllerForAdaptivePresentationStyle:(UIModalPresentationStyle)style;
{
    _isShowingAsPopover = NO;
    _menuNavigationController.navigationBarHidden = NO;
    return self;
}

- (void)prepareForPopoverPresentation:(UIPopoverPresentationController *)popoverPresentationController;
{
    _isShowingAsPopover = YES;
    BOOL atTopLevel = _menuNavigationController.viewControllers.count < 2;
    _menuNavigationController.navigationBarHidden = atTopLevel;
    
    self.preferredContentSize = _menuNavigationController.preferredContentSize;
}

- (void)popoverPresentationControllerDidDismissPopover:(UIPopoverPresentationController *)popoverPresentationController;
{
    [self _discardMenu];
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
    // Do *NOT* call -popoverPresentationController here, since that will create one if it has already been cleared by the dismissal path, creating a retain cycle.
    //_menuNavigationController.popoverPresentationController.delegate = nil;
    _menuNavigationController = nil;
    _topOptions = @[];
}

- (void)_didFinish;
{
    if (_didFinish) {
        typeof(_didFinish) didFinish = _didFinish;
        _didFinish = nil;
        didFinish();
    }
}

- (UIColor *)_effectiveTintColor;
{
    return _tintColor ? _tintColor : _presentingViewTintColor;
}

@end

NS_ASSUME_NONNULL_END
